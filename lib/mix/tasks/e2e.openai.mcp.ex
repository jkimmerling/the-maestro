defmodule Mix.Tasks.E2e.Openai.Mcp do
  use Mix.Task
  @shortdoc "E2E: OpenAI (OAuth/API) + MCP tools + instruction-shape + no-duplicates"

  @moduledoc """
  Validates OpenAI integration:
  - MCP tool exposure + function calling
  - Instruction shape per auth: OAuth => string; API key => list/segments
  - Conversation normalization: delta +2 messages per completed turn (user+assistant), no duplicate appends

  Usage:
      mix e2e.openai.mcp --openai personal_oauth_openai [--api enterprise_api_name]
  """

  alias TheMaestro.{Chat, Conversations, MCP}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: [openai: :string, api: :string])
    session_name = opts[:openai] || System.get_env("OPENAI_SESSION_NAME")
    _api_name = opts[:api] || System.get_env("OPENAI_API_NAME")

    unless is_binary(session_name) and session_name != "" do
      Mix.raise("Provide --openai <saved_auth_name> or OPENAI_SESSION_NAME env var")
    end

    # Ensure a session exists for this saved auth
    {:ok, session_id} = ensure_session(session_name)
    ensure_mcps!(session_id)

    # Attach telemetry to assert instruction shape on real request
    {:ok, cap} = Agent.start_link(fn -> nil end)
    handler_id = attach_openai_shape_handler(cap)

    Chat.subscribe(session_id)

    prompt = "please use the context7 mcp to look up elixir ecto and tell me about Multi"

    pre_count = message_count(session_id)
    {:ok, turn} = Chat.start_turn(session_id, nil, prompt)

    final = collect_turn_outcome(session_id, turn.stream_id)
    validate_outcome!(final)
    validate_normalization!(session_id, pre_count)

    # Validate instruction shape from telemetry
    meta = wait_for_meta(cap)

    case meta[:mode] do
      :oauth -> assert_string_instructions!(meta)
      :enterprise -> assert_list_instructions!(meta)
      _ -> :ok
    end

    :telemetry.detach(handler_id)

    Mix.shell().info(
      "E2E OK: OpenAI — tools visible, function call observed, no-duplicates verified."
    )
  end

  defp ensure_session(session_name) do
    sa =
      TheMaestro.Auth.get_by_provider_and_name(:openai, :oauth, session_name) ||
        TheMaestro.Auth.get_by_provider_and_name(:openai, :api_key, session_name)

    unless sa, do: Mix.raise("No saved_authentication for openai name=#{session_name}")

    s = Conversations.latest_session_for_auth_id(sa.id)
    if is_nil(s), do: create_session_via_auth(session_name), else: {:ok, s.id}
  end

  defp create_session_via_auth(session_name) do
    # Fallback: create a session record tied to this saved auth
    # Default model to gpt-5 (ChatGPT OAuth); change to gpt-4o for API key sessions
    sa =
      TheMaestro.Auth.get_by_provider_and_name(:openai, :oauth, session_name) ||
        TheMaestro.Auth.get_by_provider_and_name(:openai, :api_key, session_name)

    unless sa, do: Mix.raise("No saved_authentication for openai name=#{session_name}")

    {:ok, s} =
      Conversations.create_session(%{
        auth_id: sa.id,
        model_id: "gpt-5",
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

  # ===== Instruction shape assertions =====
  defp attach_openai_shape_handler(agent) do
    id = "e2e-openai-shape-" <> Integer.to_string(System.unique_integer([:positive]))

    :telemetry.attach(
      id,
      [:providers, :openai, :request_built],
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

  defp assert_string_instructions!(%{instructions_shape: :string}), do: :ok
  defp assert_string_instructions!(_), do: Mix.raise("OpenAI OAuth instructions not string")
  defp assert_list_instructions!(%{instructions_shape: :list}), do: :ok
  defp assert_list_instructions!(_), do: Mix.raise("OpenAI API instructions not list/segments")

  # ===== Normalization assertions =====
  defp message_count(session_id) do
    case Conversations.latest_snapshot(session_id) do
      %{combined_chat: %{"messages" => msgs}} -> length(msgs)
      _ -> 0
    end
  end

  defp validate_normalization!(session_id, pre_count) do
    # Wait briefly for finalize
    after_count = wait_until(fn -> message_count(session_id) end, pre_count + 2)

    unless after_count == pre_count + 2,
      do: Mix.raise("Conversation not normalized (+2 messages expected)")
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
