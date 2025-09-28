defmodule TheMaestroWeb.Api.SessionsController do
  use TheMaestroWeb, :controller
  alias TheMaestro.Conversations

  def index(conn, params) do
    case Map.get(params, "tool_runtime") do
      runtime when runtime in ["local", "remote"] ->
        list =
          Conversations.list_sessions_by_tool_runtime(runtime)
          |> Enum.map(fn s -> %{id: to_string(s.id), name: s.name, working_dir: s.working_dir} end)

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
end
