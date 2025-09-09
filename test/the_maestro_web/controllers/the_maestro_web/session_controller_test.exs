defmodule TheMaestroWeb.TheMaestroWeb.SessionControllerTest do
  use TheMaestroWeb.ConnCase

  import TheMaestro.ConversationsFixtures

  @create_attrs_base %{name: "some name", last_used_at: ~U[2025-09-01 15:30:00Z]}
  @update_attrs %{name: "some updated name", last_used_at: ~U[2025-09-02 15:30:00Z]}
  @invalid_attrs %{name: nil, last_used_at: nil}

  describe "index" do
    test "lists all sessions", %{conn: conn} do
      conn = get(conn, ~p"/the_maestro_web/sessions")
      assert html_response(conn, 200) =~ "Listing Sessions"
    end
  end

  describe "new session" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/the_maestro_web/sessions/new")
      assert html_response(conn, 200) =~ "New Session"
    end
  end

  describe "create session" do
    test "redirects to show when data is valid", %{conn: conn} do
      short = String.slice(Ecto.UUID.generate(), 0, 6)

      {:ok, sa} =
        %TheMaestro.SavedAuthentication{}
        |> TheMaestro.SavedAuthentication.changeset(%{
          provider: :openai,
          auth_type: :api_key,
          name: "test_openai_api_key_ctrl-" <> short,
          credentials: %{"api_key" => "sk-test"}
        })
        |> TheMaestro.Repo.insert()

      conn =
        post(conn, ~p"/the_maestro_web/sessions",
          session: Map.put(@create_attrs_base, :auth_id, sa.id)
        )

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/the_maestro_web/sessions/#{id}"

      conn = get(conn, ~p"/the_maestro_web/sessions/#{id}")
      assert html_response(conn, 200) =~ "Session #{id}"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/the_maestro_web/sessions", session: @invalid_attrs)
      assert html_response(conn, 200) =~ "New Session"
    end
  end

  describe "edit session" do
    setup [:create_session]

    test "renders form for editing chosen session", %{conn: conn, session: session} do
      conn = get(conn, ~p"/the_maestro_web/sessions/#{session}/edit")
      assert html_response(conn, 200) =~ "Edit Session"
    end
  end

  describe "update session" do
    setup [:create_session]

    test "redirects when data is valid", %{conn: conn, session: session} do
      conn = put(conn, ~p"/the_maestro_web/sessions/#{session}", session: @update_attrs)
      assert redirected_to(conn) == ~p"/the_maestro_web/sessions/#{session}"

      conn = get(conn, ~p"/the_maestro_web/sessions/#{session}")
      assert html_response(conn, 200) =~ "some updated name"
    end

    test "handles update with optional fields nil by redirecting", %{conn: conn, session: session} do
      conn = put(conn, ~p"/the_maestro_web/sessions/#{session}", session: @invalid_attrs)
      assert redirected_to(conn) == ~p"/the_maestro_web/sessions/#{session}"
    end
  end

  describe "delete session" do
    setup [:create_session]

    test "deletes chosen session", %{conn: conn, session: session} do
      conn = delete(conn, ~p"/the_maestro_web/sessions/#{session}")
      assert redirected_to(conn) == ~p"/the_maestro_web/sessions"

      assert_error_sent 404, fn ->
        get(conn, ~p"/the_maestro_web/sessions/#{session}")
      end
    end
  end

  defp create_session(_) do
    session = session_fixture()

    %{session: session}
  end
end
