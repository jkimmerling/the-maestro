defmodule TheMaestro.Conversations.ChatEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chat_history" do
    field :turn_index, :integer
    field :actor, :string
    field :provider, :string
    field :request_headers, :map, default: %{}
    field :response_headers, :map, default: %{}
    field :combined_chat, :map, default: %{}
    field :edit_version, :integer, default: 0

    field :session_id, :binary_id
    # New session-centric threading fields (Phase 1)
    field :thread_id, :binary_id
    field :parent_thread_id, :binary_id
    field :fork_from_entry_id, :binary_id
    field :thread_label, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :session_id,
      :turn_index,
      :actor,
      :provider,
      :request_headers,
      :response_headers,
      :combined_chat,
      :edit_version
    ])
    # During cutover, require session_id while thread_id is being backfilled.
    # In Phase 2 we will flip to require thread_id and make session_id optional.
    |> validate_required([:session_id, :turn_index, :actor, :combined_chat])
    |> validate_inclusion(:actor, ["user", "assistant", "tool", "system"])
    |> foreign_key_constraint(:session_id)
    |> unique_constraint([:session_id, :turn_index])
    # New unique constraint (soft during cutover as thread_id may be nil)
    |> unique_constraint([:thread_id, :turn_index])
  end
end

defmodule TheMaestro.Conversations do
  @moduledoc """
  The Conversations context.
  """

  import Ecto.Query, warn: false
  alias TheMaestro.Repo

  alias TheMaestro.Conversations.ChatEntry
  alias TheMaestro.Conversations.Session

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
  def get_session!(id), do: Repo.get!(Session, id)

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
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
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
    session
    |> Session.changeset(attrs)
    |> Repo.update()
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
  Returns an `%Ecto.Changeset{}` for tracking session changes.

  ## Examples

      iex> change_session(session)
      %Ecto.Changeset{data: %Session{}}

  """
  def change_session(%Session{} = session, attrs \\ %{}) do
    Session.changeset(session, attrs)
  end

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
  end

  @doc """
  Gets a single chat entry.
  """
  def get_chat_entry!(id), do: Repo.get!(ChatEntry, id)

  @doc """
  Creates a chat entry.
  """
  def create_chat_entry(attrs) do
    %ChatEntry{}
    |> ChatEntry.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a chat entry.
  """
  def update_chat_entry(%ChatEntry{} = entry, attrs) do
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
end
