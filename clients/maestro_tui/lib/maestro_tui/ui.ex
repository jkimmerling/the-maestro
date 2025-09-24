defmodule MaestroTui.UI do
    @moduledoc false
    @behaviour Ratatouille.App
    alias MaestroTui.API
    import Ratatouille.View

    def run do
      Ratatouille.run(__MODULE__)
    end

    defmodule State do
      defstruct screen: :wizard,
                providers: [], provider: nil,
                auths: [], auth_id: nil,
                models: [], model: nil,
                prov_idx: 0, auth_idx: 0, model_idx: 0,
                wizard_focus: :provider,
                modal: nil,
                last_usage: %{},
                sessions: %{}, order: [], active: nil,
                log_visible: false, log: [],
                transcript: [],
                input: "",
                session_id: nil, current_thread_id: nil, stream_task: nil,
                stream_id: nil, stream_consumed: 0,
                working_dir: File.cwd!(),
                thinking_visibility: :collapsed,
                streams: %{}
    end

    @impl true
    def init(_context) do
      case API.providers() do
        {:ok, providers} -> %State{providers: providers}
        {:error, _} -> %State{providers: [], log: ["API unavailable — set TUI_API_BASE_URL and TUI_API_TOKEN"]}
      end
    end

    @impl true
    def subscribe(_model), do: Ratatouille.Runtime.Subscription.interval(1000, :noop)

    # No explicit subscriptions; spawned tasks send messages to self

    def update(%State{screen: :wizard} = s, {:event, %{ch: 10}}) do
      prov = s.provider || List.first(s.providers)
      with {:ok, {auth, auths}} <- pick_auths(prov), {:ok, {model, models}} <- pick_models(prov, auth) do
        sid = nil
        s1 = %State{
          s
          | screen: :chat,
            provider: prov,
            auth_id: auth,
            auths: auths,
            model: model,
            models: models,
            session_id: sid
        }
        put_new_session(s1)
      else
        _ -> s
      end
    end
    def update(%State{screen: :wizard} = s, {:event, ev}) do
      cond do
        event_key?(ev, :arrow_up) -> move_index(s, -1)
        event_key?(ev, :arrow_down) -> move_index(s, 1)
        event_key?(ev, :arrow_left) -> move_focus(s, -1)
        event_key?(ev, :arrow_right) -> move_focus(s, 1)
        event_key?(ev, :tab) -> move_focus(s, 1)
        event_enter?(ev) ->
          # Fall back to enter starting the chat
          update(s, {:event, %{ch: 10}})
        true -> s
      end
    end

    defp move_focus(%State{wizard_focus: :provider} = s, 1) do
      pv = s.provider || Enum.at(s.providers, s.prov_idx)
      {auths, aid} =
        case pv do
          nil -> {s.auths, s.auth_id}
          _ ->
            case pick_auths(pv) do
              {:ok, {first, list}} -> {list, first}
              _ -> {[], nil}
            end
        end
      %State{s | wizard_focus: :auth, provider: pv, auths: auths, auth_id: aid, auth_idx: 0}
    end
    defp move_focus(%State{wizard_focus: :auth} = s, 1) do
      pv = s.provider || Enum.at(s.providers, s.prov_idx)
      {models, mdl} =
        case {pv, s.auth_id} do
          {p, a} when is_binary(p) and is_binary(a) ->
            case pick_models(p, a) do
              {:ok, {m0, list}} -> {list, m0}
              _ -> {s.models, s.model}
            end
          _ -> {s.models, s.model}
        end
      %State{s | wizard_focus: :model, models: models, model: mdl, model_idx: 0}
    end
    defp move_focus(%State{wizard_focus: :model} = s, 1), do: s
    defp move_focus(%State{wizard_focus: :model} = s, -1), do: %State{s | wizard_focus: :auth}
    defp move_focus(%State{wizard_focus: :auth} = s, -1), do: %State{s | wizard_focus: :provider}
    defp move_focus(%State{wizard_focus: :provider} = s, -1), do: s

    defp move_index(%State{wizard_focus: :provider} = s, delta) do
      maxi = max(length(s.providers) - 1, 0)
      i = clamp(s.prov_idx + delta, 0, maxi)
      pv = Enum.at(s.providers, i)
      {auths, aid} =
        case pick_auths(pv) do
          {:ok, {first, list}} -> {list, first}
          _ -> {[], nil}
        end
      {models, mdl} =
        case aid do
          a when is_binary(a) ->
            case pick_models(pv, a) do
              {:ok, {m0, list}} -> {list, m0}
              _ -> {[], nil}
            end
          _ -> {[], nil}
        end
      %State{s | prov_idx: i, provider: pv, auths: auths, auth_idx: 0, auth_id: aid, models: models, model_idx: 0, model: mdl}
    end

    defp move_index(%State{wizard_focus: :auth} = s, delta) do
      pv = s.provider || Enum.at(s.providers, s.prov_idx)
      auths = if s.auths == [], do: (case pv do nil -> []; _ -> (case pick_auths(pv) do {:ok, {_, list}} -> list; _ -> [] end) end), else: s.auths
      maxi = max(length(auths) - 1, 0)
      i = clamp(s.auth_idx + delta, 0, maxi)
      aid = Enum.at(auths, i)
      {models, mdl} =
        case aid do
          a when is_binary(a) ->
            case pick_models(s.provider, a) do
              {:ok, {m0, list}} -> {list, m0}
              _ -> {[], nil}
            end
          _ -> {[], nil}
        end
      %State{s | auths: auths, auth_idx: i, auth_id: aid, models: models, model_idx: 0, model: mdl}
    end

    defp move_index(%State{wizard_focus: :model} = s, delta) do
      models =
        if s.models == [] and is_binary(s.auth_id) do
          case pick_models(s.provider, s.auth_id) do
            {:ok, {_, list}} -> list
            _ -> []
          end
        else
          s.models
        end

      maxi = max(length(models) - 1, 0)
      i = clamp(s.model_idx + delta, 0, maxi)
      mdl = Enum.at(models, i)
      %State{s | models: models, model_idx: i, model: mdl}
    end

    defp clamp(i, lo, _hi) when i < lo, do: lo
    defp clamp(i, _lo, hi) when i > hi, do: hi
    defp clamp(i, _lo, _hi), do: i

    # Chat: printable characters first to ensure typing works
    def update(%State{screen: :chat} = s, {:event, %{ch: ch}}) when is_integer(ch) and ch >= 32 do
      %State{s | input: s.input <> <<ch::utf8>>}
    end
    def update(%State{screen: :chat} = s, {:event, %{key: 32}}) do
      %State{s | input: s.input <> " "}
    end

    # Chat: SSE turn frames (must match before generic {:event, ev})
    def update(%State{screen: :chat} = s, {:event, %{tui: :turn_frame, stream_id: sid, frame: frame}}) do
      handle_turn_frame(s, sid, frame)
    end

    # Chat: key events (enter, backspace, modal nav)
    def update(%State{screen: :chat} = s, {:event, ev}) when is_map(ev) do
      cond do
        (not is_nil(s.modal)) and event_key?(ev, :arrow_up) -> modal_move(s, -1)
        (not is_nil(s.modal)) and event_key?(ev, :arrow_down) -> modal_move(s, 1)
        (not is_nil(s.modal)) and event_key?(ev, :esc) -> close_modal(s)
        (not is_nil(s.modal)) and event_enter?(ev) -> handle_modal_enter(s)
        event_enter?(ev) and shift?(ev) -> %State{s | input: s.input <> "\n"}
        event_enter?(ev) -> run_submit(s)
        ctrl_shift?(ev, ?L) -> %State{s | log_visible: !s.log_visible}
        ctrl_shift?(ev, ?P) -> cycle_provider(s)
        ctrl_shift?(ev, ?A) -> cycle_auth(s)
        ctrl_shift?(ev, ?M) -> cycle_model(s)
        ctrl_shift?(ev, ?N) -> new_session(s)
        ctrl_shift?(ev, ?T) -> toggle_thinking(s)
        ctrl_shift?(ev, ?]) -> next_session(s)
        ctrl_shift?(ev, ?[) -> prev_session(s)
        backspace?(ev) -> %State{s | input: String.slice(s.input, 0, max(byte_size(s.input) - 1, 0))}
        true -> s
      end
    end

    

    defp ensure_session(%State{session_id: sid} = _s) when is_binary(sid), do: {:ok, sid}
    defp ensure_session(%State{} = s) do
      url = API.base_url() <> "/api/sessions"
      body = %{"auth_id" => s.auth_id, "model" => s.model, "working_dir" => s.working_dir, "tool_runtime" => "remote"}
      case Req.post(url: url, headers: [API.auth_header()], json: body, finch: MaestroTui.Finch) do
        {:ok, %Req.Response{status: 200, body: %{"session_id" => sid}}} -> {:ok, sid}
        _ -> {:error, :session}
      end
    end

    def pick_auths(nil), do: {:error, :provider_missing}
    def pick_auths(provider) do
      url = API.base_url() <> "/api/providers/" <> provider <> "/saved_auths"
      case Req.get(url: url, headers: [API.auth_header()], finch: MaestroTui.Finch) do
        {:ok, %Req.Response{status: 200, body: %{"auths" => list}}} when is_list(list) and list != [] ->
          ids = Enum.map(list, & &1["id"]) |> Enum.filter(&is_binary/1)
          {:ok, {hd(ids), ids}}
        _ -> {:error, :auth}
      end
    end

    def pick_models(_provider, nil), do: {:error, :auth_missing}
    def pick_models(provider, auth_id) do
      url = API.base_url() <> "/api/providers/" <> provider <> "/saved_auths/" <> auth_id <> "/models"
      case Req.get(url: url, headers: [API.auth_header()], finch: MaestroTui.Finch) do
        {:ok, %Req.Response{status: 200, body: %{"models" => list}}} when is_list(list) and list != [] ->
          {:ok, {hd(list), list}}
        _ -> {:error, :model}
      end
    end

    defp put_new_session(%State{session_id: sid} = s) do
      id = sid || (length(s.order) + 1) |> to_string()
      sessions = Map.put_new(s.sessions, id, %{log: [], input: ""})
      %State{s | sessions: sessions, order: s.order ++ [id], active: id}
    end

    # Old headless send removed; UI performs turn start + SSE (implemented below)

    defp new_session(%State{} = s) do
      s1 = %State{s | session_id: nil, input: "", log: s.log}
      put_new_session(s1)
    end

    defp next_session(%State{order: []} = s), do: s
    defp next_session(%State{order: ord, active: act} = s) do
      idx = Enum.find_index(ord, & &1 == act) || 0
      nidx = rem(idx + 1, length(ord))
      %State{s | active: Enum.at(ord, nidx)}
    end

    defp prev_session(%State{order: []} = s), do: s
    defp prev_session(%State{order: ord, active: act} = s) do
      idx = Enum.find_index(ord, & &1 == act) || 0
      nidx = rem(idx - 1 + length(ord), length(ord))
      %State{s | active: Enum.at(ord, nidx)}
    end

    defp ctrl_shift?(ev, code) do
      mod = Map.get(ev, :mod)
      key = Map.get(ev, :key)
      ch = Map.get(ev, :ch)
      cond do
        mod in [:ctrl, :ctrl_shift] and is_integer(code) and (key == to_ctrl_key(code) or ch == code) -> true
        true -> false
      end
    end

    defp to_ctrl_key(?L), do: :ctrl_l
    defp to_ctrl_key(?N), do: :ctrl_n
    defp to_ctrl_key(?T), do: :ctrl_t
    defp to_ctrl_key(_), do: nil

    defp shift?(ev) do
      Map.get(ev, :mod) in [:shift, :ctrl_shift] or Map.get(ev, :shift) == true
    end

    import Ratatouille.Constants, only: [key: 1]
    defp backspace?(%{key: k}) when is_integer(k), do: k in [key(:backspace), key(:backspace2)]
    defp backspace?(_), do: false

    @transcript_limit 500
    defp add_transcript(%State{} = s, line) when is_binary(line) do
      tr = Enum.take((s.transcript || []) ++ [line], -@transcript_limit)
      %State{s | transcript: tr}
    end

    defp replace_last([], v), do: [v]
    defp replace_last(list, v) when is_list(list) do
      case Enum.split(list, length(list) - 1) do
        {[], _} -> [v]
        {init, [_last]} -> init ++ [v]
      end
    end
    defp replace_at(list, idx, v) when is_list(list) and is_integer(idx) and idx >= 1 do
      {left, right} = Enum.split(list, idx - 1)
      case right do
        [] -> left ++ [v]
        [_old | tail] -> left ++ [v | tail]
      end
    end
    
    defp now_ms, do: :erlang.monotonic_time(:millisecond)
    defp stamp_line(role, text) do
      {_, {h, m, s}} = :calendar.local_time()
      ts = :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> IO.iodata_to_binary()
      "[" <> ts <> "] " <> role <> ": " <> to_string(text || "")
    end
    defp format_usage(u) do
      input = Map.get(u, "input_tokens") || Map.get(u, :input_tokens)
      output = Map.get(u, "output_tokens") || Map.get(u, :output_tokens)
      total = Map.get(u, "total_tokens") || Map.get(u, :total_tokens)
      Enum.join(Enum.filter([
        (is_integer(input) && ("input=" <> Integer.to_string(input))) || nil,
        (is_integer(output) && ("output=" <> Integer.to_string(output))) || nil,
        (is_integer(total) && ("total=" <> Integer.to_string(total))) || nil
      ], & &1), " ")
    end

    # tracing removed for parity-focused implementation

    defp append_line(%State{} = s, add_line), do: add_transcript(s, add_line)

    defp tlog(msg) when is_binary(msg) do
      case System.get_env("TUI_DEBUG") do
        s when s in ["1", "true", "TRUE"] -> IO.puts(:stderr, "[tui] " <> msg)
        _ -> :ok
      end
    end

    def render(%State{screen: :wizard, providers: providers, prov_idx: pidx, auths: auths, auth_idx: aidx, models: models, model_idx: midx, wizard_focus: focus} = s) do
      import Ratatouille.View
      view do
        panel title: "Provider / Auth / Model" do
          label(content: "Arrows=move  Tab/Shift+Tab=switch  Enter=start")
          row do
            column size: 4 do
              panel title: focus_title(:provider, focus) do
                for {p, i} <- Enum.with_index(providers) do
                  label(content: list_item(p, i == pidx))
                end
              end
            end
            column size: 4 do
              panel title: focus_title(:auth, focus) do
                cond do
                  (auths == [] and is_binary(s.provider || Enum.at(providers, pidx))) ->
                    label(content: "loading…")
                  true ->
                    for {a, i} <- Enum.with_index(auths) do
                      label(content: list_item(a || "", i == aidx))
                    end
                end
              end
            end
            column size: 4 do
              panel title: focus_title(:model, focus) do
                cond do
                  (models == [] and is_binary(s.auth_id || Enum.at(auths, aidx))) ->
                    label(content: "loading…")
                  true ->
                    for {m, i} <- Enum.with_index(models) do
                      label(content: list_item(m || "", i == midx))
                    end
                end
              end
            end
          end
        end
      end
    end

    defp focus_title(which, focus) do
      if which == focus, do: "→ #{which}", else: to_string(which)
    end
    defp list_item(text, true), do: "> " <> to_string(text)
    defp list_item(text, false), do: "  " <> to_string(text)

    def render(%State{screen: :chat, input: input, log: log, log_visible: lv, provider: pv, auth_id: aid, model: mdl} = s) do
      import Ratatouille.View
      view do
        panel title: "Chat" do
          label(content: "Provider: #{pv || "?"}  Auth: #{aid || "?"}  Model: #{mdl || "?"}")
          for line <- Enum.take(s.transcript || [], -200) do
            label(content: line)
          end
          if lv do
            for line <- Enum.take(log, -200) do
              label(content: line)
            end
          else
            label(content: "(log hidden) Press Ctrl+Shift+L to toggle")
          end
          label(content: "> " <> input)
          if String.starts_with?(input, "/") do
            show_slash_suggestions(s)
          end
          # Snapshot keybinding hint intentionally omitted in UI to keep noise low
          if s.modal do
            render_modal(s)
          end
        end
      end
    end
    
    # ----- SSE integration -----
    @io_tools ~w(apply_patch write_file write create_file edit multi_edit list_directory glob grep shell run_shell_command notebook_edit bash)a

    defp send_message(%State{} = s) do
      text = String.trim(s.input)
      case ensure_session(s) do
        {:ok, sid} ->
          case start_turn(sid, text) do
            {:ok, %{"stream_id" => stream_id, "thread_id" => tid}} ->
              ui_pid = self()
              spawn(fn -> consume_sse(sid, stream_id, s.working_dir, ui_pid) end)
              s
              |> add_transcript(stamp_line("you", text))
              |> Map.put(:input, "")
              |> Map.put(:log, s.log ++ ["> " <> text])
              
              |> Map.put(:stream_id, stream_id)
              |> Map.put(:stream_consumed, 0)
              |> Map.put(:session_id, sid)
              |> Map.put(:current_thread_id, tid)
              |> put_new_stream(stream_id, tid)
            _ -> s
          end
        _ -> s
      end
    end

    defp start_turn(session_id, message) do
      url = API.base_url() <> "/api/sessions/" <> session_id <> "/turns"
      case Req.post(url: url, headers: [API.auth_header()], json: %{"message" => message}, finch: MaestroTui.Finch) do
        {:ok, %Req.Response{status: 202, body: body}} -> {:ok, body}
        other -> {:error, other}
      end
    end

    defp consume_sse(session_id, stream_id, workdir, ui) do
      url = API.base_url() <> "/api/sessions/" <> session_id <> "/turns/" <> stream_id <> "/frames"
      req = Req.new(headers: [API.auth_header()], finch: MaestroTui.Finch)
      case Req.request(req, method: :get, url: url, into: :self, receive_timeout: :infinity) do
        {:ok, %Req.Response{status: 200, body: stream}} ->
          _rest =
            Enum.reduce(stream, "", fn chunk, acc ->
              {events, rest} = parse_sse_chunk(acc, chunk)
              if events != [] do
                tlog("sse events: " <> Integer.to_string(length(events)))
              end
              Enum.each(events, fn %{data: frame} ->
                send(ui, {:event, %{tui: :turn_frame, stream_id: stream_id, frame: frame, session_id: session_id, workdir: workdir}})
              end)
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

    # remove ETS event handlers — use event-driven updates below

    defp exec_local(name, args_json, base) do
      case dispatch(String.downcase(to_string(name)), args_json || "{}", base) do
        {:ok, payload} -> {:ok, payload}
        {:error, r} -> {:error, to_string(r)}
      end
    end

    defp io_tool?(name) when is_binary(name), do: String.downcase(name) in Enum.map(@io_tools, &to_string/1)
    defp io_tool?(_), do: false

    defp post_tool_result(session_id, stream_id, call_id, name, {:ok, payload}) do
      url = API.base_url() <> "/api/sessions/" <> session_id <> "/turns/" <> stream_id <> "/tools/results"
      body = %{"call_id" => call_id, "name" => name, "output" => payload}
      _ = Req.post(url: url, headers: [API.auth_header()], json: body, finch: MaestroTui.Finch)
      :ok
    end
    defp post_tool_result(_sid, _stream, _id, _name, {:error, _}), do: :ok

    defp api_clear_thread(thread_id) do
      url = API.base_url() <> "/api/threads/" <> thread_id <> "/clear"
      case Req.post(url: url, headers: [API.auth_header()], finch: MaestroTui.Finch) do
        {:ok, %Req.Response{status: s}} when s in 200..299 -> :ok
        other -> {:error, other}
      end
    end

    defp dispatch("write_file", json, base) do
      with {:ok, args} <- Jason.decode(json), do: TheMaestro.Tools.WriteFile.run(args, base_cwd: base)
    end
    defp dispatch("write", json, base), do: dispatch("write_file", json, base)
    defp dispatch("create_file", json, base), do: dispatch("write_file", json, base)
    defp dispatch("shell", json, base) do
      with {:ok, args} <- Jason.decode(json), do: TheMaestro.Tools.Shell.run(args, base_cwd: base)
    end
    defp dispatch("bash", json, base), do: dispatch("shell", json, base)
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
    defp dispatch(_other, _json, _base), do: {:error, "unsupported tool"}

    # ----- UI message handling -----
    # ----- Event-driven rendering for SSE frames -----
    def update(%State{} = s, {:ui, {:usage, usage}}) when is_map(usage) do
      %State{s | last_usage: Map.merge(s.last_usage || %{}, usage)}
    end
    def update(%State{screen: :chat} = s, {:event, %{tui: :turn_frame, stream_id: sid, frame: %{"kind" => kind} = frame, session_id: _sess}}) do
      handle_turn_frame(s, sid, frame)
    end

    defp handle_turn_frame(%State{} = s, sid, %{"kind" => kind} = frame) do
      case kind do
        "usage" ->
          usage = frame["payload"] || %{}
          append_line(s, stamp_line("usage", format_usage(usage)))
        "function_call" ->
          calls = get_in(frame, ["payload", "calls"]) || []
          s1 = Enum.reduce(calls, s, fn %{"name" => name, "arguments" => args_json}, acc ->
            prev = String.slice(to_string(args_json || "{}"), 0, 120)
            append_line(acc, stamp_line("tool use", to_string(name) <> " args=" <> prev))
          end)
          put_in_stream(s1, sid, &Map.put(&1, :tool_pending?, true))
        "tool_result" ->
          prev = get_in(frame, ["payload", "preview"]) || ""
          s1 = append_line(s, stamp_line("tool result", String.slice(to_string(prev), 0, 160)))
          s2 = put_in_stream(s1, sid, fn st ->
            buf = (st[:assistant_buf] || "") <> to_string(st[:pending_assistant_text] || "")
            st |> Map.put(:assistant_buf, buf) |> Map.put(:pending_assistant_text, "") |> Map.put(:tool_pending?, false)
          end)
          st = get_stream(s2, sid)
          if (st[:assistant_buf] || "") != "" do
            update_assistant_line(s2, sid, st[:assistant_buf])
          else
            s2
          end
        "assistant_text" ->
          d = to_string(get_in(frame, ["payload", "delta"]) || "")
          s1 = put_in_stream(s, sid, fn st ->
            if Map.get(st, :tool_pending?, false), do: Map.update(st, :pending_assistant_text, d, &(&1 <> d)), else: Map.update(st, :assistant_buf, d, &(&1 <> d))
          end)
          st = get_stream(s1, sid)
          if not Map.get(st, :tool_pending?, false) do
            update_assistant_line(s1, sid, st[:assistant_buf] || "")
          else
            s1
          end
        "assistant_thinking" ->
          content = to_string(get_in(frame, ["payload", "content"]) || "")
          s1 = put_in_stream(s, sid, fn st -> st |> Map.put(:has_thinking, true) |> Map.update(:thinking_buf, content, &(&1 <> content)) end)
          update_thinking_line(s1, sid)
        "final" ->
          content = to_string(get_in(frame, ["payload", "content"]) || "")
          st = get_stream(s, sid)
          base = (st[:assistant_buf] || "") <> to_string(st[:pending_assistant_text] || "")
          text = if content != "", do: content, else: base
          s1 = if text != "", do: update_assistant_line(s, sid, text), else: s
          s2 = append_line(s1, stamp_line("final", ""))
          put_in_stream(s2, sid, fn st2 -> st2 |> Map.put(:assistant_buf, "") |> Map.put(:assistant_shown, "") |> Map.put(:pending_assistant_text, "") |> Map.put(:tool_pending?, false) |> Map.put(:has_thinking, false) end)
        _ -> s
      end
    end
    # removed :tick aggregator — event-driven updates handle everything
    def update(s, _), do: s

    # ----- Slash commands -----
    @slash_cmds [
      %{name: "context", desc: "Show context and token usage", type: :action},
      %{name: "model", desc: "Change model", type: :menu},
      %{name: "help", desc: "Show help and keybindings", type: :action},
      %{name: "clear", desc: "Clear chat context and start new", type: :action},
      %{name: "thinking", desc: "Set thinking visibility: collapsed|expanded|hidden", type: :action},
      %{name: "thoughts", desc: "Alias for /thinking", type: :action}
    ]

    defp run_submit(%State{input: "/" <> _} = s), do: run_slash(s)
    defp run_submit(%State{} = s), do: send_message(s)

    defp run_slash(%State{input: input} = s) do
      query = input |> String.trim() |> String.trim_leading("/")
      matches = slash_matches(query)
      case List.first(matches) do
        %{name: "context"} ->
          log = s.log ++ [format_context(s)]
          %State{s | log: log, input: ""}

        %{name: "model"} ->
          items = if s.models != [], do: s.models, else: (case pick_models(s.provider, s.auth_id) do {:ok, {_, list}} -> list; _ -> [] end)
          if items == [] do
            %State{s | log: s.log ++ ["No models available"], input: ""}
          else
            %State{s | modal: {:model_picker, items, 0}, input: ""}
          end

        %{name: "help"} ->
          %State{s | log: s.log ++ help_lines(), input: ""}

        %{name: "thinking"} ->
          mode = parse_thinking_mode(input)
          %State{s | thinking_visibility: mode, input: "", log: s.log ++ ["thinking: " <> Atom.to_string(mode)]}

        %{name: "thoughts"} ->
          mode = parse_thinking_mode(input)
          %State{s | thinking_visibility: mode, input: "", log: s.log ++ ["thinking: " <> Atom.to_string(mode)]}

        %{name: "clear"} ->
          case s.current_thread_id do
            tid when is_binary(tid) ->
              case api_clear_thread(tid) do
                :ok -> %State{s | last_usage: %{}, log: [], input: ""}
                {:error, r} -> %State{s | log: s.log ++ ["Clear failed: " <> inspect(r)], input: ""}
              end
            _ -> %State{s | log: s.log ++ ["No thread yet; send a message first"], input: ""}
          end

        _ ->
          %State{s | log: s.log ++ ["Unknown command"], input: ""}
      end
    end

    

    defp slash_matches("") do
      @slash_cmds
    end
    defp slash_matches(query) do
      q = String.downcase(query || "")
      Enum.filter(@slash_cmds, fn c -> String.starts_with?(c.name, q) end)
    end

    defp show_slash_suggestions(%State{input: input}) do
      import Ratatouille.View
      query = input |> String.trim_leading("/")
      ms = slash_matches(query) |> Enum.take(5)
      panel title: "/ Commands" do
        for c <- ms do
          label(content: "/" <> c.name <> " — " <> c.desc)
        end
      end
    end

    defp format_context(%State{} = s) do
      u = s.last_usage || %{}
      tokens =
        [
          {"input", Map.get(u, "input_tokens") || Map.get(u, :input_tokens)},
          {"output", Map.get(u, "output_tokens") || Map.get(u, :output_tokens)},
          {"total", Map.get(u, "total_tokens") || Map.get(u, :total_tokens)}
        ]
        |> Enum.filter(fn {_k, v} -> is_integer(v) end)
        |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
        |> Enum.join(", ")

      "Context — provider=#{s.provider || "?"} model=#{s.model || "?"} tokens{#{tokens}}"
    end

    defp help_lines do
      [
        "Help:",
        " - Slash commands: /context, /model, /help, /clear, /thinking [collapsed|expanded|hidden]",
        " - Type '/' to open the command palette; keep typing to filter; Enter to run",
        " - Keys: Enter send, Shift+Enter newline, Ctrl+Shift+L log, Ctrl+Shift+N new session, Ctrl+Shift+T thinking toggle, Ctrl+Shift+] / [ switch session, Ctrl+Shift+P/A/M cycle provider/auth/model",
        " - Wizard: Arrows move, Tab/Shift+Tab change column, Enter to start"
      ]
    end

    # ----- Modal: model picker -----
    defp render_modal(%State{modal: {:model_picker, items, idx}}) do
      import Ratatouille.View
      panel title: "Select Model" do
        for {m, i} <- Enum.with_index(items) do
          label(content: list_item(m, i == idx))
        end
        label(content: "Enter=select  Esc=cancel  ↑/↓=move")
      end
    end

    defp modal_move(%State{modal: {:model_picker, items, idx}} = s, delta) do
      maxi = max(length(items) - 1, 0)
      i = clamp(idx + delta, 0, maxi)
      %State{s | modal: {:model_picker, items, i}}
    end
    defp modal_move(s, _), do: s

    defp handle_modal_enter(%State{modal: {:model_picker, items, idx}} = s) do
      mdl = Enum.at(items, idx)
      %State{s | model: mdl, modal: nil, log: s.log ++ ["model set: " <> to_string(mdl)]}
    end
    defp handle_modal_enter(s), do: s
    defp close_modal(%State{} = s), do: %State{s | modal: nil}

    def cycle_provider(%State{providers: []} = s), do: s
    def cycle_provider(%State{providers: [_]} = s), do: s
    def cycle_provider(%State{providers: provs, provider: pv} = s) do
      idx = Enum.find_index(provs, & &1 == pv) || 0
      nxt = Enum.at(provs, rem(idx + 1, length(provs)))
      %State{s | provider: nxt}
    end

    def cycle_auth(%State{auths: []} = s), do: s
    def cycle_auth(%State{auths: [_]} = s), do: s
    def cycle_auth(%State{auths: auths, auth_id: aid} = s) do
      idx = Enum.find_index(auths, & &1 == aid) || 0
      %State{s | auth_id: Enum.at(auths, rem(idx + 1, length(auths)))}
    end

    def cycle_model(%State{models: []} = s), do: s
    def cycle_model(%State{models: [_]} = s), do: s
    def cycle_model(%State{models: models, model: mdl} = s) do
      idx = Enum.find_index(models, & &1 == mdl) || 0
      %State{s | model: Enum.at(models, rem(idx + 1, length(models)))}
    end

    # Event helpers
    defp event_key?(%{key: code}, name) when is_integer(code), do: code == key(name)
    defp event_key?(_, _), do: false
    defp event_enter?(%{key: code}) when is_integer(code), do: code == key(:enter)
    defp event_enter?(%{ch: ch}) when is_integer(ch), do: ch in [10, 13]
    defp event_enter?(_), do: false

    defp toggle_thinking(%State{thinking_visibility: v} = s) do
      next = case v do
        :collapsed -> :expanded
        :expanded -> :hidden
        _ -> :collapsed
      end
      %State{s | thinking_visibility: next, log: s.log ++ ["thinking: " <> Atom.to_string(next)]}
    end

    defp parse_thinking_mode(input) do
      arg =
        input
        |> String.trim()
        |> String.replace_prefix("/thinking", "")
        |> String.replace_prefix("/thoughts", "")
        |> String.trim()

      case String.downcase(arg || "") do
        "expanded" -> :expanded
        "hidden" -> :hidden
        _ -> :collapsed
      end
    end

    # ----- Stream state helpers (event-driven) -----
    defp put_new_stream(%State{} = s, stream_id, thread_id) do
      st = %{
        thread_id: thread_id,
        assistant_buf: "",
        assistant_shown: "",
        assistant_streaming_idx: nil,
        pending_assistant_text: "",
        tool_pending?: false,
        has_thinking: false,
        thinking_buf: "",
        thinking_streaming_idx: nil
      }
      streams = Map.put(s.streams || %{}, stream_id, st)
      %State{s | streams: streams}
    end

    defp get_stream(%State{} = s, stream_id), do: (s.streams || %{})[stream_id] || %{}

    defp put_in_stream(%State{} = s, stream_id, fun) when is_function(fun, 1) do
      cur = get_stream(s, stream_id)
      new = fun.(cur)
      %State{s | streams: Map.put(s.streams || %{}, stream_id, new)}
    end

    defp update_assistant_line(%State{} = s, stream_id, text) when is_binary(text) do
      st = get_stream(s, stream_id)
      case st[:assistant_streaming_idx] do
        i when is_integer(i) and i >= 1 ->
          tr = replace_at(s.transcript || [], i, stamp_line("assistant", text))
          s1 = %State{s | transcript: tr}
          put_in_stream(s1, stream_id, fn st2 -> Map.put(st2, :assistant_shown, text) end)
        _ ->
          idx = length(s.transcript || []) + 1
          s1 = add_transcript(s, stamp_line("assistant", text))
          put_in_stream(s1, stream_id, fn st2 -> st2 |> Map.put(:assistant_streaming_idx, idx) |> Map.put(:assistant_shown, text) end)
      end
    end

    defp update_thinking_line(%State{} = s, stream_id) do
      st = get_stream(s, stream_id)
      if Map.get(st, :has_thinking, false) do
        txt = st[:thinking_buf] || ""
        display = case s.thinking_visibility do
          :hidden -> "thinking (hidden)"
          :collapsed -> "…thinking…"
          :expanded -> if txt == "", do: "…thinking…", else: "Thinking: " <> txt
        end
        case st[:thinking_streaming_idx] do
          i when is_integer(i) and i >= 1 ->
            tr = replace_at(s.transcript || [], i, stamp_line("assistant", display))
            %State{s | transcript: tr}
          _ ->
            idx = length(s.transcript || []) + 1
            s1 = add_transcript(s, stamp_line("assistant", display))
            put_in_stream(s1, stream_id, fn st2 -> Map.put(st2, :thinking_streaming_idx, idx) end)
        end
      else
        s
      end
    end
  end
