defmodule TheMaestroWeb.Api.ToolResultsController do
  use TheMaestroWeb, :controller
  alias TheMaestro.Sessions.Manager

  def create(conn, %{"session_id" => session_id, "stream_id" => stream_id} = params) do
    call_id = params["call_id"]
    name = params["name"]
    output = params["output"]

    if is_binary(call_id) and is_binary(name) do
      :ok =
        GenServer.cast(
          Manager,
          {:tool_result_posted, session_id, stream_id, %{id: call_id, name: name, output: output}}
        )

      send_resp(conn, 202, "")
    else
      conn |> put_status(:unprocessable_entity) |> json(%{error: "call_id and name required"})
    end
  end
end
