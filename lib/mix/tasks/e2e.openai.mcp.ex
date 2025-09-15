defmodule Mix.Tasks.E2e.Openai.Mcp do
  use Mix.Task
  @shortdoc "E2E: OpenAI (OAuth/API) + Context7 MCP tools exposure + function call"

  @moduledoc """
  Validates OpenAI integration with MCP tool exposure and function calling.

  - Ensures session has MCP server configured (from ENV or defaults)
  - Starts a turn asking to use the context7 MCP
  - Confirms the model sees tools and emits a function call

  Usage:
      mix e2e.openai.mcp --openai personal_oauth_openai
  """

  alias TheMaestro.{Chat, Conversations}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: [openai: :string])
    session_name = opts[:openai] || System.get_env("OPENAI_SESSION_NAME")

    unless is_binary(session_name) and session_name != "" do
      Mix.raise("Provide --openai <saved_auth_name> or OPENAI_SESSION_NAME env var")
    end

    # Ensure a session exists for this saved auth
    {:ok, session_id} = ensure_session(session_name)
    ensure_mcps!(session_id)

    # Extra debug reveals tools list in payload
    System.put_env("DEBUG_STREAM_EVENTS", "1")

    Chat.subscribe(session_id)

    prompt = "please use the context7 mcp to look up elixir ecto and tell me about Multi"
    {:ok, turn} = Chat.start_turn(session_id, nil, prompt)

    final = collect_turn_outcome(session_id, turn.stream_id)
    validate_outcome!(final)

    Mix.shell().info("E2E OK: OpenAI saw MCP tools and issued a function call.")
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
    base_url = System.get_env("CONTEXT7_BASE_URL") || "https://mcp.context7.com"
    endpoint = System.get_env("CONTEXT7_ENDPOINT") || "/mcp"

    headers =
      case System.get_env("CONTEXT7_HEADERS_JSON") do
        nil ->
          key = System.get_env("CONTEXT7_API_KEY")

          if is_binary(key) and key != "" do
            %{"X-Api-Key" => key}
          else
            %{}
          end

        json ->
          Jason.decode!(json)
      end

    s = Conversations.get_session!(session_id)

    mcps =
      Map.put(s.mcps || %{}, "context7", %{
        "transport" => "stream",
        "base_url" => base_url,
        "endpoint" => endpoint,
        "headers" => headers
      })

    {:ok, _} = Conversations.update_session(s, %{mcps: mcps})
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
end
