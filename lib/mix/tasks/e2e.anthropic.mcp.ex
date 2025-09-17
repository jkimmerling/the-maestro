defmodule Mix.Tasks.E2e.Anthropic.Mcp do
  use Mix.Task
  @shortdoc "E2E: Anthropic + Context7 MCP tools exposure + function call"

  @moduledoc """
  Validates Anthropic integration with MCP tool exposure and function calling.

  Usage:
      mix e2e.anthropic.mcp --anthropic personal_oauth_anthropic
  """

  alias TheMaestro.{Auth, Chat, Conversations, MCP}

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

    session =
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

    session_id = session.id

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
end
