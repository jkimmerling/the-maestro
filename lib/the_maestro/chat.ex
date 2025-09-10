defmodule TheMaestro.Chat do
  @moduledoc """
  Context facade for chat/session operations.

  This module is the single internal API that all user interfaces (LiveView,
  AgentLoop, future REST/CLI) should call. It centralizes business logic and
  routes work to persistence (`TheMaestro.Conversations`) and orchestration
  (`TheMaestro.Sessions.Manager`).

  Initial surface is intentionally thin and delegates to existing modules.
  Subsequent phases will move streaming finalization and provider/model
  resolution fully behind this API (see docs/overhauls/2025-09-10-*.md).
  """

  alias Phoenix.PubSub
  alias TheMaestro.{Auth, Conversations, Provider}
  alias TheMaestro.Sessions.Manager, as: SessionsManager

  @type session_id :: String.t()
  @type thread_id :: String.t()
  @type stream_id :: String.t()

  # ----- Session & snapshots -----

  @doc "Get a session preloaded with auth (for UIs)."
  @spec get_session(session_id) :: struct()
  def get_session(id), do: Conversations.get_session_with_auth!(id)

  @doc "Latest snapshot for a session."
  def latest_snapshot(session_id), do: Conversations.latest_snapshot(session_id)

  @doc "Latest snapshot for a thread."
  def latest_snapshot_for_thread(thread_id),
    do: Conversations.latest_snapshot_for_thread(thread_id)

  # ----- Threads -----

  @doc "Ensure a thread exists for the given session; returns {:ok, thread_id}."
  @spec ensure_thread(session_id) :: {:ok, thread_id}
  def ensure_thread(session_id), do: Conversations.ensure_thread_for_session(session_id)

  @doc "Create a new thread for a session with optional label."
  @spec new_thread(session_id, String.t() | nil) :: {:ok, thread_id}
  def new_thread(session_id, label \\ nil) when is_binary(session_id) do
    session = Conversations.get_session!(session_id)
    Conversations.new_thread(session, label)
  end

  @doc "Rename a thread label."
  def rename_thread(thread_id, label), do: Conversations.set_thread_label(thread_id, label)

  @doc "Delete all entries for a thread."
  def clear_thread(thread_id), do: Conversations.delete_thread_entries(thread_id)

  # ----- Models -----

  @doc "List models for a saved authentication id. Returns {:ok, [model_id]}."
  @spec list_models(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_models(auth_id) when is_binary(auth_id) do
    sa = Auth.get_saved_authentication!(auth_id)
    provider = to_provider_atom(sa.provider)

    with {:ok, models} <- Provider.list_models(provider, sa.auth_type, sa.name) do
      {:ok, Enum.map(models, & &1.id)}
    end
  end

  # ----- Streaming orchestration (thin) -----

  @doc "Subscribe the current process to session PubSub topic."
  @spec subscribe(session_id) :: :ok | {:error, term()}
  def subscribe(session_id) when is_binary(session_id) do
    SessionsManager.subscribe(session_id)
  end

  @doc "Unsubscribe the current process from a session PubSub topic."
  @spec unsubscribe(session_id) :: :ok
  def unsubscribe(session_id) when is_binary(session_id) do
    PubSub.unsubscribe(TheMaestro.PubSub, topic(session_id))
  end

  @doc "Cancel any in-flight stream for a session."
  @spec cancel_turn(session_id) :: :ok
  def cancel_turn(session_id) when is_binary(session_id) do
    SessionsManager.cancel(session_id)
  end

  @doc """
  Start a provider streaming turn for a session with already-translated
  provider messages. This is a thin wrapper to the Manager for now.

  Returns {:ok, stream_id}.
  """
  @spec start_stream(session_id, atom, String.t(), list(), String.t(), keyword()) ::
          {:ok, stream_id} | {:error, term()}
  def start_stream(session_id, provider, session_name, provider_messages, model, opts \\ [])
      when is_binary(session_id) and is_atom(provider) and is_binary(model) do
    SessionsManager.start_stream(
      session_id,
      provider,
      session_name,
      provider_messages,
      model,
      opts
    )
  end

  # ----- Helpers -----

  defp topic(session_id), do: "session:" <> session_id

  defp to_provider_atom(p) when is_atom(p), do: p

  defp to_provider_atom(p) when is_binary(p) do
    allowed = TheMaestro.Provider.list_providers()
    allowed_strings = Enum.map(allowed, &Atom.to_string/1)
    if p in allowed_strings, do: String.to_existing_atom(p), else: :openai
  end
end
