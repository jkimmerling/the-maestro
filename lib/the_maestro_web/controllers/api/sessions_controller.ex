defmodule TheMaestroWeb.Api.SessionsController do
  use TheMaestroWeb, :controller
  alias TheMaestro.Conversations

  def index(conn, params) do
    case Map.get(params, "tool_runtime") do
      runtime when runtime in ["local", "remote"] ->
        list =
          Conversations.list_sessions_by_tool_runtime(runtime)
          |> Enum.sort_by(
            fn s ->
              s.last_used_at || s.updated_at || s.inserted_at || ~U[1970-01-01 00:00:00Z]
            end,
            {:desc, DateTime}
          )
          |> Enum.map(fn s ->
            %{
              id: to_string(s.id),
              name: s.name,
              working_dir: s.working_dir,
              last_used_at: s.last_used_at,
              updated_at: s.updated_at,
              inserted_at: s.inserted_at
            }
          end)

        json(conn, %{sessions: list})

      _ ->
        conn |> put_status(:bad_request) |> json(%{error: "tool_runtime parameter required"})
    end
  end

  def create(conn, params) do
    attrs = %{
      "auth_id" => params["auth_id"],
      "model_id" => params["model"],
      "working_dir" => params["working_dir"],
      "tool_runtime" => params["tool_runtime"] || "remote",
      "persona" => params["persona"] || %{},
      "memory" => params["memory"] || %{},
      "tools" => params["tools"] || %{}
    }

    case Conversations.create_session(attrs) do
      {:ok, session} ->
        json(conn, %{session_id: to_string(session.id)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(changeset.errors)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    session = Conversations.get_session!(id)

    attrs = %{}
    attrs = if params["auth_id"], do: Map.put(attrs, "auth_id", params["auth_id"]), else: attrs
    attrs = if params["model_id"], do: Map.put(attrs, "model_id", params["model_id"]), else: attrs

    case Conversations.update_session(session, attrs) do
      {:ok, updated_session} ->
        json(conn, %{
          session_id: to_string(updated_session.id),
          auth_id: updated_session.auth_id,
          model_id: updated_session.model_id
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(changeset.errors)})
    end
  end

  def delete(conn, %{"id" => id}) do
    session = Conversations.get_session!(id)

    case Conversations.delete_session(session) do
      {:ok, _session} ->
        conn
        |> put_status(:no_content)
        |> json(%{})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(changeset.errors)})
    end
  end
end
