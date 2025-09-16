defmodule Mix.Tasks.E2e.Anthropic.Mcp do
  use Mix.Task
  @shortdoc "E2E: Anthropic + Context7 MCP tools exposure + function call"

  @moduledoc """
  Validates Anthropic integration with MCP tool exposure and function calling.

  Usage:
      mix e2e.anthropic.mcp --anthropic personal_oauth_anthropic
  """

  alias TheMaestro.{Auth, Chat, Conversations}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: [anthropic: :string])
    session_name = opts[:anthropic] || System.get_env("ANTHROPIC_SESSION_NAME")

    unless is_binary(session_name) and session_name != "" do
      Mix.raise("Provide --anthropic <saved_auth_name> or ANTHROPIC_SESSION_NAME env var")
    end

    # Ensure a session exists
    sa =
      Auth.get_by_provider_and_name(:anthropic, :oauth, session_name) ||
        Auth.get_by_provider_and_name(:anthropic, :api_key, session_name)

    unless sa, do: Mix.raise("No saved_authentication for anthropic name=#{session_name}")

    session_id =
      case Conversations.latest_session_for_auth_id(sa.id) do
        %Conversations.Session{id: id} ->
          id

        _ ->
          {:ok, s} =
            Conversations.create_session(%{
              auth_id: sa.id,
              model_id: "claude-3-5-sonnet-latest",
              working_dir: File.cwd!()
            })

          s.id
      end

    ensure_mcps!(session_id)

    System.put_env("HTTP_DEBUG", "1")
    Chat.subscribe(session_id)

    prompt =
      "please use the context7 mcp to resolve \"elixir ecto\" and then get docs for \"changesets\""

    {:ok, turn} = Chat.start_turn(session_id, nil, prompt)

    final = collect_turn_outcome(session_id, turn.stream_id)
    validate_outcome!(final)

    Mix.shell().info(
      "E2E OK: Anthropic + Context7 MCP: function call observed; stream finalized."
    )
  end

  defp ensure_mcps!(session_id) do
    base_url = System.get_env("CONTEXT7_BASE_URL") || "https://mcp.context7.com"
    endpoint = System.get_env("CONTEXT7_ENDPOINT") || "/mcp"

    headers =
      case System.get_env("CONTEXT7_HEADERS_JSON") do
        nil ->
          key = System.get_env("CONTEXT7_API_KEY")
          if is_binary(key) and key != "", do: %{"X-Api-Key" => key}, else: %{}

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
