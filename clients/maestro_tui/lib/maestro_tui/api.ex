defmodule MaestroTui.API do
  @moduledoc false

  @spec base_url() :: String.t()
  def base_url do
    case MaestroTui.Config.load_config() do
      {:ok, %{api_host: host}} -> host
      {:error, _} -> "http://localhost:4000"
    end
  end

  @spec auth_header() :: {binary(), binary()}
  def auth_header do
    token =
      case MaestroTui.Config.load_config() do
        {:ok, %{api_key: key}} -> key
        {:error, _} -> "0000000000000000"
      end

    {"authorization", "Bearer " <> token}
  end

  @spec providers() :: {:ok, [String.t()]} | {:error, term()}
  def providers do
    req = Req.new(finch: MaestroTui.Finch, headers: [auth_header()])
    case Req.get(req, url: base_url() <> "/api/providers") do
      {:ok, %Req.Response{status: 200, body: %{"providers" => list}}} -> {:ok, list}
      other -> {:error, other}
    end
  end

  @spec update_session(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def update_session(session_id, auth_id, model) do
    url = base_url() <> "/api/sessions/" <> session_id
    body = %{"auth_id" => auth_id, "model_id" => model}

    case Req.patch(url: url, headers: [auth_header()], json: body, finch: MaestroTui.Finch) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> {:ok, body}
      other -> {:error, other}
    end
  end
end

