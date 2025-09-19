defmodule TheMaestro.Conversations do
  @moduledoc """
  The Conversations context.
  """

  import Ecto.Query, warn: false
  alias Ecto.Changeset
  alias Ecto.Multi

  alias TheMaestro.Auth.SavedAuthentication
  alias TheMaestro.Conversations.{ChatEntry, Session}
  alias TheMaestro.{MCP, Provider, Repo, SystemPrompts}

  @doc """
  Returns the list of sessions.

  ## Examples

      iex> list_sessions()
      [%Session{}, ...]

  """
  def list_sessions do
    Repo.all(Session)
  end

  @doc """
  Returns sessions preloaded with their agents for dashboard cards.
  """
  def list_sessions_with_auth do
    Repo.all(from s in Session, preload: [:saved_authentication, :latest_chat_entry])
  end

  @doc """
  Gets a single session.

  Raises `Ecto.NoResultsError` if the Session does not exist.

  ## Examples

      iex> get_session!(123)
      %Session{}

      iex> get_session!(456)
      ** (Ecto.NoResultsError)

  """
  def get_session!(id) do
    Session
    |> Repo.get!(id)
    |> Repo.preload([:mcp_servers, :session_mcp_servers])
  end

  @doc """
  Gets a single session preloaded with saved_authentication.
  """
  def get_session_with_auth!(id),
    do: Repo.get!(Session, id) |> Repo.preload([:saved_authentication])

  @doc """
  Creates a session.

  ## Examples

      iex> create_session(%{field: value})
      {:ok, %Session{}}

      iex> create_session(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_session(attrs) do
    {system_prompt_spec, attrs} = extract_system_prompts(attrs, :defaults)
    {mcp_ids, attrs} = extract_mcp_server_ids(attrs)

    Multi.new()
    |> Multi.insert(:session, Session.changeset(%Session{}, attrs))
    |> maybe_attach_mcp_servers(:session, mcp_ids)
    |> maybe_apply_system_prompts(:session, system_prompt_spec)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: _session, session_mcp_servers: updated_session}} ->
        {:ok, Repo.preload(updated_session, [:mcp_servers, :session_mcp_servers])}

      {:ok, %{session: session}} ->
        {:ok, Repo.preload(session, [:mcp_servers, :session_mcp_servers])}

      {:error, _step, %Changeset{} = changeset, _} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates a session.

  ## Examples

      iex> update_session(session, %{field: new_value})
      {:ok, %Session{}}

      iex> update_session(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_session(%Session{} = session, attrs) do
    {system_prompt_spec, attrs} = extract_system_prompts(attrs, :keep)
    {mcp_ids, attrs} = extract_mcp_server_ids(attrs)

    Multi.new()
    |> Multi.update(:session, Session.changeset(session, attrs))
    |> maybe_attach_mcp_servers(:session, mcp_ids)
    |> maybe_apply_system_prompts(:session, system_prompt_spec)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: _session, session_mcp_servers: reloaded}} ->
        {:ok, Repo.preload(reloaded, [:mcp_servers, :session_mcp_servers])}

      {:ok, %{session: updated_session}} ->
        {:ok, Repo.preload(updated_session, [:mcp_servers, :session_mcp_servers])}

      {:error, _step, %Changeset{} = changeset, _} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes a session.

  ## Examples

      iex> delete_session(session)
      {:ok, %Session{}}

      iex> delete_session(session)
      {:error, %Ecto.Changeset{}}

  """
  def delete_session(%Session{} = session) do
    Repo.delete(session)
  end

  @doc """
  Deletes only the session row, preserving chat history. Requires DB FK to nilify.
  """
  def delete_session_only(%Session{} = session) do
    Repo.transaction(fn ->
      from(e in ChatEntry, where: e.session_id == ^session.id)
      |> Repo.update_all(set: [session_id: nil])

      {:ok, session} =
        session
        |> Ecto.Changeset.change(latest_chat_entry_id: nil)
        |> Repo.update()

      case Repo.delete(session) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Deletes a session and its chat history.
  """
  def delete_session_and_chat(%Session{} = session) do
    Repo.transaction(fn ->
      # Delete all chat entries that reference this session
      from(e in ChatEntry, where: e.session_id == ^session.id)
      |> Repo.delete_all()

      {:ok, _} = Repo.delete(session)
      :ok
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking session changes.

  ## Examples

      iex> change_session(session)
      %Ecto.Changeset{data: %Session{}}

  """
  def change_session(%Session{} = session, attrs \\ %{}) do
    Session.changeset(session, attrs)
  end

  @doc """
  Preload MCP associations on a session struct.
  """
  def preload_session_mcp(%Session{} = session) do
    Repo.preload(session, [:mcp_servers, :session_mcp_servers])
  end

  defp extract_mcp_server_ids(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, :mcp_server_ids) ->
        {Map.get(attrs, :mcp_server_ids), Map.delete(attrs, :mcp_server_ids)}

      Map.has_key?(attrs, "mcp_server_ids") ->
        {Map.get(attrs, "mcp_server_ids"), Map.delete(attrs, "mcp_server_ids")}

      true ->
        {nil, attrs}
    end
  end

  defp maybe_attach_mcp_servers(multi, _session_key, ids) when ids in [nil, ""], do: multi

  defp maybe_attach_mcp_servers(multi, session_key, ids) do
    Multi.run(multi, :session_mcp_servers, fn _repo, changes ->
      session = Map.fetch!(changes, session_key)
      MCP.replace_session_servers(session, ids)
    end)
  end

  defp extract_system_prompts(attrs, fallback) when is_map(attrs) do
    {value, attrs} = pop_system_prompt_spec(attrs)
    map = value |> Kernel.||(%{}) |> normalize_system_prompt_map()
    if map == %{}, do: {fallback, attrs}, else: {{:explicit, map, fallback}, attrs}
  end

  defp pop_system_prompt_spec(attrs) do
    cond do
      Map.has_key?(attrs, :system_prompts) ->
        Map.pop(attrs, :system_prompts)

      Map.has_key?(attrs, "system_prompts") ->
        Map.pop(attrs, "system_prompts")

      Map.has_key?(attrs, :system_prompt_ids_by_provider) ->
        Map.pop(attrs, :system_prompt_ids_by_provider)

      Map.has_key?(attrs, "system_prompt_ids_by_provider") ->
        Map.pop(attrs, "system_prompt_ids_by_provider")

      true ->
        {nil, attrs}
    end
  end

  defp maybe_apply_system_prompts(multi, _session_key, :keep), do: multi

  defp maybe_apply_system_prompts(multi, session_key, spec) do
    Multi.run(multi, :session_prompts, fn _repo, changes ->
      session = Map.fetch!(changes, session_key)

      case apply_system_prompts(session, spec) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  # :keep is handled by maybe_apply_system_prompts/3 before calling this function

  defp apply_system_prompts(session, :defaults) do
    case session_provider(session) do
      {:ok, provider} ->
        SystemPrompts.set_session_defaults(session, provider, transaction?: false)

      {:error, _} ->
        {:ok, :no_provider}
    end
  end

  defp apply_system_prompts(session, {:explicit, map, fallback}) do
    result =
      Enum.reduce_while(map, {:ok, []}, fn {provider, specs}, {:ok, acc} ->
        case SystemPrompts.set_session_prompts(session, provider, specs, transaction?: false) do
          {:ok, list} -> {:cont, {:ok, [{provider, list} | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, _} -> maybe_apply_system_prompts_fallback(session, map, fallback)
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_apply_system_prompts_fallback(_session, _map, :keep), do: {:ok, :explicit}

  defp maybe_apply_system_prompts_fallback(session, map, :defaults) do
    case session_provider(session) do
      {:ok, provider} ->
        if Map.has_key?(map, provider) do
          {:ok, :explicit}
        else
          SystemPrompts.set_session_defaults(session, provider, transaction?: false)
        end

      {:error, _} ->
        {:ok, :explicit}
    end
  end

  defp session_provider(%Session{auth_id: nil}), do: {:error, :no_auth}

  defp session_provider(%Session{auth_id: auth_id}) do
    case Repo.get(SavedAuthentication, auth_id) do
      %SavedAuthentication{provider: provider} ->
        case to_provider_atom(provider) do
          nil -> {:error, :unknown_provider}
          provider_atom -> {:ok, provider_atom}
        end

      _ ->
        {:error, :no_auth}
    end
  end

  defp normalize_system_prompt_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {provider, specs}, acc ->
      case {to_provider_atom(provider), normalize_system_prompt_specs(specs)} do
        {nil, _} -> acc
        {_, []} -> acc
        {prov, list} -> Map.put(acc, prov, list)
      end
    end)
  end

  defp normalize_system_prompt_map(_), do: %{}

  defp normalize_system_prompt_specs(list) when is_list(list) do
    list
    |> Enum.map(&normalize_system_prompt_spec/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_system_prompt_specs(_), do: []

  defp normalize_system_prompt_spec(%{id: id} = spec),
    do:
      normalize_system_prompt_spec(%{
        "id" => id,
        "enabled" => Map.get(spec, :enabled),
        "overrides" => Map.get(spec, :overrides)
      })

  defp normalize_system_prompt_spec(%{"id" => id} = spec) when is_binary(id) do
    %{
      id: id,
      enabled: Map.get(spec, :enabled, Map.get(spec, "enabled", true)),
      overrides: ensure_map(Map.get(spec, :overrides, Map.get(spec, "overrides", %{})))
    }
  end

  defp normalize_system_prompt_spec(%{"prompt_id" => id} = spec) when is_binary(id) do
    normalize_system_prompt_spec(%{
      "id" => id,
      "enabled" => Map.get(spec, :enabled, Map.get(spec, "enabled", true)),
      "overrides" => Map.get(spec, :overrides, Map.get(spec, "overrides", %{}))
    })
  end

  defp normalize_system_prompt_spec(id) when is_binary(id) do
    %{id: id, enabled: true, overrides: %{}}
  end

  defp normalize_system_prompt_spec(_), do: nil

  defp ensure_map(nil), do: %{}
  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_), do: %{}

  defp to_provider_atom(p) when is_atom(p) do
    providers = Provider.list_providers()
    if p in providers, do: p, else: nil
  end

  defp to_provider_atom(p) when is_binary(p) do
    providers = Provider.list_providers()
    provider_strings = Enum.map(providers, &Atom.to_string/1)

    if p in provider_strings do
      String.to_existing_atom(p)
    else
      nil
    end
  end

  defp to_provider_atom(_), do: nil

  # ===== Chat History APIs =====

  @doc """
  Returns the list of chat entries for a session ordered by turn_index.
  """
  def list_chat_entries(session_id) do
    Repo.all(from e in ChatEntry, where: e.session_id == ^session_id, order_by: e.turn_index)
  end

  @doc """
  Returns the list of chat entries for a thread ordered by turn_index.
  """
  def list_chat_entries_by_thread(thread_id) when is_binary(thread_id) do
    Repo.all(from e in ChatEntry, where: e.thread_id == ^thread_id, order_by: e.turn_index)
  end

  @doc """
  Returns the latest snapshot row for the given thread if one exists.
  """
  def latest_snapshot_for_thread(thread_id) when is_binary(thread_id) do
    Repo.one(
      from e in ChatEntry,
        where: e.thread_id == ^thread_id,
        order_by: [desc: e.turn_index],
        limit: 1
    )
    |> normalize_combined_chat_entry()
  end

  @doc """
  Gets a single chat entry.
  """
  def get_chat_entry!(id), do: Repo.get!(ChatEntry, id)

  @doc """
  Creates a chat entry.
  """
  def create_chat_entry(attrs) do
    attrs = normalize_combined_chat_attr(attrs)

    %ChatEntry{}
    |> ChatEntry.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists orphan chat history entries (those not attached to a session).
  Intended for the Chat Histories admin view.
  """
  def list_orphan_chat_entries do
    Repo.all(from e in ChatEntry, where: is_nil(e.session_id), order_by: [desc: e.inserted_at])
  end

  @doc """
  Returns aggregated chat history information for sessions that have messages.
  Each entry includes the session struct, total message count, and the most
  recent chat entry metadata.
  """
  def list_chat_history_summary do
    counts_by_session =
      Repo.all(
        from e in ChatEntry,
          where: not is_nil(e.session_id),
          group_by: e.session_id,
          select: {e.session_id, count(e.id)}
      )
      |> Map.new()

    if map_size(counts_by_session) == 0,
      do: [],
      else: build_chat_history_summary(counts_by_session)
  end

  defp build_chat_history_summary(counts_by_session) when is_map(counts_by_session) do
    session_ids = Map.keys(counts_by_session)

    latest_entries =
      Repo.all(
        from e in ChatEntry,
          where: e.session_id in ^session_ids,
          order_by: [desc: e.inserted_at],
          distinct: e.session_id,
          select:
            {e.session_id,
             %{
               id: e.id,
               inserted_at: e.inserted_at,
               actor: e.actor,
               provider: e.provider,
               turn_index: e.turn_index
             }}
      )
      |> Map.new()

    sessions =
      Repo.all(from s in Session, where: s.id in ^session_ids, preload: [:saved_authentication])

    sessions
    |> Enum.sort_by(&latest_dt(&1, latest_entries), fn a, b -> DateTime.compare(a, b) != :lt end)
    |> Enum.map(fn session ->
      %{
        session: session,
        message_count: Map.fetch!(counts_by_session, session.id),
        latest_entry: Map.get(latest_entries, session.id)
      }
    end)
  end

  defp latest_dt(session, latest_entries) do
    Map.get(latest_entries, session.id, %{inserted_at: session.inserted_at}).inserted_at
  end

  @doc """
  Returns a list of orphan thread ids and labels for selection in UIs.
  """
  def list_orphan_threads do
    Repo.all(
      from e in ChatEntry,
        where: is_nil(e.session_id) and not is_nil(e.thread_id),
        group_by: [e.thread_id],
        order_by: [desc: max(e.inserted_at)],
        select: %{thread_id: e.thread_id, label: max(e.thread_label)}
    )
  end

  @doc """
  Returns a list of thread ids and labels regardless of session attachment.
  Useful for pickers that allow reattaching an existing conversation to a new session.
  """
  def list_threads do
    Repo.all(
      from e in ChatEntry,
        where: not is_nil(e.thread_id),
        group_by: [e.thread_id],
        order_by: [desc: max(e.inserted_at)],
        select: %{thread_id: e.thread_id, label: max(e.thread_label)}
    )
  end

  @doc """
  Attaches all entries in a thread to the given session.
  """
  def attach_thread_to_session(thread_id, session_id)
      when is_binary(thread_id) and is_binary(session_id) do
    {count, _} =
      Repo.update_all(
        from(e in ChatEntry, where: e.thread_id == ^thread_id),
        set: [session_id: session_id]
      )

    {:ok, count}
  end

  @doc """
  Attaches a single chat entry to a session (used if no thread_id present).
  """
  def attach_entry_to_session(entry_id, session_id)
      when is_binary(entry_id) and is_binary(session_id) do
    entry = get_chat_entry!(entry_id)
    update_chat_entry(entry, %{session_id: session_id})
  end

  @doc """
  Detaches a thread from any session (sets session_id = nil for all entries).
  """
  def detach_thread(thread_id) when is_binary(thread_id) do
    {count, _} =
      Repo.update_all(from(e in ChatEntry, where: e.thread_id == ^thread_id),
        set: [session_id: nil]
      )

    {:ok, count}
  end

  @doc """
  Returns lightweight session options for selects: [{label, id}].
  """
  def list_sessions_brief do
    Repo.all(from s in Session, order_by: [desc: s.inserted_at], preload: [:saved_authentication])
    |> Enum.map(fn s ->
      {s.name || (s.saved_authentication && s.saved_authentication.name) ||
         "sess-" <> String.slice(s.id, 0, 8), s.id}
    end)
  end

  @doc """
  Updates a chat entry.
  """
  def update_chat_entry(%ChatEntry{} = entry, attrs) do
    attrs = normalize_combined_chat_attr(attrs)

    entry
    |> ChatEntry.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a chat entry.
  """
  def delete_chat_entry(%ChatEntry{} = entry) do
    Repo.delete(entry)
  end

  # ===== Helpers for resolving workspace root by auth session =====
  @doc """
  Returns the latest Session associated with a given SavedAuthentication id.
  Useful for locating the session-scoped working_dir when only an auth session
  name is available.
  """
  @spec latest_session_for_auth_id(Ecto.UUID.t()) :: Session | nil
  def latest_session_for_auth_id(auth_id) when is_binary(auth_id) do
    Repo.one(
      from s in Session,
        where: s.auth_id == ^auth_id,
        order_by: [desc: s.inserted_at],
        limit: 1
    )
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking chat entry changes.
  """
  def change_chat_entry(%ChatEntry{} = entry, attrs \\ %{}) do
    ChatEntry.changeset(entry, attrs)
  end

  @doc """
  Returns the latest snapshot row for the session if one exists.
  """
  def latest_snapshot(session_id) do
    Repo.one(
      from e in ChatEntry,
        where: e.session_id == ^session_id,
        order_by: [desc: e.turn_index],
        limit: 1
    )
    |> normalize_combined_chat_entry()
  end

  @doc """
  Returns the most recently used thread_id for a session (if any).
  """
  def latest_thread_id(session_id) do
    Repo.one(
      from e in ChatEntry,
        where: e.session_id == ^session_id and not is_nil(e.thread_id),
        order_by: [desc: e.inserted_at],
        select: e.thread_id,
        limit: 1
    )
  end

  @doc """
  Returns the latest label for a thread (if any).
  """
  def thread_label(thread_id) when is_binary(thread_id) do
    Repo.one(
      from e in ChatEntry,
        where: e.thread_id == ^thread_id and not is_nil(e.thread_label),
        order_by: [desc: e.inserted_at],
        select: e.thread_label,
        limit: 1
    )
  end

  @doc """
  Sets the label for all entries in a thread for consistent display.
  """
  def set_thread_label(thread_id, label) when is_binary(thread_id) and is_binary(label) do
    {count, _} =
      Repo.update_all(from(e in ChatEntry, where: e.thread_id == ^thread_id),
        set: [thread_label: label]
      )

    {:ok, count}
  end

  @doc """
  Creates a new thread for a session with an initial system snapshot based on the session persona/base prompt.
  Returns {:ok, thread_id}.
  """
  def new_thread(%Session{} = session, label \\ nil) do
    thread_id = Ecto.UUID.generate()
    label = label || default_thread_label(session)

    # Build system text from session persona
    system_text = system_text_for_session(session)

    canonical = %{
      "messages" =>
        if(system_text != "",
          do: [%{"role" => "system", "content" => [%{"type" => "text", "text" => system_text}]}],
          else: []
        )
    }

    alias TheMaestro.Domain.CombinedChat
    canonical = CombinedChat.new(canonical) |> CombinedChat.to_map()

    turn_idx = next_turn_index(session.id)

    _ =
      %ChatEntry{}
      |> ChatEntry.changeset(%{
        session_id: session.id,
        thread_id: thread_id,
        thread_label: label,
        turn_index: turn_idx,
        actor: "system",
        provider: nil,
        request_headers: %{},
        response_headers: %{},
        combined_chat: canonical,
        edit_version: 0
      })
      |> Repo.insert!()

    {:ok, thread_id}
  end

  defp default_thread_label(session) do
    base = session.name || "session"
    ts = DateTime.utc_now() |> Calendar.strftime("%H:%M")
    base <> " @ " <> ts
  end

  defp system_text_for_session(session) do
    case session.persona do
      %{"persona_text" => pt} when is_binary(pt) -> pt
      %{persona_text: pt} when is_binary(pt) -> pt
      _ -> ""
    end
  end

  @doc """
  Deletes all entries for a given thread.
  """
  def delete_thread_entries(thread_id) when is_binary(thread_id) do
    {count, _} = Repo.delete_all(from e in ChatEntry, where: e.thread_id == ^thread_id)
    {:ok, count}
  end

  @doc """
  Computes the next turn_index for a session (0-based).
  """
  def next_turn_index(session_id) do
    max =
      Repo.one(
        from e in ChatEntry,
          where: e.session_id == ^session_id,
          select: max(e.turn_index)
      ) || -1

    max + 1
  end

  # ===== Thread-first APIs =====

  @doc """
  Creates an initial thread for a session with optional label.
  """
  def ensure_thread_for_session(session_id, _label \\ nil) when is_binary(session_id) do
    # If any entry already has a thread_id, reuse its thread_id
    case Repo.one(
           from e in ChatEntry,
             where: e.session_id == ^session_id and not is_nil(e.thread_id),
             select: e.thread_id,
             limit: 1
         ) do
      nil ->
        tid = Ecto.UUID.generate()
        {:ok, tid}

      tid ->
        {:ok, tid}
    end
  end

  @doc """
  Forks a thread at a given entry, setting lineage fields on subsequent entries as needed.
  Returns {:ok, new_thread_id}.
  """
  def fork_thread(thread_id, fork_from_entry_id, _label \\ nil)
      when is_binary(thread_id) and is_binary(fork_from_entry_id) do
    new_id = Ecto.UUID.generate()
    # We only record lineage at the fork point for traceability
    from(e in ChatEntry, where: e.id == ^fork_from_entry_id)
    |> Repo.update_all(set: [fork_from_entry_id: fork_from_entry_id])

    {:ok, new_id}
  end

  @doc """
  Computes the next turn_index for a thread (0-based).
  """
  def next_turn_index_for_thread(thread_id) when is_binary(thread_id) do
    max =
      Repo.one(
        from e in ChatEntry,
          where: e.thread_id == ^thread_id,
          select: max(e.turn_index)
      ) || -1

    max + 1
  end

  @doc """
  Seeds an initial system message snapshot if none exists for the session.
  Returns {:ok, {session, snapshot}}.
  """
  def ensure_seeded_snapshot(%Session{} = session) do
    case latest_snapshot(session.id) do
      %ChatEntry{} = entry ->
        {:ok, {session, entry}}

      nil ->
        # Build a minimal canonical chat with a system message from session persona
        system_text =
          case session.persona do
            %{"persona_text" => pt} when is_binary(pt) -> pt
            %{persona_text: pt} when is_binary(pt) -> pt
            _ -> ""
          end

        canonical = %{
          "messages" =>
            if(system_text != "",
              do: [
                %{"role" => "system", "content" => [%{"type" => "text", "text" => system_text}]}
              ],
              else: []
            )
        }

        alias TheMaestro.Domain.CombinedChat
        canonical = CombinedChat.new(canonical) |> CombinedChat.to_map()

        idx = 0

        {:ok, entry} =
          create_chat_entry(%{
            session_id: session.id,
            turn_index: idx,
            actor: "system",
            provider: nil,
            request_headers: %{},
            response_headers: %{},
            combined_chat: canonical,
            edit_version: 0
          })

        {:ok, {session, entry}}
    end
  end

  # ===== Internal normalization helpers =====

  defp normalize_combined_chat_attr(%{"combined_chat" => cc} = attrs) when is_map(cc) do
    alias TheMaestro.Domain.CombinedChat
    Map.put(attrs, "combined_chat", CombinedChat.new(cc) |> CombinedChat.to_map())
  end

  defp normalize_combined_chat_attr(%{combined_chat: cc} = attrs) when is_map(cc) do
    alias TheMaestro.Domain.CombinedChat
    Map.put(attrs, :combined_chat, CombinedChat.new(cc) |> CombinedChat.to_map())
  end

  defp normalize_combined_chat_attr(attrs), do: attrs

  defp normalize_combined_chat_entry(nil), do: nil

  defp normalize_combined_chat_entry(%ChatEntry{} = e) do
    cc = e.combined_chat || %{}

    alias TheMaestro.Domain.CombinedChat
    norm = CombinedChat.from_map(cc) |> CombinedChat.to_map()

    %ChatEntry{e | combined_chat: norm}
  end
end
