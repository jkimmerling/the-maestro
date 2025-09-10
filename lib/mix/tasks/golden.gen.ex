defmodule Mix.Tasks.Golden.Gen do
  use Mix.Task
  @shortdoc "Generate golden HTTP fixtures by running real sessions"

  @moduledoc """
  Generates golden request fixtures by exercising real provider calls using existing saved authentications.

  This task will:
  - Create (or reuse) a session for each configured provider session name
  - Send two turns: "hello" and then "please list the files in your current directory"
  - Capture HTTP headers/body via TheMaestro.DebugLog into priv/golden/<provider>.log
  - Extract the first request payload+headers for each turn into JSON fixtures under priv/golden/<provider>/

  Usage:
      mix golden.gen --openai personal_oauth_openai --anthropic personal_oauth_claude --gemini personal_oauth_gemini

  Notes:
  - Requires valid saved_authentications already present (OAuth tokens/API keys).
  - This uses live network calls. Run intentionally.
  """

  alias TheMaestro.{Auth, Chat, Conversations}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args, switches: [openai: :string, anthropic: :string, gemini: :string])

    providers =
      Enum.filter(
        [{:openai, opts[:openai]}, {:anthropic, opts[:anthropic]}, {:gemini, opts[:gemini]}],
        fn {_p, v} -> is_binary(v) and v != "" end
      )

    if providers == [] do
      Mix.raise("Provide at least one provider session name via --openai/--anthropic/--gemini")
    end

    File.mkdir_p!(Path.join([File.cwd!(), "priv", "golden"]))

    Enum.each(providers, fn {provider, session_name} ->
      run_for_provider(provider, session_name)
    end)
  end

  defp run_for_provider(provider, session_name) do
    sa =
      Auth.get_by_provider_and_name(provider, :oauth, session_name) ||
        Auth.get_by_provider_and_name(provider, :api_key, session_name)

    unless sa, do: Mix.raise("No saved_authentication for #{provider}/#{session_name}")

    {:ok, session_id} = ensure_session(provider, sa)

    log_dir = Path.join([File.cwd!(), "priv", "golden", Atom.to_string(provider)])
    File.mkdir_p!(log_dir)
    log_path = Path.join(log_dir, "capture.log")
    File.rm_rf(log_path)

    System.put_env("HTTP_DEBUG", "1")
    System.put_env("HTTP_DEBUG_LEVEL", "high")
    System.put_env("HTTP_DEBUG_FILE", log_path)

    TheMaestro.Chat.subscribe(session_id)

    {:ok, t1} = Chat.start_turn(session_id, nil, "hello")
    ensure_turn_passes!(session_id, t1.stream_id, require_tools?: false)

    {:ok, t2} =
      Chat.start_turn(session_id, nil, "please list the files in your current directory")

    ensure_turn_passes!(session_id, t2.stream_id, require_tools?: true)

    fixtures = extract_fixtures(log_path)
    out_file = Path.join(log_dir, "request_fixtures.json")
    File.write!(out_file, Jason.encode!(fixtures, pretty: true))

    Mix.shell().info("Wrote #{out_file}")
  end

  defp ensure_session(provider, sa) do
    s = Conversations.latest_session_for_auth_id(sa.id)
    if s, do: {:ok, s.id}, else: create_session(provider, sa)
  end

  defp create_session(provider, sa) do
    {:ok, s} =
      Conversations.create_session(%{
        auth_id: sa.id,
        model_id: default_model(provider),
        working_dir: File.cwd!()
      })

    {:ok, s.id}
  end

  defp default_model(:openai), do: "gpt-4o"
  defp default_model(:anthropic), do: "claude-3-5-sonnet-20240620"
  defp default_model(:gemini), do: "gemini-1.5-pro-latest"

  defp extract_fixtures(log_path) do
    {:ok, bin} = File.read(log_path)
    lines = String.split(bin, "\n")

    # Simple heuristic: grab last seen Headers JSON and the Body JSON following it for each request
    do_extract(lines, [], %{})
  end

  defp do_extract([], acc, _current), do: Enum.reverse(acc)

  defp do_extract([line | rest], acc, current) do
    cond do
      String.starts_with?(line, "[HTTP] ") ->
        do_extract(rest, acc, %{headers: nil, body: nil})

      String.starts_with?(line, "RespHeaders:") ->
        do_extract(rest, acc, current)

      String.starts_with?(line, "Headers:") ->
        json = String.replace_prefix(line, "Headers: ", "")

        case Jason.decode(json) do
          {:ok, map} -> do_extract(rest, acc, Map.put(current, :headers, map))
          _ -> do_extract(rest, acc, current)
        end

      String.starts_with?(line, "Body:") ->
        body = String.replace_prefix(line, "Body: ", "")
        item = %{headers: current[:headers], body: safe_decode(body)}
        do_extract(rest, [item | acc], %{})

      true ->
        do_extract(rest, acc, current)
    end
  end

  defp safe_decode(str) do
    case Jason.decode(str) do
      {:ok, m} -> m
      _ -> str
    end
  end

  defp ensure_turn_passes!(session_id, stream_id, opts) do
    require_tools? = Keyword.get(opts, :require_tools?, false)
    final = collect_turn_outcome(session_id, stream_id)
    validate_outcome!(final, require_tools?)
  end

  defp collect_turn_outcome(session_id, stream_id) do
    deadline = System.monotonic_time(:millisecond) + 30_000
    state = %{content: "", saw_error?: false, saw_finalized?: false, saw_tool?: false}
    wait_events(session_id, stream_id, state, deadline, &reduce_event/2)
  end

  defp reduce_event(%{type: :error}, acc), do: %{acc | saw_error?: true}
  defp reduce_event(%{type: :finalized}, acc), do: %{acc | saw_finalized?: true}

  defp reduce_event(%{type: :content, content: chunk}, acc) when is_binary(chunk),
    do: %{acc | content: acc.content <> chunk}

  defp reduce_event(%{type: :function_call, tool_calls: calls}, acc) when is_list(calls) do
    any_tool = Enum.any?(calls, &tool_name_matches?/1)
    %{acc | saw_tool?: acc.saw_tool? or any_tool}
  end

  defp reduce_event(_other, acc), do: acc

  defp tool_name_matches?(c) do
    n = (is_map(c) && (c["name"] || c[:name])) || nil
    n in ["shell", "Bash", "run_shell_command", "list_directory"]
  end

  defp validate_outcome!(final, require_tools?) do
    cond do
      final.saw_error? ->
        Mix.raise("Turn failed: provider returned error events")

      not final.saw_finalized? ->
        Mix.raise("Turn did not finalize in time")

      String.trim(final.content) == "" ->
        Mix.raise("Turn produced empty content")

      require_tools? and not final.saw_tool? ->
        Mix.raise("Second turn did not use tools as required")

      require_tools? and not looks_like_listing?(final.content) ->
        Mix.raise("Second turn did not appear to list files")

      true ->
        :ok
    end
  end

  defp wait_events(session_id, stream_id, acc, deadline_ms, reducer) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline_ms do
      acc
    else
      receive do
        {:session_stream,
         %TheMaestro.Domain.StreamEnvelope{
           session_id: ^session_id,
           stream_id: ^stream_id,
           event: ev
         }} ->
          acc2 = reducer.(ev, acc)

          if acc2.saw_finalized?,
            do: acc2,
            else: wait_events(session_id, stream_id, acc2, deadline_ms, reducer)

        _other ->
          wait_events(session_id, stream_id, acc, deadline_ms, reducer)
      after
        1000 ->
          wait_events(session_id, stream_id, acc, deadline_ms, reducer)
      end
    end
  end

  defp looks_like_listing?(text) when is_binary(text) do
    sample = String.downcase(text)

    Enum.any?(
      [
        "mix.exs",
        "lib/",
        "deps/",
        "assets/",
        ".gitignore",
        "README.md",
        "total ",
        "drwx"
      ],
      fn needle -> String.contains?(sample, String.downcase(needle)) end
    )
  end
end
