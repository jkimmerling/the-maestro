defmodule TheMaestroWeb.Api.TurnsController do
  use TheMaestroWeb, :controller
  alias TheMaestro.Chat
  alias TheMaestro.Conversations

  def create(conn, %{"session_id" => session_id} = params) do
    message = (params["message"] || "") |> to_string() |> String.trim()
    thread_id = params["thread_id"]

    if message == "" do
      conn |> put_status(:unprocessable_entity) |> json(%{error: "message is required"})
    else
      _ = Conversations.get_session!(session_id)

      case Chat.start_turn(session_id, thread_id, message) do
        {:ok, %{stream_id: sid, provider: provider, model: model, thread_id: tid}} ->
          conn
          |> put_status(:accepted)
          |> json(%{
            stream_id: sid,
            provider: Atom.to_string(provider),
            model: model,
            thread_id: tid
          })

        {:error, reason} ->
          conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
      end
    end
  end
end
