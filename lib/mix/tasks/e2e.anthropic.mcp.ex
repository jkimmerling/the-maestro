defmodule Mix.Tasks.E2e.Anthropic.Mcp do
  use Mix.Task
  @shortdoc "E2E: Anthropic + MCP tools + system blocks + no-duplicates"

  @moduledoc """
  Validates Anthropic integration with MCP tool exposure and function calling.

  Usage:
      mix e2e.anthropic.mcp --anthropic personal_oauth_anthropic
  """

  alias TheMaestro.{Auth, Chat, Conversations, MCP}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    session_name = get_session_name(args)
    sa = get_saved_auth!(session_name)
    session = get_or_create_session(sa)
    session_id = session.id

    ensure_mcps!(session_id)

    System.put_env("HTTP_DEBUG", "1")
    Chat.subscribe(session_id)

    # Telemetry shape capture (real request)
    {:ok, cap} = Agent.start_link(fn -> nil end)
    handler_id = attach_anthropic_shape_handler(cap)

    prompt =
      "please use the context7 mcp to resolve \"elixir ecto\" and then get docs for \"changesets\""

    pre = message_count(session_id)
    {:ok, turn} = Chat.start_turn(session_id, nil, prompt)

    final = collect_turn_outcome(session_id, turn.stream_id)
    validate_outcome!(final)
    validate_normalization!(session_id, pre)

    meta = wait_for_meta(cap)

    unless is_integer(meta[:system_blocks]) and meta[:system_blocks] >= 0,
      do: Mix.raise("Anthropic system blocks missing or wrong shape")

    :telemetry.detach(handler_id)

    Mix.shell().info(
      "E2E OK: Anthropic — tools visible, function call observed, no-duplicates verified."
    )
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
        state2 =
          case ev do
            %{type: :function_call, tool_calls: calls} when is_list(calls) ->
              %{state | saw_fc?: state.saw_fc? or calls != []}

            %{type: :done} ->
              %{state | finalized?: true}

            _ ->
              state
          end

        if state2.finalized?, do: state2, else: wait(session_id, stream_id, state2, deadline)

      _ ->
        wait(session_id, stream_id, state, deadline)
    after
      1000 -> wait(session_id, stream_id, state, deadline)
    end
  end

  defp validate_outcome!(%{finalized?: true, saw_fc?: true}), do: :ok
  defp validate_outcome!(%{finalized?: false}), do: Mix.raise("Stream did not finalize")
  defp validate_outcome!(%{saw_fc?: false}), do: Mix.raise("Model did not call any tool")

  # ===== Instruction/system blocks assertion =====
  defp attach_anthropic_shape_handler(agent) do
    id = "e2e-anthropic-shape-" <> Integer.to_string(System.unique_integer([:positive]))

    :telemetry.attach(
      id,
      [:providers, :anthropic, :request_built],
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

  # ===== Normalization assertion =====
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

  defp get_session_name(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [anthropic: :string])
    session_name = opts[:anthropic] || System.get_env("ANTHROPIC_SESSION_NAME")

    unless is_binary(session_name) and session_name != "" do
      Mix.raise("Provide --anthropic <saved_auth_name> or ANTHROPIC_SESSION_NAME env var")
    end

    session_name
  end

  defp get_saved_auth!(session_name) do
    sa =
      Auth.get_by_provider_and_name(:anthropic, :oauth, session_name) ||
        Auth.get_by_provider_and_name(:anthropic, :api_key, session_name)

    unless sa, do: Mix.raise("No saved_authentication for anthropic name=#{session_name}")
    sa
  end

  defp get_or_create_session(sa) do
    case Conversations.latest_session_for_auth_id(sa.id) do
      existing when not is_nil(existing) ->
        existing

      _ ->
        {:ok, created} =
          Conversations.create_session(%{
            auth_id: sa.id,
            model_id: "claude-3-5-sonnet-latest",
            working_dir: File.cwd!()
          })

        created
    end
  end
end
