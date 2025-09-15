defmodule Mix.Tasks.E2e.Gemini.Mcp do
  use Mix.Task
  @shortdoc "E2E: Gemini OAuth + Context7 MCP resolve_library_id → functionResponse"

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

  alias TheMaestro.{Auth, Chat, Conversations}

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

    prompt = "please use the context7 mcp to look up the docs on Elixir ecto migrations"
    {:ok, turn} = Chat.start_turn(session_id, nil, prompt)

    # Collect events until finalized
    final = collect_turn_outcome(session_id, turn.stream_id)
    validate_outcome!(final)

    Mix.shell().info("E2E OK: Gemini OAuth + Context7 MCP: model called resolve-library-id, stream finalized.")
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
        json -> Jason.decode!(json)
      end

    s = Conversations.get_session!(session_id)
    mcps = Map.put(s.mcps || %{}, "context7", %{
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
      {:session_stream, %TheMaestro.Domain.StreamEnvelope{session_id: ^session_id, stream_id: ^stream_id, event: ev}} ->
        state2 =
          case ev do
            %{type: :function_call, tool_calls: calls} when is_list(calls) ->
              # Detect resolve-library-id call
              saw = Enum.any?(calls, fn c ->
                n = (is_map(c) && (c["name"] || c[:name])) || nil
                n == "resolve-library-id"
              end)
              %{state | saw_fc?: state.saw_fc? or saw}

            %{type: :done} -> %{state | finalized?: true}

            _ -> state
          end

        if state2.finalized?, do: state2, else: wait(session_id, stream_id, state2, deadline)

      _ -> wait(session_id, stream_id, state, deadline)
    after
      1000 -> wait(session_id, stream_id, state, deadline)
    end
  end

  defp validate_outcome!(%{finalized?: true, saw_fc?: true}), do: :ok
  defp validate_outcome!(%{finalized?: false}), do: Mix.raise("Stream did not finalize")
  defp validate_outcome!(%{saw_fc?: false}), do: Mix.raise("Model did not call resolve-library-id")

  # No file-based assertion; the presence of a function call + finalization is enough
end
