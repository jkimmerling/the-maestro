defmodule TheMaestroWeb.CliAuthControllerTest do
  use TheMaestroWeb.ConnCase

  alias TheMaestroWeb.CliAuthController

  describe "POST /api/cli/auth/device" do
    test "generates device code and verification URLs", %{conn: conn} do
      conn = post(conn, ~p"/api/cli/auth/device")

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      # Check required fields are present
      assert Map.has_key?(response, "device_code")
      assert Map.has_key?(response, "user_code")
      assert Map.has_key?(response, "verification_uri")
      assert Map.has_key?(response, "verification_uri_complete")
      assert Map.has_key?(response, "expires_in")
      assert Map.has_key?(response, "interval")

      # Check field types and basic validation
      assert is_binary(response["device_code"])
      assert is_binary(response["user_code"])
      assert String.length(response["user_code"]) == 6
      # 15 minutes
      assert response["expires_in"] == 900
      # 5 seconds
      assert response["interval"] == 5

      # Check URLs are properly formatted
      assert String.contains?(response["verification_uri"], "/api/cli/auth/authorize")
      assert String.contains?(response["verification_uri_complete"], response["user_code"])
    end
  end

  describe "GET /api/cli/auth/authorize" do
    test "renders authorization page", %{conn: conn} do
      conn = get(conn, ~p"/api/cli/auth/authorize")

      assert html_response(conn, 200)
      response_body = html_response(conn, 200)

      # Check essential elements are present
      assert response_body =~ "Authorize Device"
      assert response_body =~ "user_code"
      assert response_body =~ "form"
    end

    test "pre-fills user code from query parameter", %{conn: conn} do
      user_code = "ABC123"
      conn = get(conn, ~p"/api/cli/auth/authorize?user_code=#{user_code}")

      assert html_response(conn, 200)
      response_body = html_response(conn, 200)

      assert response_body =~ user_code
    end
  end

  describe "POST /api/cli/auth/authorize" do
    setup do
      # Initialize the ETS table for testing
      CliAuthController.init_device_codes_store()

      # Generate a test device code entry
      device_code = "test_device_code_123"
      user_code = "TEST12"
      # 15 minutes from now
      expires_at = DateTime.add(DateTime.utc_now(), 900, :second)

      device_info = %{
        device_code: device_code,
        user_code: user_code,
        expires_at: expires_at,
        authorized: false,
        access_token: nil,
        error: nil
      }

      :ets.insert(:device_codes_store, {device_code, device_info})

      %{device_code: device_code, user_code: user_code}
    end

    test "redirects to OAuth with valid user code", %{conn: conn, user_code: user_code} do
      conn =
        conn
        |> init_test_session(%{})
        |> post(~p"/api/cli/auth/authorize", %{"user_code" => user_code})

      assert redirected_to(conn) == "/auth/google?state=device_auth"

      # Check session contains pending device code
      assert get_session(conn, :pending_device_code)
      assert get_session(conn, :user_code) == user_code
    end

    test "renders error with invalid user code", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> post(~p"/api/cli/auth/authorize", %{"user_code" => "INVALID"})

      assert html_response(conn, 200)
      response_body = html_response(conn, 200)

      assert response_body =~ "Invalid user code"
    end

    test "renders error with expired user code", %{conn: conn} do
      # Create an expired device code
      device_code = "expired_device_code_123"
      user_code = "EXPIR1"
      # 1 minute ago
      expires_at = DateTime.add(DateTime.utc_now(), -60, :second)

      device_info = %{
        device_code: device_code,
        user_code: user_code,
        expires_at: expires_at,
        authorized: false,
        access_token: nil,
        error: nil
      }

      :ets.insert(:device_codes_store, {device_code, device_info})

      conn =
        conn
        |> init_test_session(%{})
        |> post(~p"/api/cli/auth/authorize", %{"user_code" => user_code})

      assert html_response(conn, 200)
      response_body = html_response(conn, 200)

      assert response_body =~ "expired"
    end
  end

  describe "GET /api/cli/auth/poll" do
    setup do
      CliAuthController.init_device_codes_store()

      device_code = "test_device_code_456"
      expires_at = DateTime.add(DateTime.utc_now(), 900, :second)

      device_info = %{
        device_code: device_code,
        user_code: "TEST34",
        expires_at: expires_at,
        authorized: false,
        access_token: nil,
        error: nil
      }

      :ets.insert(:device_codes_store, {device_code, device_info})

      %{device_code: device_code}
    end

    test "returns authorization_pending for pending authorization", %{
      conn: conn,
      device_code: device_code
    } do
      conn = get(conn, ~p"/api/cli/auth/poll?device_code=#{device_code}")

      # Precondition Required
      assert json_response(conn, 428)
      response = json_response(conn, 428)

      assert response["error"] == "authorization_pending"
      assert response["interval"] == 5
    end

    test "returns access_token when authorization is complete", %{
      conn: conn,
      device_code: device_code
    } do
      # Update device to be authorized
      access_token = "test_access_token_123"

      device_info = %{
        device_code: device_code,
        user_code: "TEST34",
        expires_at: DateTime.add(DateTime.utc_now(), 900, :second),
        authorized: true,
        access_token: access_token,
        error: nil
      }

      :ets.insert(:device_codes_store, {device_code, device_info})

      conn = get(conn, ~p"/api/cli/auth/poll?device_code=#{device_code}")

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert response["access_token"] == access_token
      assert response["token_type"] == "Bearer"
    end

    test "returns error for expired device code", %{conn: conn} do
      # Create expired device code
      expired_device_code = "expired_device_code_456"

      device_info = %{
        device_code: expired_device_code,
        user_code: "EXPIR2",
        # 1 minute ago
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second),
        authorized: false,
        access_token: nil,
        error: nil
      }

      :ets.insert(:device_codes_store, {expired_device_code, device_info})

      conn = get(conn, ~p"/api/cli/auth/poll?device_code=#{expired_device_code}")

      assert json_response(conn, 400)
      response = json_response(conn, 400)

      assert response["error"] == "expired_token"
    end

    test "returns error for invalid device code", %{conn: conn} do
      conn = get(conn, ~p"/api/cli/auth/poll?device_code=invalid_code")

      assert json_response(conn, 400)
      response = json_response(conn, 400)

      assert response["error"] == "invalid_request"
    end
  end

  describe "complete_device_authorization/2" do
    setup do
      CliAuthController.init_device_codes_store()

      device_code = "test_device_code_complete"

      device_info = %{
        device_code: device_code,
        user_code: "COMPL1",
        expires_at: DateTime.add(DateTime.utc_now(), 900, :second),
        authorized: false,
        access_token: nil,
        error: nil
      }

      :ets.insert(:device_codes_store, {device_code, device_info})

      %{device_code: device_code}
    end

    test "completes device authorization with access token", %{
      conn: conn,
      device_code: device_code
    } do
      access_token = "completed_access_token_123"

      # Set up session as if user is in OAuth flow
      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:pending_device_code, device_code)

      {:ok, updated_conn} = CliAuthController.complete_device_authorization(conn, access_token)

      # Check that device code is updated in ETS
      [{^device_code, device_info}] = :ets.lookup(:device_codes_store, device_code)
      assert device_info.authorized == true
      assert device_info.access_token == access_token

      # Check session is cleared
      assert is_nil(get_session(updated_conn, :pending_device_code))
    end
  end
end
