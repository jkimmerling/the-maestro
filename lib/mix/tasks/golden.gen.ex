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

    {:ok, _} = Chat.start_turn(session_id, nil, "hello")
    Process.sleep(1500)
    {:ok, _} = Chat.start_turn(session_id, nil, "please list the files in your current directory")
    Process.sleep(3000)

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
end
