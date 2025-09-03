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
    render(conn, :new, changeset: changeset, agent_options: agent_options())
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
    render(conn, :edit, session: session, changeset: changeset, agent_options: agent_options())
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

  defp agent_options do
    TheMaestro.Agents.list_agents_with_auth()
    |> Enum.map(fn a -> {a.name, to_string(a.id)} end)
  end
end
