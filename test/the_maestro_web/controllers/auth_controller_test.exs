defmodule TheMaestroWeb.AuthControllerTest do
  use TheMaestroWeb.ConnCase

  describe "OAuth callback with success" do
    test "stores user info in session and redirects to agent", %{conn: conn} do
      auth = %Ueberauth.Auth{
        uid: "123456789",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Test User",
          image: "https://example.com/avatar.jpg"
        }
      }

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/google/callback")

      assert redirected_to(conn) == ~p"/agent"
      assert get_flash(conn, :info) == "Successfully authenticated!"

      # Check that user info is stored in session
      user_info = get_session(conn, :current_user)
      assert user_info["id"] == "123456789"
      assert user_info["email"] == "test@example.com"
      assert user_info["name"] == "Test User"
      assert user_info["avatar"] == "https://example.com/avatar.jpg"
    end
  end

  describe "OAuth callback with failure" do
    test "redirects to home with error message", %{conn: conn} do
      failure = %Ueberauth.Failure{
        errors: [%Ueberauth.Failure.Error{message: "OAuth error"}]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_failure, failure)
        |> get(~p"/auth/google/callback")

      assert redirected_to(conn) == ~p"/"
      assert get_flash(conn, :error) == "Failed to authenticate. Please try again."
    end
  end

  describe "logout" do
    test "clears session and redirects to home", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, %{"id" => "123", "email" => "test@example.com"})
        |> get(~p"/auth/logout")

      assert redirected_to(conn) == ~p"/"
      assert get_flash(conn, :info) == "You have been logged out."
      assert get_session(conn, :current_user) == nil
    end
  end
end
