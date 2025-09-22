defmodule TheMaestro.Events do
  @moduledoc """
  Lightweight PubSub helpers for internal UI updates.

  Topics:
    plans:<session_id>
      event: "plans:updated" payload: %{session_id, thread_id, items}
    images:<session_id>
      event: "images:attached" payload: %{session_id, thread_id, path}
  """

  alias TheMaestroWeb.Endpoint

  @spec topic(atom(), String.t()) :: String.t()
  def topic(:plans, session_id), do: "plans:" <> session_id
  def topic(:images, session_id), do: "images:" <> session_id

  @spec broadcast_plan_update(String.t(), String.t() | nil, list()) :: :ok
  def broadcast_plan_update(session_id, thread_id, items) do
    Endpoint.broadcast(topic(:plans, session_id), "plans:updated", %{
      session_id: session_id,
      thread_id: thread_id,
      items: items
    })

    :ok
  end

  @spec broadcast_image_attached(String.t(), String.t() | nil, String.t()) :: :ok
  def broadcast_image_attached(session_id, thread_id, path) do
    Endpoint.broadcast(topic(:images, session_id), "images:attached", %{
      session_id: session_id,
      thread_id: thread_id,
      path: path
    })

    :ok
  end
end
