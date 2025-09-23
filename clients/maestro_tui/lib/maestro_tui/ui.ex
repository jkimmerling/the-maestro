if Code.ensure_loaded?(Ratatouille) do
  defmodule MaestroTui.UI do
    @moduledoc false
    alias MaestroTui.API

    def run do
      Ratatouille.run(%Ratatouille.Runtime{subscribe: &subscribe/1, update: &update/2, render: &render/1, init: &init/0})
    end

    defmodule State do
      defstruct screen: :wizard, providers: [], provider: nil, auths: [], auth_id: nil, models: [], model: nil,
                log: [], input: "", session_id: nil, stream_task: nil, working_dir: File.cwd!()
    end

    defp init do
      {:ok, providers} = API.providers()
      %State{providers: providers}
    end

    defp subscribe(_state), do: []

    defp update(%State{screen: :wizard} = s, {:event, %{ch: 10}}) do
      prov = s.provider || List.first(s.providers)
      with {:ok, auth} <- pick_auth(prov), {:ok, model} <- pick_model(prov, auth) do
        %State{s | screen: :chat, provider: prov, auth_id: auth, model: model}
      else
        _ -> s
      end
    end
    defp update(%State{screen: :wizard} = s, _msg), do: s

    defp update(%State{screen: :chat} = s, {:event, %{ch: 10}}) do
      text = String.trim(s.input)
      if text == "" do
        s
      else
        case ensure_session(s) do
          {:ok, sid} ->
            spawn(fn -> MaestroTui.Headless.run(provider: s.provider, auth_id: s.auth_id, model: s.model, working_dir: s.working_dir, message: text) end)
            %State{s | input: "", log: s.log ++ ["> " <> text], session_id: sid}
          _ -> s
        end
      end
    end
    defp update(%State{screen: :chat} = s, {:event, %{key: k}}) when is_binary(k) do
      case k do
        "Backspace" -> %State{s | input: String.slice(s.input, 0, max(byte_size(s.input) - 1, 0))}
        _ -> s
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

    defp render(%State{screen: :wizard, providers: providers}) do
      import Ratatouille.View
      view do
        panel title: "Provider / Auth / Model" do
          label(content: "Providers: #{Enum.join(providers, ", ")}")
          label(content: "Press Enter to continue")
        end
      end
    end

    defp render(%State{screen: :chat, input: input, log: log}) do
      import Ratatouille.View
      view do
        panel title: "Chat" do
          for line <- Enum.take(log, -200) do
            label(content: line)
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

