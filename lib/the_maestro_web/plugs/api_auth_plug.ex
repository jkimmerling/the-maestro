defmodule TheMaestroWeb.ApiAuthPlug do
  @moduledoc false
  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- valid_token?(token) do
      conn
    else
      _ -> unauthorized(conn)
    end
  end

  defp valid_token?(token) when is_binary(token) do
    expected = Application.get_env(:the_maestro, :api, []) |> Keyword.get(:token)

    if is_binary(expected) and token == expected do
      true
    else
      case TheMaestro.ApiKeys.lookup_valid_by_token(token) do
        %TheMaestro.ApiKeys.ApiKey{} = key ->
          _ = TheMaestro.ApiKeys.mark_used!(key)
          true

        _ ->
          false
      end
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"unauthorized"}))
    |> halt()
  end
end
