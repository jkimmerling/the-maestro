defmodule TheMaestroWeb.ApiProvidersControllerTest do
  use TheMaestroWeb.ConnCase, async: true

  @token "0000000000000000"

  test "GET /api/providers returns list", %{conn: conn} do
    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get(~p"/api/providers")
      |> json_response(200)

    assert is_list(resp["providers"]) and Enum.all?(resp["providers"], &is_binary/1)
  end

  test "GET /api/providers/:provider/saved_auths returns list (may be empty)", %{conn: conn} do
    provider = "openai"

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get(~p"/api/providers/#{provider}/saved_auths")
      |> json_response(200)

    assert is_map(resp) and Map.has_key?(resp, "auths")
  end
end
