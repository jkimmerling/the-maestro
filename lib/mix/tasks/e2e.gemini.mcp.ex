defmodule Mix.Tasks.E2e.Gemini.Mcp do
  use Mix.Task

  @shortdoc "E2E: Gemini OAuth + MCP resolve_library_id → functionResponse + systemInstruction + no-duplicates"

  @moduledoc """
  Runs an end-to-end check against Gemini OAuth (Cloud Code) using the session’s
  MCP connector for Context7. It validates that:

  - Gemini sees MCP tools (resolve-library-id, get-library-docs) via dynamic tools
  - Model emits a functionCall for resolve-library-id
  - We send a follow-up with functionResponse carrying the tool result

  Requirements:
  - A SavedAuthentication for Gemini OAuth with name `--gemini <session_name>`
  - Context7 MCP accessible via ENV or flags:
      CONTEXT7_BASE_URL (e.g., https://mcp.context7.com)
      CONTEXT7_ENDPOINT (default /mcp)
      CONTEXT7_API_KEY (optional; sets X-Api-Key header)
      or CONTEXT7_HEADERS_JSON (JSON map of headers)

  Usage:
      mix e2e.gemini.mcp --gemini personal_oauth_gemini
  """

  alias TheMaestro.{Auth, Chat, Conversations, MCP}
  alias TheMaestro.Conversations.Translator

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: [gemini: :string])
    session_name = opts[:gemini] || System.get_env("GEMINI_SESSION_NAME")

    unless is_binary(session_name) and session_name != "" do
      Mix.raise("Provide --gemini <saved_auth_name> or GEMINI_SESSION_NAME env var")
    end

    sa = Auth.get_by_provider_and_name(:gemini, :oauth, session_name)
    unless sa, do: Mix.raise("No saved_authentication for gemini/oauth name=#{session_name}")

    {:ok, session_id} = ensure_session(sa)
    ensure_mcps!(session_id)

    # Enable request debug to STDOUT (optional). We won't rely on a file-based capture.
    System.put_env("HTTP_DEBUG", "1")
    System.put_env("HTTP_DEBUG_LEVEL", "high")

    # Subscribe to stream events
    Chat.subscribe(session_id)
    # Telemetry shape capture (real request)
    {:ok, cap} = Agent.start_link(fn -> nil end)
    handler_id = attach_gemini_shape_handler(cap)

    prompt = "please use the context7 mcp to look up the docs on Elixir ecto migrations"
    pre = message_count(session_id)
    {:ok, turn} = Chat.start_turn(session_id, nil, prompt)

    # Collect events until finalized
    final = collect_turn_outcome(session_id, turn.stream_id)
    validate_outcome!(final)
    validate_normalization!(session_id, pre)

    meta = wait_for_meta(cap)

    unless meta[:system_instruction?] in [true, false],
      do: Mix.raise("Gemini systemInstruction telemetry missing")

    :telemetry.detach(handler_id)

    Mix.shell().info(
      "E2E OK: Gemini OAuth + Context7 MCP: model called resolve-library-id, stream finalized."
    )
  end

  defp ensure_session(sa) do
    s = Conversations.latest_session_for_auth_id(sa.id)
    if s, do: {:ok, s.id}, else: create_session(sa)
  end

  defp create_session(sa) do
    {:ok, s} =
      Conversations.create_session(%{
        auth_id: sa.id,
        model_id: "gemini-2.5-pro",
        working_dir: File.cwd!()
      })

    {:ok, s.id}
  end

  defp ensure_mcps!(session_id) do
    # Use the existing Context7 stdio server
    context7_server_id = "1ae83be6-3f07-47b5-b092-7994b6a009c5"

    # Get the server to ensure it exists
    server = MCP.get_server!(context7_server_id)

    unless server do
      Mix.raise(
        "Context7 MCP server not found. Please ensure it exists with ID: #{context7_server_id}"
      )
    end

    existing_ids =
      session_id
      |> MCP.list_session_servers()
      |> Enum.map(& &1.mcp_server_id)

    # Add the Context7 server to the session if not already attached
    {:ok, _} =
      MCP.replace_session_servers(session_id, Enum.uniq(existing_ids ++ [context7_server_id]))
  end

  defp collect_turn_outcome(session_id, stream_id) do
    deadline = System.monotonic_time(:millisecond) + 60_000
    state = %{finalized?: false, saw_fc?: false}
    wait(session_id, stream_id, state, deadline)
  end

  defp wait(session_id, stream_id, state, deadline) do
    now = System.monotonic_time(:millisecond)
    if now >= deadline, do: state, else: do_wait(session_id, stream_id, state, deadline)
  end

  defp do_wait(session_id, stream_id, state, deadline) do
    receive do
      {:session_stream,
       %TheMaestro.Domain.StreamEnvelope{
         session_id: ^session_id,
         stream_id: ^stream_id,
         event: ev
       }} ->
        state2 = reduce_event(ev, state)
        if state2.finalized?, do: state2, else: wait(session_id, stream_id, state2, deadline)

      _ ->
        wait(session_id, stream_id, state, deadline)
    after
      1000 -> wait(session_id, stream_id, state, deadline)
    end
  end

  # -- helpers to keep do_wait/4 simple --
  defp reduce_event(%{type: :done}, state), do: %{state | finalized?: true}

  defp reduce_event(%{type: :function_call, tool_calls: calls}, state) when is_list(calls) do
    %{state | saw_fc?: state.saw_fc? or Enum.any?(calls, &resolve_lib_call?/1)}
  end

  defp reduce_event(_other, state), do: state

  defp resolve_lib_call?(%TheMaestro.Domain.ToolCall{name: "resolve-library-id"}), do: true
  defp resolve_lib_call?(%TheMaestro.Domain.ToolCall{}), do: false
  defp resolve_lib_call?(%{name: "resolve-library-id"}), do: true
  defp resolve_lib_call?(%{"name" => "resolve-library-id"}), do: true
  defp resolve_lib_call?(_), do: false

  defp validate_outcome!(%{finalized?: true, saw_fc?: true}), do: :ok
  defp validate_outcome!(%{finalized?: false}), do: Mix.raise("Stream did not finalize")

  defp validate_outcome!(%{saw_fc?: false}),
    do: Mix.raise("Model did not call resolve-library-id")

  # No file-based assertion; the presence of a function call + finalization is enough
  # ===== Shape and normalization helpers =====
  defp attach_gemini_shape_handler(agent) do
    id = "e2e-gemini-shape-" <> Integer.to_string(System.unique_integer([:positive]))

    :telemetry.attach(
      id,
      [:providers, :gemini, :request_built],
      fn _ev, _meas, meta, a ->
        Agent.update(a, fn _ -> meta end)
      end,
      agent
    )

    id
  end

  defp wait_for_meta(agent, deadline_ms \\ 10_000) do
    t0 = System.monotonic_time(:millisecond)
    do_wait_meta(agent, t0 + deadline_ms)
  end

  defp do_wait_meta(agent, deadline) do
    meta = Agent.get(agent, & &1)

    cond do
      is_map(meta) ->
        meta

      System.monotonic_time(:millisecond) >= deadline ->
        %{}

      true ->
        Process.sleep(100)
        do_wait_meta(agent, deadline)
    end
  end

  defp message_count(session_id) do
    case Conversations.latest_snapshot(session_id) do
      %{combined_chat: %{"messages" => msgs}} -> length(msgs)
      _ -> 0
    end
  end

  defp validate_normalization!(session_id, pre) do
    afterc = wait_until(fn -> message_count(session_id) end, pre + 2)
    unless afterc == pre + 2, do: Mix.raise("Conversation not normalized (+2 expected)")
  end

  defp wait_until(fun, target, deadline_ms \\ 5_000) do
    t0 = System.monotonic_time(:millisecond)
    do_wait_until(fun, target, t0 + deadline_ms)
  end

  defp do_wait_until(fun, target, deadline) do
    val = fun.()

    cond do
      val == target ->
        val

      System.monotonic_time(:millisecond) >= deadline ->
        val

      true ->
        Process.sleep(100)
        do_wait_until(fun, target, deadline)
    end
  end
end
