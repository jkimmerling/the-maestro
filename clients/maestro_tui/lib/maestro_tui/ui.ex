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
                transcript: [], stream_buffer: nil,
                input: "",
                session_id: nil, current_thread_id: nil, stream_task: nil,
                stream_id: nil, stream_consumed: 0,
                assistant_placeholder_at: nil,
                working_dir: File.cwd!()
    end

    @impl true
    def init(_context) do
      if :ets.whereis(:maestro_tui_streams) == :undefined do
        :ets.new(:maestro_tui_streams, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])
      end
      case API.providers() do
        {:ok, providers} -> %State{providers: providers}
        {:error, _} -> %State{providers: [], log: ["API unavailable — set TUI_API_BASE_URL and TUI_API_TOKEN"]}
      end
    end

    @impl true
    def subscribe(_model) do
      Ratatouille.Runtime.Subscription.interval(100, :tick)
    end

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

    defp clamp(i, lo, hi) when i < lo, do: lo
    defp clamp(i, lo, hi) when i > hi, do: hi
    defp clamp(i, _lo, _hi), do: i

    # Chat: printable characters first to ensure typing works
    def update(%State{screen: :chat} = s, {:event, %{ch: ch}}) when is_integer(ch) and ch >= 32 do
      %State{s | input: s.input <> <<ch::utf8>>}
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
        false -> false
      end
    end

    defp to_ctrl_key(?L), do: :ctrl_l
    defp to_ctrl_key(?N), do: :ctrl_n
    defp to_ctrl_key(_), do: nil

    defp shift?(ev) do
      Map.get(ev, :mod) in [:shift, :ctrl_shift] or Map.get(ev, :shift) == true
    end

    import Ratatouille.Constants, only: [key: 1]
    defp backspace?(%{key: k}) when is_integer(k), do: k in [key(:backspace), key(:backspace2)]
    defp backspace?(_), do: false

    @transcript_limit 500
    defp add_transcript(%State{} = s, line) when is_binary(line) do
      tlog("add_transcript line=" <> String.slice(line, 0, 40))
      tr = Enum.take(s.transcript ++ [line], -@transcript_limit)
      %State{s | transcript: tr}
    end

    defp add_stream_chunk(%State{stream_buffer: nil} = s, chunk) when is_binary(chunk) do
      parts = String.split(chunk, "\n")
      start = stamp_line("assistant", List.first(parts) || "")
      tlog("add_stream_chunk start=" <> String.slice(start, 0, 40))
      tr = Enum.take(s.transcript ++ [start], -@transcript_limit)
      tr2 =
        Enum.reduce(Enum.drop(parts, 1), tr, fn piece, acc ->
          if piece == "" do
            acc
          else
            Enum.take(acc ++ [piece], -@transcript_limit)
          end
        end)
      %State{s | transcript: tr2, stream_buffer: start}
    end
    defp add_stream_chunk(%State{stream_buffer: buf} = s, chunk) when is_binary(chunk) do
      parts = String.split(chunk, "\n")
      case parts do
        [only] ->
          new_buf = (buf || "") <> only
          tlog("add_stream_chunk cont size=" <> Integer.to_string(byte_size(new_buf)))
          tr = replace_last(s.transcript, new_buf)
          %State{s | transcript: tr, stream_buffer: new_buf}
        [first | rest] ->
          new_buf = (buf || "") <> first
          tr = replace_last(s.transcript, new_buf)
          tr2 =
            Enum.reduce(rest, tr, fn piece, acc ->
              if piece == "" do
                acc
              else
                Enum.take(acc ++ [piece], -@transcript_limit)
              end
            end)
          %State{s | transcript: tr2, stream_buffer: new_buf}
      end
    end
    defp add_stream_chunk(%State{} = s, _), do: s

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
    defp replace_placeholder(%State{assistant_placeholder_at: idx} = s, final_line) when is_integer(idx) do
      tr = replace_at(s.transcript || [], idx, final_line)
      %State{s | transcript: tr, assistant_placeholder_at: nil}
    end
    defp replace_placeholder(%State{} = s, final_line) do
      %State{s | transcript: replace_last(s.transcript || [], final_line), assistant_placeholder_at: nil}
    end
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

    defp append_line_to_stream(stream_id, add_line) do
      case :ets.lookup(:maestro_tui_streams, stream_id) do
        [{^stream_id, %{} = m}] ->
          lines = Map.get(m, :lines, [])
          :ets.insert(:maestro_tui_streams, {stream_id, Map.put(m, :lines, lines ++ [add_line])})
        _ ->
          :ets.insert(:maestro_tui_streams, {stream_id, %{assistant: "", lines: [add_line], placeholder_pending: false, placeholder_inserted: false, done: false}})
      end
      :ok
    end

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
      tlog("render chat transcript_size=" <> Integer.to_string(length(s.transcript || [])))
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
          if s.modal do
            render_modal(s)
          end
        end
      end
    end
    
    # ----- SSE integration -----
    @io_tools ~w(apply_patch write_file write create_file edit multi_edit list_directory glob grep shell run_shell_command notebook_edit)a

    defp send_message(%State{} = s) do
      text = String.trim(s.input)
      case ensure_session(s) do
        {:ok, sid} ->
          case start_turn(sid, text) do
            {:ok, %{"stream_id" => stream_id, "thread_id" => tid}} ->
              ui_pid = self()
              :ets.insert(:maestro_tui_streams, {stream_id, %{assistant: "", lines: [], placeholder_pending: false, placeholder_inserted: false, done: false}})
              spawn(fn -> consume_sse(sid, stream_id, s.working_dir, ui_pid) end)
              s
              |> add_transcript(stamp_line("you", text))
              |> Map.put(:input, "")
              |> Map.put(:log, s.log ++ ["> " <> text])
              |> Map.put(:stream_buffer, nil)
              |> Map.put(:stream_id, stream_id)
              |> Map.put(:stream_consumed, 0)
              |> Map.put(:assistant_placeholder_at, nil)
              |> Map.put(:session_id, sid)
              |> Map.put(:current_thread_id, tid)
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
              Enum.each(events, fn ev -> handle_event(session_id, stream_id, ev, workdir, ui) end)
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

    defp handle_event(_sid, stream_id, %{data: %{"kind" => "assistant_text", "payload" => %{"delta" => d}}}, _wd, _ui) when is_binary(d) do
      tlog("assistant_text " <> Integer.to_string(byte_size(d)) <> "B")
      case :ets.lookup(:maestro_tui_streams, stream_id) do
        [{^stream_id, %{} = m}] ->
          buf = Map.get(m, :assistant, "") <> d
          first? = Map.get(m, :assistant, "") == ""
          m2 = m
          |> Map.put(:assistant, buf)
          |> Map.put(:placeholder_pending, first? || Map.get(m, :placeholder_pending, false))
          :ets.insert(:maestro_tui_streams, {stream_id, m2})
        _ ->
          :ets.insert(:maestro_tui_streams, {stream_id, %{assistant: d, lines: [], placeholder_pending: true, placeholder_inserted: false, done: false}})
      end
    end
    defp handle_event(_sid, stream_id, %{data: %{"kind" => "usage", "payload" => usage}}, _wd, _ui) when is_map(usage) do
      append_line_to_stream(stream_id, stamp_line("usage", format_usage(usage)))
    end
    defp handle_event(session_id, stream_id, %{data: %{"kind" => "function_call", "payload" => %{"calls" => calls}}}, workdir, _ui) do
      Enum.each(calls, fn %{"name" => name, "arguments" => args_json} ->
        prev = String.slice(to_string(args_json || "{}"), 0, 120)
        append_line_to_stream(stream_id, stamp_line("tool use", to_string(name) <> " args=" <> prev))
      end)
      Enum.each(calls, fn %{"id" => id, "name" => name, "arguments" => args_json} ->
        if io_tool?(name) do
          result = exec_local(name, args_json, workdir)
          post_tool_result(session_id, stream_id, id, name, result)
        end
      end)
    end
    defp handle_event(_sid, stream_id, %{data: %{"kind" => "tool_result", "payload" => payload}}, _wd, _ui) do
      prev = payload["preview"] || ""
      append_line_to_stream(stream_id, stamp_line("tool result", String.slice(to_string(prev), 0, 160)))
    end
    defp handle_event(_sid, stream_id, %{data: %{"kind" => "done"}}, _wd, _ui) do
      case :ets.lookup(:maestro_tui_streams, stream_id) do
        [{^stream_id, %{} = m}] -> :ets.insert(:maestro_tui_streams, {stream_id, Map.put(m, :done, true)})
        _ -> :ok
      end
    end
    defp handle_event(_sid, _stream, _ev, _wd, _ui), do: :ok

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
    def update(%State{} = s, {:ui, {:append_text, text}}) when is_binary(text) do
      tlog("update append_text len=" <> Integer.to_string(byte_size(text)))
      s2 = add_stream_chunk(s, text)
      tlog("transcript_size=" <> Integer.to_string(length(s2.transcript || [])))
      %State{s2 | log: s2.log ++ [text]}
    end
    def update(%State{} = s, {:ui, {:usage, usage}}) when is_map(usage) do
      %State{s | last_usage: Map.merge(s.last_usage || %{}, usage)}
    end
    def update(%State{screen: :chat, stream_id: sid} = s, :tick) when is_binary(sid) do
      case :ets.lookup(:maestro_tui_streams, sid) do
        [{^sid, %{} = m}] ->
          # Flush queued lines (tool use/results, usage)
          s1 = Enum.reduce(Map.get(m, :lines, []), s, fn line, acc -> add_transcript(acc, line) end)
          m = Map.put(m, :lines, [])

          # Insert thinking placeholder once
          {s2, m} =
            if Map.get(m, :placeholder_pending, false) and not Map.get(m, :placeholder_inserted, false) do
              idx = length(s1.transcript || []) + 1
              s2 = add_transcript(s1, stamp_line("assistant", "…thinking…"))
              {Map.put(s2, :assistant_placeholder_at, idx), m |> Map.put(:placeholder_pending, false) |> Map.put(:placeholder_inserted, true)}
            else
              {s1, m}
            end

          # If done, replace placeholder with final assistant text
          s3 =
            if Map.get(m, :done, false) do
              final = stamp_line("assistant", Map.get(m, :assistant, ""))
              s2a = replace_placeholder(s2, final)
              # reset entry
              :ets.insert(:maestro_tui_streams, {sid, %{assistant: "", lines: [], placeholder_pending: false, placeholder_inserted: false, done: false}})
              s2a
            else
              :ets.insert(:maestro_tui_streams, {sid, m})
              s2
            end

          s3
        _ -> s
      end
    end
    def update(s, _), do: s

    # ----- Slash commands -----
    @slash_cmds [
      %{name: "context", desc: "Show context and token usage", type: :action},
      %{name: "model", desc: "Change model", type: :menu},
      %{name: "help", desc: "Show help and keybindings", type: :action},
      %{name: "clear", desc: "Clear chat context and start new", type: :action}
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
        " - Slash commands: /context, /model, /help, /clear",
        " - Type '/' to open the command palette; keep typing to filter; Enter to run",
        " - Keys: Enter send, Shift+Enter newline, Ctrl+Shift+L log, Ctrl+Shift+N new session, Ctrl+Shift+] / [ switch session, Ctrl+Shift+P/A/M cycle provider/auth/model",
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
  end
