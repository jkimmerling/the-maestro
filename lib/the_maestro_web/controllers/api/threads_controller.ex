defmodule TheMaestroWeb.Api.ThreadsController do
  use TheMaestroWeb, :controller
  alias TheMaestro.Chat
  alias TheMaestro.Conversations

  def index(conn, %{"session_id" => session_id}) do
    threads = Conversations.list_threads_for_session(session_id)

    json(conn, %{
      threads:
        Enum.map(threads, fn t ->
          %{id: t.thread_id, label: t.label, updated_at: t.updated_at}
        end)
    })
  end

  def create(conn, %{"session_id" => session_id} = params) do
    label = params["label"]
    {:ok, tid} = Chat.new_thread(session_id, label)
    json(conn, %{id: tid, label: label})
  end

  def update(conn, %{"thread_id" => thread_id, "label" => label}) do
    {:ok, _} = Chat.rename_thread(thread_id, label)
    json(conn, %{ok: true})
  end

  def clear(conn, %{"thread_id" => thread_id}) do
    {:ok, _count} = Conversations.delete_thread_entries(thread_id)
    json(conn, %{ok: true})
  end
end
