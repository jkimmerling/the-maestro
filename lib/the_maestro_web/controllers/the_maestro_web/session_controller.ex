defmodule TheMaestroWeb.TheMaestroWeb.SessionController do
  use TheMaestroWeb, :controller

  alias TheMaestro.Conversations
  alias TheMaestro.Conversations.Session

  def index(conn, _params) do
    sessions = Conversations.list_sessions()
    render(conn, :index, sessions: sessions)
  end

  def new(conn, _params) do
    changeset = Conversations.change_session(%Session{})
    render(conn, :new, changeset: changeset, auth_options: auth_options())
  end

  def create(conn, %{"session" => session_params}) do
    case Conversations.create_session(session_params) do
      {:ok, session} ->
        conn
        |> put_flash(:info, "Session created successfully.")
        |> redirect(to: ~p"/the_maestro_web/sessions/#{session}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    session = Conversations.get_session!(id)
    render(conn, :show, session: session)
  end

  def edit(conn, %{"id" => id}) do
    session = Conversations.get_session!(id)
    changeset = Conversations.change_session(session)
    render(conn, :edit, session: session, changeset: changeset, auth_options: auth_options())
  end

  def update(conn, %{"id" => id, "session" => session_params}) do
    session = Conversations.get_session!(id)

    case Conversations.update_session(session, session_params) do
      {:ok, session} ->
        conn
        |> put_flash(:info, "Session updated successfully.")
        |> redirect(to: ~p"/the_maestro_web/sessions/#{session}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, session: session, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    session = Conversations.get_session!(id)
    {:ok, _session} = Conversations.delete_session(session)

    conn
    |> put_flash(:info, "Session deleted successfully.")
    |> redirect(to: ~p"/the_maestro_web/sessions")
  end

  defp auth_options do
    TheMaestro.SavedAuthentication.list_all()
    |> Enum.map(fn sa -> {"#{sa.name} (#{sa.provider}/#{sa.auth_type})", to_string(sa.id)} end)
  end
end
