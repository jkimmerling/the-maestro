defmodule MaestroTui.API do
  @moduledoc false

  @spec base_url() :: String.t()
  def base_url do
    System.get_env("TUI_API_BASE_URL") || "http://localhost:4000"
  end

  @spec auth_header() :: {binary(), binary()}
  def auth_header do
    token = System.get_env("TUI_API_TOKEN") || "0000000000000000"
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
end

