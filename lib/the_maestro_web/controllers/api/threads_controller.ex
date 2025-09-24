defmodule TheMaestroWeb.Api.ThreadsController do
  use TheMaestroWeb, :controller
  alias TheMaestro.Conversations

  def clear(conn, %{"thread_id" => thread_id}) do
    {:ok, _count} = Conversations.delete_thread_entries(thread_id)
    json(conn, %{ok: true})
  end
end
