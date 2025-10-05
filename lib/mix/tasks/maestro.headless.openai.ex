defmodule Mix.Tasks.Maestro.Headless.Openai do
  use Mix.Task
  @shortdoc "Run a single OpenAI turn headlessly with full payload tee logging"

  alias TheMaestro.{Auth, Chat, Conversations}

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          auth_name: :string,
          auth_id: :string,
          model: :string,
          cwd: :string,
          message: :string,
          runtime: :string
        ]
      )

    auth_id = find_auth!(opts)
    cwd = opts[:cwd] || File.cwd!()
    _model = opts[:model] || "gpt-5"
    msg = required!(opts[:message], "--message")
    runtime = (opts[:runtime] || "server") |> String.downcase()

    {:ok, session} =
      Conversations.create_session(%{
        name: "Headless OpenAI",
        auth_id: auth_id,
        working_dir: cwd,
        tool_runtime: runtime
      })

    {:ok, thread_id} = Chat.ensure_thread(session.id)

    IO.puts("\n[HEADLESS] Starting turn in #{cwd} (runtime=#{runtime})\n")

    {:ok, %{stream_id: stream_id}} =
      Chat.start_turn(session.id, thread_id, msg,
        streaming_adapter: TheMaestro.Providers.Http.TeeStreamingAdapter,
        sandbox_owner: self()
      )

    :ok = Chat.subscribe_turn(session.id, stream_id)
    frames = collect([])
    IO.puts("\n[HEADLESS] Frames: \n" <> inspect(frames, limit: :infinity))
  end

  defp collect(acc) do
    receive do
      {:turn_frame, frame} ->
        if frame["kind"] == "final" do
          Enum.reverse([frame | acc])
        else
          collect([frame | acc])
        end
    after
      15_000 -> Enum.reverse(acc)
    end
  end

  defp required!(val, flag) do
    if is_binary(val) and String.trim(val) != "", do: val, else: Mix.raise("missing #{flag}")
  end

  defp find_auth!(opts) do
    case {opts[:auth_id], opts[:auth_name]} do
      {id, _} when is_binary(id) ->
        id

      {_, name} when is_binary(name) ->
        case Auth.get_by_provider_and_name(:openai, :api_key, name) ||
               Auth.get_by_provider_and_name(:openai, :oauth, name) do
          %{id: id} -> id
          _ -> Mix.raise("auth not found: #{name}")
        end

      _ ->
        Mix.raise("provide --auth_id or --auth_name")
    end
  end
end
