defmodule TheMaestroWeb.ApiAuthPlug do
  @moduledoc false
  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        expected =
          Application.get_env(:the_maestro, :api, []) |> Keyword.get(:token, "0000000000000000")

        if token == expected, do: conn, else: unauthorized(conn)

      _ ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"unauthorized"}))
    |> halt()
  end
end
