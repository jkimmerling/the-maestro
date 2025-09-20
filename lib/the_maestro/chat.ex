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

  alias Phoenix.Ecto.SQL.Sandbox, as: PhoenixSandbox
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
  @doc """
  High-level start_turn: persists the user message, resolves provider/auth/model,
  translates to provider messages, and starts the orchestrator stream.

  Returns {:ok, %{stream_id, provider, model, auth_type, auth_name, thread_id, pending_canonical}}.
  """
  @spec start_turn(session_id, thread_id | nil, String.t(), keyword()) ::
          {:ok,
           %{
             stream_id: stream_id,
             provider: atom(),
             model: String.t(),
             auth_type: atom(),
             auth_name: String.t(),
             thread_id: String.t(),
             pending_canonical: map()
           }}
          | {:error, term()}
  def start_turn(session_id, thread_id, user_text, opts \\ [])
      when is_binary(session_id) and is_binary(user_text) do
    session = Conversations.get_session_with_auth!(session_id)
    {auth_type, auth_name} = auth_meta_from_session(session)
    provider = provider_from_session(session)

    tid = resolve_thread_id(session_id, thread_id)
    canonical = get_canonical_chat(tid)

    case append_user_message(session_id, tid, canonical, user_text) do
      {:error, :duplicate_turn} ->
        {:error, :duplicate_turn}

      {:ok, updated} ->
        build_turn_response(
          session,
          session_id,
          tid,
          updated,
          provider,
          auth_type,
          auth_name,
          opts
        )
    end
  end

  defp resolve_thread_id(session_id, thread_id) do
    case thread_id do
      t when is_binary(t) and t != "" ->
        t

      _ ->
        {:ok, t} = ensure_thread(session_id)
        t
    end
  end

  defp get_canonical_chat(tid) do
    case Conversations.latest_snapshot_for_thread(tid) do
      %{combined_chat: canon} -> canon
      _ -> %{"messages" => []}
    end
  end

  defp append_user_message(session_id, tid, canonical, user_text) do
    case needs_append_user?(canonical, user_text) do
      true ->
        updated =
          put_in(canonical, ["messages"], (canonical["messages"] || []) ++ [user_msg(user_text)])

        {:ok, _} =
          Conversations.create_chat_entry(%{
            session_id: session_id,
            turn_index: Conversations.next_turn_index(session_id),
            actor: "user",
            provider: nil,
            request_headers: %{},
            response_headers: %{},
            combined_chat: updated,
            thread_id: tid,
            edit_version: 0
          })

        {:ok, updated}

      false ->
        {:error, :duplicate_turn}
    end
  end

  defp build_turn_response(
         session,
         session_id,
         tid,
         updated,
         provider,
         auth_type,
         auth_name,
         opts
       ) do
    model = pick_model_for_session(session, provider)
    t0_ms = Keyword.get(opts, :t0_ms, System.monotonic_time(:millisecond))

    opts =
      opts
      |> Keyword.put_new(:t0_ms, t0_ms)
      |> put_sandbox_owner()

    if Keyword.get(opts, :start_stream?, true) do
      start_stream_response(session_id, tid, updated, provider, auth_type, auth_name, model, opts)
    else
      dry_run_response(tid, updated, provider, auth_type, auth_name, model)
    end
  end

  defp start_stream_response(
         session_id,
         tid,
         updated,
         provider,
         auth_type,
         auth_name,
         model,
         opts
       ) do
    {:ok, provider_msgs} = Conversations.Translator.to_provider(updated, provider)

    with {:ok, stream_id} <-
           SessionsManager.start_stream(
             session_id,
             provider,
             auth_name,
             provider_msgs,
             model,
             opts
           ) do
      {:ok,
       %{
         stream_id: stream_id,
         provider: provider,
         model: model,
         auth_type: auth_type,
         auth_name: auth_name,
         thread_id: tid,
         pending_canonical: updated
       }}
    end
  end

  defp dry_run_response(tid, updated, provider, auth_type, auth_name, model) do
    {:ok,
     %{
       stream_id: "dry-" <> Ecto.UUID.generate(),
       provider: provider,
       model: model,
       auth_type: auth_type,
       auth_name: auth_name,
       thread_id: tid,
       pending_canonical: updated
     }}
  end

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
    opts = put_sandbox_owner(opts)

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

  defp put_sandbox_owner(opts) do
    if Keyword.has_key?(opts, :sandbox_owner) do
      opts
    else
      case sandbox_owner_from_process() do
        nil -> opts
        owner -> Keyword.put(opts, :sandbox_owner, owner)
      end
    end
  end

  defp sandbox_owner_from_process do
    [
      Process.get(:phoenix_ecto_sandbox_owner),
      Process.get(:"$ecto_sandbox_owner"),
      Process.get({TheMaestro.Repo, :sandbox_owner}),
      extract_owner_from_meta(Process.get(:phoenix_ecto_sandbox))
    ]
    |> Enum.find(&is_pid/1)
  end

  defp extract_owner_from_meta(%{owner: owner}) when is_pid(owner), do: owner

  defp extract_owner_from_meta(metadata) when is_binary(metadata) do
    if Code.ensure_loaded?(PhoenixSandbox) do
      case PhoenixSandbox.decode_metadata(metadata) do
        %{owner: owner} when is_pid(owner) -> owner
        _ -> nil
      end
    else
      nil
    end
  end

  defp extract_owner_from_meta(_), do: nil

  # Public wrappers for LV/REST parity
  @doc "Return provider atom for a session's saved authentication."
  def provider_for_session(session), do: provider_from_session(session)

  @doc "Return {auth_type, auth_name} for a session's saved authentication."
  def auth_meta_for_session(session), do: auth_meta_from_session(session)

  @doc "Resolve a valid model for the session+provider (respects session.model_id)."
  def resolve_model_for_session(session, provider), do: pick_model_for_session(session, provider)

  defp user_msg(text), do: %{"role" => "user", "content" => [%{"type" => "text", "text" => text}]}

  defp needs_append_user?(%{"messages" => msgs}, text) when is_list(msgs) do
    case List.last(msgs) do
      %{"role" => "user", "content" => [%{"type" => "text", "text" => last_txt} | _]} ->
        String.trim(to_string(last_txt)) != String.trim(to_string(text))

      _ ->
        true
    end
  end

  defp needs_append_user?(_, _), do: true

  defp provider_from_session(session) do
    saved = session.saved_authentication

    cond do
      match?(%Ecto.Association.NotLoaded{}, saved) and session.auth_id ->
        sa = Auth.get_saved_authentication!(session.auth_id)
        to_provider_atom(sa.provider)

      is_map(saved) ->
        to_provider_atom(saved.provider)

      true ->
        :openai
    end
  end

  defp auth_meta_from_session(session) do
    saved = session.saved_authentication

    cond do
      match?(%Ecto.Association.NotLoaded{}, saved) and session.auth_id ->
        sa = Auth.get_saved_authentication!(session.auth_id)
        {sa.auth_type, sa.name}

      is_map(saved) ->
        {saved.auth_type, saved.name}

      true ->
        {:oauth, "default"}
    end
  end

  defp default_model_for_session(session, :openai) do
    {auth_type, _} = auth_meta_from_session(session)

    case auth_type do
      :oauth -> "gpt-5"
      _ -> "gpt-4o"
    end
  end

  defp default_model_for_session(_session, :anthropic), do: "claude-3-5-sonnet"

  defp default_model_for_session(session, :gemini) do
    {auth_type, _} = auth_meta_from_session(session)

    case auth_type do
      :oauth -> "gemini-2.5-pro"
      _ -> "gemini-1.5-pro-latest"
    end
  end

  defp pick_model_for_session(session, provider) do
    chosen = session.model_id

    if is_binary(chosen) and chosen != "" do
      chosen
    else
      choose_model_from_provider(session, provider)
    end
  end

  defp choose_model_from_provider(session, provider) do
    default = default_model_for_session(session, provider)
    {auth_type, session_name} = auth_meta_from_session(session)

    case Provider.list_models(provider, auth_type, session_name) do
      {:ok, models} when is_list(models) and models != [] ->
        ids = Enum.map(models, & &1.id)
        if default in ids, do: default, else: hd(ids)

      _ ->
        default
    end
  end
end
