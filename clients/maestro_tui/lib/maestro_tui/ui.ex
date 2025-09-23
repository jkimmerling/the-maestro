if System.get_env("TUI_ENABLE_TUI") in ["1", "true", "TRUE"] do
  defmodule MaestroTui.UI do
    @moduledoc false
    alias MaestroTui.API

    def run do
      Ratatouille.run(%Ratatouille.Runtime{subscribe: &subscribe/1, update: &update/2, render: &render/1, init: &init/0})
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
                log_visible: false, log: [], input: "",
                session_id: nil, current_thread_id: nil, stream_task: nil,
                working_dir: File.cwd!()
    end

    defp init do
      {:ok, providers} = API.providers()
      %State{providers: providers}
    end

    defp subscribe(_state), do: []

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
    def update(%State{screen: :wizard} = s, {:event, %{key: :up}}), do: move_index(s, -1)
    def update(%State{screen: :wizard} = s, {:event, %{key: :down}}), do: move_index(s, 1)
    def update(%State{screen: :wizard} = s, {:event, %{key: :left}}), do: move_focus(s, -1)
    def update(%State{screen: :wizard} = s, {:event, %{key: :right}}), do: move_focus(s, 1)
    def update(%State{screen: :wizard} = s, {:event, %{key: :tab}}), do: move_focus(s, 1)
    def update(%State{screen: :wizard} = s, {:event, %{key: :backtab}}), do: move_focus(s, -1)
    def update(%State{screen: :wizard} = s, _msg), do: s

    defp move_focus(%State{wizard_focus: :provider} = s, 1), do: %State{s | wizard_focus: :auth}
    defp move_focus(%State{wizard_focus: :auth} = s, 1), do: %State{s | wizard_focus: :model}
    defp move_focus(%State{wizard_focus: :model} = s, 1), do: s
    defp move_focus(%State{wizard_focus: :model} = s, -1), do: %State{s | wizard_focus: :auth}
    defp move_focus(%State{wizard_focus: :auth} = s, -1), do: %State{s | wizard_focus: :provider}
    defp move_focus(%State{wizard_focus: :provider} = s, -1), do: s

    defp move_index(%State{wizard_focus: :provider} = s, delta) do
      maxi = max(length(s.providers) - 1, 0)
      i = clamp(s.prov_idx + delta, 0, maxi)
      pv = Enum.at(s.providers, i)
      %State{s | prov_idx: i, provider: pv, auths: [], models: [], auth_idx: 0, model_idx: 0}
    end

    defp move_index(%State{wizard_focus: :auth} = s, delta) do
      auths = if s.auths == [], do: (case pick_auths(s.provider) do {:ok, {_, list}} -> list; _ -> [] end), else: s.auths
      maxi = max(length(auths) - 1, 0)
      i = clamp(s.auth_idx + delta, 0, maxi)
      aid = Enum.at(auths, i)
      %State{s | auths: auths, auth_idx: i, auth_id: aid, models: [], model_idx: 0}
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

    def update(%State{screen: :chat} = s, {:event, ev}) when is_map(ev) and Map.get(ev, :key) in [:enter, "Enter"] do
      # If a modal is open, Enter selects inside modal
      if s.modal do
        handle_modal_enter(s)
      else if shift?(ev) do
        %State{s | input: s.input <> "\n"}
      else
        run_submit(s)
      end
      end
    end

    def update(%State{screen: :chat} = s, {:event, %{ch: 10}}) do
      text = String.trim(s.input)
      if text == "" do
        s
      else
        send_message(s)
      end
    end
    def update(%State{screen: :chat, log_visible: lv} = s, {:event, ev}) when is_map(ev) do
      # Modal navigation takes priority
      if s.modal do
        case Map.get(ev, :key) do
          :up -> modal_move(s, -1)
          :down -> modal_move(s, 1)
          :escape -> close_modal(s)
          _ -> s
        end
      else
      cond do
        ctrl_shift?(ev, ?L) -> %State{s | log_visible: !lv}
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
    end
    def update(%State{screen: :chat} = s, {:event, %{ch: ch}}) when is_integer(ch) and ch >= 32 do
      %State{s | input: s.input <> <<ch::utf8>>}
    end
    def update(s, _), do: s

    defp ensure_session(%State{session_id: sid} = _s) when is_binary(sid), do: {:ok, sid}
    defp ensure_session(%State{} = s) do
      url = API.base_url() <> "/api/sessions"
      body = %{"auth_id" => s.auth_id, "model" => s.model, "working_dir" => s.working_dir, "tool_runtime" => "remote"}
      case Req.post(url: url, headers: [API.auth_header()], json: body, finch: MaestroTui.Finch) do
        {:ok, %Req.Response{status: 200, body: %{"session_id" => sid}}} -> {:ok, sid}
        _ -> {:error, :session}
      end
    end

    def pick_auths(provider) do
      url = API.base_url() <> "/api/providers/" <> provider <> "/saved_auths"
      case Req.get(url: url, headers: [API.auth_header()], finch: MaestroTui.Finch) do
        {:ok, %Req.Response{status: 200, body: %{"auths" => list}}} when is_list(list) and list != [] ->
          ids = Enum.map(list, & &1["id"]) |> Enum.filter(&is_binary/1)
          {:ok, {hd(ids), ids}}
        _ -> {:error, :auth}
      end
    end

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

    defp backspace?(%{key: k}) when k in [:backspace, :backspace2, "Backspace"], do: true
    defp backspace?(_), do: false

    defp render(%State{screen: :wizard, providers: providers, prov_idx: pidx, auths: auths, auth_idx: aidx, models: models, model_idx: midx, wizard_focus: focus}) do
      import Ratatouille.View
      view do
        panel title: "Provider / Auth / Model" do
          label(content: "Arrows=move  Tab/Shift+Tab=switch  Enter=start")
          columns do
            column size: 4 do
              panel title: focus_title(:provider, focus) do
                for {p, i} <- Enum.with_index(providers) do
                  label(content: list_item(p, i == pidx))
                end
              end
            end
            column size: 4 do
              panel title: focus_title(:auth, focus) do
                for {a, i} <- Enum.with_index(auths) do
                  label(content: list_item(a || "", i == aidx))
                end
              end
            end
            column size: 4 do
              panel title: focus_title(:model, focus) do
                for {m, i} <- Enum.with_index(models) do
                  label(content: list_item(m || "", i == midx))
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
              spawn(fn -> consume_sse(sid, stream_id, s.working_dir) end)
              %State{s | input: "", log: s.log ++ ["> " <> text], session_id: sid, current_thread_id: tid}
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

    defp consume_sse(session_id, stream_id, workdir) do
      url = API.base_url() <> "/api/sessions/" <> session_id <> "/turns/" <> stream_id <> "/frames"
      req = Req.new(headers: [API.auth_header()], finch: MaestroTui.Finch)
      case Req.request(req, method: :get, url: url, into: :self, receive_timeout: :infinity) do
        {:ok, %Req.Response{status: 200, body: stream}} ->
          ui = self()
          for chunk <- stream do
            for ev <- parse_sse(chunk) do
              handle_event(session_id, stream_id, ev, workdir, ui)
            end
          end
          :ok
        _ -> :ok
      end
    end

    defp parse_sse(chunk) do
      data = IO.iodata_to_binary(chunk)
      data
      |> String.split("\n\n", trim: true)
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
    end

    defp handle_event(session_id, stream_id, %{data: %{"kind" => "assistant_text", "payload" => %{"delta" => d}}}, _wd, ui) when is_binary(d) do
      send(ui, {:ui, {:append_text, d}})
    end
    defp handle_event(_sid, _stream, %{data: %{"kind" => "usage", "payload" => usage}}, _wd, ui) when is_map(usage) do
      send(ui, {:ui, {:usage, usage}})
    end
    defp handle_event(session_id, stream_id, %{data: %{"kind" => "function_call", "payload" => %{"calls" => calls}}}, workdir, ui) do
      Enum.each(calls, fn %{"id" => id, "name" => name, "arguments" => args_json} ->
        if io_tool?(name) do
          result = exec_local(name, args_json, workdir)
          post_tool_result(session_id, stream_id, id, name, result)
        end
      end)
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
      %State{s | log: s.log ++ [text]}
    end
    def update(%State{} = s, {:ui, {:usage, usage}}) when is_map(usage) do
      %State{s | last_usage: Map.merge(s.last_usage || %{}, usage)}
    end

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
  end
else
  defmodule MaestroTui.UI do
    @moduledoc false
    def run, do: IO.puts(:stderr, "UI not available. Set TUI_ENABLE_TUI=1 and run deps.")
  end
end
