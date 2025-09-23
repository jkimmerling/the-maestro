if Code.ensure_loaded?(Ratatouille) do
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
                sessions: %{}, order: [], active: nil,
                log_visible: false, log: [], input: "",
                session_id: nil, stream_task: nil,
                working_dir: File.cwd!()
    end

    defp init do
      {:ok, providers} = API.providers()
      %State{providers: providers}
    end

    defp subscribe(_state), do: []

    defp update(%State{screen: :wizard} = s, {:event, %{ch: 10}}) do
      prov = s.provider || List.first(s.providers)
      with {:ok, auth} <- pick_auth(prov), {:ok, model} <- pick_model(prov, auth) do
        sid = nil
        s1 = %State{s | screen: :chat, provider: prov, auth_id: auth, model: model, session_id: sid}
        put_new_session(s1)
      else
        _ -> s
      end
    end
    defp update(%State{screen: :wizard} = s, _msg), do: s

    defp update(%State{screen: :chat} = s, {:event, ev}) when is_map(ev) and Map.get(ev, :key) in [:enter, "Enter"] do
      if shift?(ev) do
        %State{s | input: s.input <> "\n"}
      else
        send_message(s)
      end
    end

    defp update(%State{screen: :chat} = s, {:event, %{ch: 10}}) do
      text = String.trim(s.input)
      if text == "" do
        s
      else
        send_message(s)
      end
    end
    defp update(%State{screen: :chat, log_visible: lv} = s, {:event, ev}) when is_map(ev) do
      cond do
        ctrl_shift?(ev, ?L) -> %State{s | log_visible: !lv}
        ctrl_shift?(ev, ?N) -> new_session(s)
        ctrl_shift?(ev, :tab_next) -> next_session(s)
        ctrl_shift?(ev, :tab_prev) -> prev_session(s)
        backspace?(ev) -> %State{s | input: String.slice(s.input, 0, max(byte_size(s.input) - 1, 0))}
        true -> s
      end
    end
    defp update(%State{screen: :chat} = s, {:event, %{ch: ch}}) when is_integer(ch) and ch >= 32 do
      %State{s | input: s.input <> <<ch::utf8>>}
    end
    defp update(s, _), do: s

    defp ensure_session(%State{session_id: sid} = _s) when is_binary(sid), do: {:ok, sid}
    defp ensure_session(%State{} = s) do
      url = API.base_url() <> "/api/sessions"
      body = %{"auth_id" => s.auth_id, "model" => s.model, "working_dir" => s.working_dir, "tool_runtime" => "remote"}
      case Req.post(url: url, headers: [API.auth_header()], json: body, finch: MaestroTui.Finch) do
        {:ok, %Req.Response{status: 200, body: %{"session_id" => sid}}} -> {:ok, sid}
        _ -> {:error, :session}
      end
    end

    defp pick_auth(provider) do
      url = API.base_url() <> "/api/providers/" <> provider <> "/saved_auths"
      case Req.get(url: url, headers: [API.auth_header()], finch: MaestroTui.Finch) do
        {:ok, %Req.Response{status: 200, body: %{"auths" => [first | _]}}} -> {:ok, first["id"]}
        _ -> {:error, :auth}
      end
    end

    defp pick_model(provider, auth_id) do
      url = API.base_url() <> "/api/providers/" <> provider <> "/saved_auths/" <> auth_id <> "/models"
      case Req.get(url: url, headers: [API.auth_header()], finch: MaestroTui.Finch) do
        {:ok, %Req.Response{status: 200, body: %{"models" => [m | _]}}} -> {:ok, m}
        _ -> {:error, :model}
      end
    end

    defp put_new_session(%State{session_id: sid} = s) do
      id = sid || (length(s.order) + 1) |> to_string()
      sessions = Map.put_new(s.sessions, id, %{log: [], input: ""})
      %State{s | sessions: sessions, order: s.order ++ [id], active: id}
    end

    defp send_message(%State{} = s) do
      text = String.trim(s.input)
      case ensure_session(s) do
        {:ok, sid} ->
          spawn(fn -> MaestroTui.Headless.run(provider: s.provider, auth_id: s.auth_id, model: s.model, working_dir: s.working_dir, message: text) end)
          log = s.log ++ ["> " <> text]
          %State{s | input: "", log: log, session_id: sid}
        _ -> s
      end
    end

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

    defp ctrl_shift?(%{key: k}, :tab_next) when k in ["Tab", :tab], do: false
    defp ctrl_shift?(%{key: k}, :tab_prev) when k in ["Tab", :tab], do: false
    defp ctrl_shift?(ev, code) do
      mod = Map.get(ev, :mod)
      key = Map.get(ev, :key)
      ch = Map.get(ev, :ch)
      cond do
        mod in [:ctrl, :ctrl_shift] and is_integer(code) and (key == to_ctrl_key(code) or ch == code) -> true
        key in [:ctrl_l, :ctrl_L] and code in [?
L, ?l] -> true
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

    defp render(%State{screen: :wizard, providers: providers}) do
      import Ratatouille.View
      view do
        panel title: "Provider / Auth / Model" do
          label(content: "Providers: #{Enum.join(providers, ", ")}")
          label(content: "Press Enter to continue")
        end
      end
    end

    defp render(%State{screen: :chat, input: input, log: log, log_visible: lv}) do
      import Ratatouille.View
      view do
        panel title: "Chat" do
          if lv do
            for line <- Enum.take(log, -200) do
              label(content: line)
            end
          else
            label(content: "(log hidden) Press Ctrl+Shift+L to toggle")
          end
          label(content: "> " <> input)
        end
      end
    end
  end
else
  defmodule MaestroTui.UI do
    @moduledoc false
    def run, do: IO.puts(:stderr, "UI not available. Set TUI_ENABLE_TUI=1 and run deps.")
  end
end
