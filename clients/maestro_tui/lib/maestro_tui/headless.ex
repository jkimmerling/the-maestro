defmodule MaestroTui.Headless do
  @moduledoc false
  alias MaestroTui.API

  @io_tools ~w(apply_patch write_file write create_file edit multi_edit list_directory glob grep shell run_shell_command notebook_edit)a

  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts) do
    provider = Keyword.get(opts, :provider)
    auth_id = Keyword.get(opts, :auth_id)
    model = Keyword.get(opts, :model)
    working_dir = Keyword.get(opts, :working_dir) || File.cwd!()
    prompt = Keyword.get(opts, :message) || read_stdin()

    with {:ok, prov} <- pick_provider(provider),
         {:ok, auth} <- pick_auth(prov, auth_id),
         {:ok, mdl} <- pick_model(prov, auth, model),
         {:ok, session_id} <- create_session(auth, mdl, working_dir),
         {:ok, turn} <- start_turn(session_id, prompt) do
      consume_sse(session_id, turn["stream_id"], working_dir)
      :ok
    else
      {:error, r} -> {:error, r}
    end
  end

  defp pick_provider(nil) do
    case API.providers() do
      {:ok, [p | _]} -> {:ok, p}
      {:ok, []} -> {:error, :no_providers}
      other -> other
    end
  end
  defp pick_provider(p) when is_binary(p), do: {:ok, p}

  defp pick_auth(provider, nil) do
    url = API.base_url() <> "/api/providers/" <> provider <> "/saved_auths"
    case Req.get(url: url, headers: [API.auth_header()], finch: MaestroTui.Finch) do
      {:ok, %Req.Response{status: 200, body: %{"auths" => [first | _]}}} -> {:ok, first["id"]}
      {:ok, %Req.Response{status: 200, body: %{"auths" => []}}} -> {:error, :no_auths}
      other -> {:error, other}
    end
  end
  defp pick_auth(_provider, id) when is_binary(id), do: {:ok, id}

  defp pick_model(provider, auth_id, nil) do
    url = API.base_url() <> "/api/providers/" <> provider <> "/saved_auths/" <> auth_id <> "/models"
    case Req.get(url: url, headers: [API.auth_header()], finch: MaestroTui.Finch) do
      {:ok, %Req.Response{status: 200, body: %{"models" => [m | _]}}} -> {:ok, m}
      other -> {:error, other}
    end
  end
  defp pick_model(_provider, _auth, m) when is_binary(m), do: {:ok, m}

  defp create_session(auth_id, model, working_dir) do
    url = API.base_url() <> "/api/sessions"
    body = %{"auth_id" => auth_id, "model" => model, "working_dir" => working_dir, "tool_runtime" => "remote"}
    case Req.post(url: url, headers: [API.auth_header()], json: body, finch: MaestroTui.Finch) do
      {:ok, %Req.Response{status: s, body: %{"session_id" => id}}} when s in 200..299 -> {:ok, id}
      other -> {:error, other}
    end
  end

  defp start_turn(session_id, message) do
    url = API.base_url() <> "/api/sessions/" <> session_id <> "/turns"
    case Req.post(url: url, headers: [API.auth_header()], json: %{"message" => message}, finch: MaestroTui.Finch) do
      {:ok, %Req.Response{status: 202, body: body}} -> {:ok, body}
      other -> {:error, other}
    end
  end

  defp consume_sse(session_id, stream_id, workdir) do
    url = API.base_url() <> "/api/sessions/" <> session_id <> "/turns/" <> stream_id <> "/frames"
    req = Req.new(headers: [API.auth_header()], finch: MaestroTui.Finch)
    case Req.request(req, method: :get, url: url, into: :self, receive_timeout: :infinity) do
      {:ok, %Req.Response{status: 200, body: stream}} ->
        _rest =
          Enum.reduce(stream, "", fn chunk, acc ->
            {events, rest} = parse_sse_chunk(acc, chunk)
            Enum.each(events, fn ev -> handle_event(session_id, stream_id, ev, workdir) end)
            rest
          end)
        :ok
      _ -> :ok
    end
  end

  defp parse_sse_chunk(acc, chunk) do
    data = acc <> IO.iodata_to_binary(chunk)
    segs = String.split(data, "\n\n", trim: false)
    {complete, rest} =
      if String.ends_with?(data, "\n\n") do
        {segs, ""}
      else
        {Enum.drop(segs, -1), List.last(segs) || ""}
      end

    events =
      complete
      |> Enum.flat_map(fn block ->
        case Regex.run(~r/data:\s*(.*)/s, block, capture: :all_but_first) do
          [json] ->
            case Jason.decode(json) do
              {:ok, %{"data" => frame}} -> [%{data: frame}]
              _ -> []
            end
          _ -> []
        end
      end)

    {events, rest}
  end

  defp handle_event(session_id, stream_id, %{data: %{"kind" => "function_call", "payload" => %{"calls" => calls}}}, workdir) do
    Enum.each(calls, fn %{"id" => id, "name" => name, "arguments" => args_json} ->
      if io_tool?(name) do
        result = exec_local(name, args_json, workdir)
        post_tool_result(session_id, stream_id, id, name, result)
      end
    end)
  end
  defp handle_event(_sid, _stream, %{data: %{"kind" => "assistant_text", "payload" => %{"delta" => d}}}, _wd) when is_binary(d) do
    IO.write(d)
  end
  defp handle_event(_sid, _stream, _ev, _wd), do: :ok

  defp exec_local(name, args_json, base) do
    case dispatch(String.downcase(to_string(name)), args_json || "{}", base) do
      {:ok, payload} -> {:ok, payload}
      {:error, r} -> {:error, to_string(r)}
    end
  end

  defp dispatch("write_file" = _n, json, base) do
    with {:ok, args} <- Jason.decode(json), do: TheMaestro.Tools.WriteFile.run(args, base_cwd: base)
  end
  defp dispatch("write", json, base), do: dispatch("write_file", json, base)
  defp dispatch("create_file", json, base), do: dispatch("write_file", json, base)
  defp dispatch("shell", json, base) do
    with {:ok, args} <- Jason.decode(json), do: TheMaestro.Tools.Shell.run(args, base_cwd: base)
  end
  defp dispatch("run_shell_command", json, base), do: dispatch("shell", json, base)
  defp dispatch("list_directory", json, base) do
    with {:ok, args} <- Jason.decode(json), do: TheMaestro.Tools.ListDirectory.run(args, base_cwd: base)
  end
  defp dispatch("glob", json, base) do
    with {:ok, args} <- Jason.decode(json), do: TheMaestro.Tools.Glob.run(args, base_cwd: base)
  end
  defp dispatch("grep", json, base) do
    with {:ok, args} <- Jason.decode(json), do: TheMaestro.Tools.Grep.run(args, base_cwd: base)
  end
  defp dispatch("edit", json, base) do
    with {:ok, args} <- Jason.decode(json),
         {:ok, payload, _} <- TheMaestro.Tools.Edit.run(args, base_cwd: base) do
      {:ok, payload}
    end
  end
  defp dispatch("multi_edit", json, base) do
    with {:ok, args} <- Jason.decode(json),
         {:ok, payload, _} <- TheMaestro.Tools.MultiEdit.run(args, base_cwd: base) do
      {:ok, payload}
    end
  end
  defp dispatch("apply_patch", json, base) do
    with {:ok, %{"input" => input}} <- Jason.decode(json), do: TheMaestro.Tools.ApplyPatch.run(input, base_cwd: base)
  end
  defp dispatch("notebook_edit", json, base) do
    with {:ok, args} <- Jason.decode(json), do: TheMaestro.Tools.NotebookEdit.run(args, base_cwd: base)
  end
  defp dispatch(other, _json, _base), do: {:error, "unsupported tool: #{other}"}

  defp post_tool_result(session_id, stream_id, call_id, name, {:ok, payload}) do
    url = API.base_url() <> "/api/sessions/" <> session_id <> "/turns/" <> stream_id <> "/tools/results"
    body = %{"call_id" => call_id, "name" => name, "output" => payload}
    _ = Req.post(url: url, headers: [API.auth_header()], json: body, finch: MaestroTui.Finch)
    :ok
  end
  defp post_tool_result(_sid, _stream, _id, _name, {:error, _} = _err), do: :ok

  defp io_tool?(name) when is_binary(name), do: String.downcase(name) in Enum.map(@io_tools, &to_string/1)
  defp io_tool?(_), do: false

  defp read_stdin do
    IO.read(:stdio, :all) |> to_string() |> String.trim()
  end
end
