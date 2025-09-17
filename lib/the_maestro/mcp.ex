defmodule TheMaestro.MCP do
  @moduledoc """
  Domain context exposing MCP server persistence and attachment APIs.
  """

  import Ecto.Query, warn: false
  alias Ecto.Changeset
  alias Ecto.Multi

  alias TheMaestro.Conversations.Session
  alias TheMaestro.MCP.{Servers, SessionServer}
  alias TheMaestro.Repo

  @doc """
  List MCP servers ordered by display name (case-insensitive). Disabled servers are
  excluded by default; pass `include_disabled?: true` to include them.
  """
  def list_servers(opts \\ []) do
    include_disabled? = Keyword.get(opts, :include_disabled?, false)

    base_query =
      from s in Servers,
        order_by: [asc: fragment("lower(?)", s.display_name), asc: fragment("lower(?)", s.name)]

    query =
      if include_disabled? do
        base_query
      else
        from s in base_query, where: s.is_enabled == true
      end

    Repo.all(query)
  end

  @doc """
  Return server options suitable for select inputs. Includes disabled servers by
  default so forms can display previously attached entries.
  """
  def server_options(opts \\ []) do
    include_disabled? = Keyword.get(opts, :include_disabled?, true)

    list_servers(include_disabled?: include_disabled?)
    |> Enum.map(fn server ->
      status_suffix = if server.is_enabled, do: "", else: " (disabled)"

      label =
        [server.display_name, transport_label(server)]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" · ")
        |> Kernel.<>(status_suffix)

      {label, server.id}
    end)
  end

  @doc """
  List servers with aggregated attachment counts.
  Returns each server struct with `:session_count` virtual field populated.
  """
  def list_servers_with_stats do
    Repo.all(
      from s in Servers,
        left_join: sms in SessionServer,
        on: sms.mcp_server_id == s.id,
        group_by: s.id,
        order_by: [asc: fragment("lower(?)", s.display_name), asc: fragment("lower(?)", s.name)],
        select_merge: %{session_count: count(sms.id)}
    )
  end

  @doc """
  Fetch a server by id. Pass `preload: [...]` to eager load associations.
  """
  def get_server!(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    Servers
    |> Repo.get!(id)
    |> Repo.preload(preloads)
  end

  @doc """
  Convenience fetch by canonical name.
  """
  def get_server_by_name(name) when is_binary(name) do
    canonical = Servers.normalize_name(name)

    Repo.one(from s in Servers, where: s.name == ^canonical)
  end

  @doc """
  Create an MCP server entry.
  """
  def create_server(attrs) when is_map(attrs) do
    %Servers{}
    |> Servers.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update an MCP server entry.
  """
  def update_server(%Servers{} = server, attrs) do
    server
    |> Servers.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete an MCP server (dependent join rows cascade from FK).
  """
  def delete_server(%Servers{} = server) do
    Repo.delete(server)
  end

  @doc """
  Delete servers by canonical name. Returns `{:ok, count}` with the number of
  deleted rows.
  """
  def delete_servers_by_names(names) when is_list(names) do
    canonical = Enum.map(names, &Servers.normalize_name/1)

    {count, _} = Repo.delete_all(from s in Servers, where: s.name in ^canonical)
    {:ok, count}
  end

  @doc """
  Build a changeset for an MCP server without persisting.
  """
  def change_server(%Servers{} = server, attrs \\ %{}) do
    Servers.changeset(server, attrs)
  end

  @doc """
  Ensure the provided list of server attribute maps exist (bulk upsert). Each entry
  must include a `name`. Returns `{:ok, servers}` with the upserted structs in the
  original order or `{:error, failed_changeset}`.
  """
  def ensure_servers_exist(entries) when is_list(entries) do
    Multi.new()
    |> Multi.run(:validated, fn _repo, _ -> validate_entries(entries) end)
    |> Multi.run(:upserts, fn _repo, %{validated: validated} -> upsert_servers(validated) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{upserts: servers}} -> {:ok, servers}
      {:error, _step, %Changeset{} = changeset, _} -> {:error, changeset}
      other -> other
    end
  end

  @doc """
  Replace the MCP server assignments for a session (accepts session struct or id)
  with the provided list of server ids. Returns `{:ok, session}` reloaded with the
  `:mcp_servers` association.
  """
  def replace_session_servers(%Session{id: session_id} = session, server_ids) do
    do_replace_session_servers(session, session_id, server_ids)
  end

  def replace_session_servers(session_id, server_ids) when is_binary(session_id) do
    session = Repo.get!(Session, session_id)
    do_replace_session_servers(session, session_id, server_ids)
  end

  def replace_session_servers(_session, nil), do: {:error, :invalid_server_ids}

  defp do_replace_session_servers(%Session{} = _session, session_id, server_ids) do
    with {:ok, sanitized} <- sanitize_server_ids(server_ids || []),
         {:ok, session} <- replace_session_servers_transaction(session_id, sanitized) do
      {:ok, session}
    end
  end

  defp replace_session_servers_transaction(session_id, server_ids) do
    Repo.transaction(fn ->
      case ensure_all_servers_exist(server_ids) do
        :ok ->
          delete_obsolete_session_links(session_id, server_ids)
          insert_missing_session_links(session_id, server_ids)

          Session
          |> Repo.get!(session_id)
          |> Repo.preload([:mcp_servers, :session_mcp_servers])

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> normalize_transaction_result()
  end

  defp normalize_transaction_result({:ok, value}), do: {:ok, value}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}
  defp normalize_transaction_result({:error, reason, _value, _changes}), do: {:error, reason}

  @doc """
  List session-to-server bindings, preloading the server struct.
  """
  def list_session_servers(session_id) when is_binary(session_id) do
    Repo.all(
      from sms in SessionServer,
        where: sms.session_id == ^session_id,
        preload: [:mcp_server],
        order_by: [asc: sms.inserted_at]
    )
  end

  def list_session_servers(%Session{id: session_id}) do
    list_session_servers(session_id)
  end

  @doc """
  List session bindings for a given MCP server, preloading sessions and auth.
  """
  def list_server_sessions(server_id) when is_binary(server_id) do
    Repo.all(
      from sms in SessionServer,
        where: sms.mcp_server_id == ^server_id,
        join: s in assoc(sms, :session),
        join: sa in assoc(s, :saved_authentication),
        preload: [session: {s, saved_authentication: sa}],
        order_by: [asc: sms.inserted_at]
    )
  end

  @doc """
  Produce a map of session MCP bindings keyed by alias/name, mirroring the legacy
  `session.mcps` JSON structure for transitional consumers.
  """
  def session_connector_map(session) do
    list_session_servers(session)
    |> Enum.reduce(%{}, fn binding, acc ->
      server = binding.mcp_server
      key = binding.alias || server.name

      config = %{
        "display_name" => server.display_name,
        "description" => server.description,
        "transport" => server.transport,
        "url" => server.url,
        "command" => server.command,
        "args" => server.args,
        "headers" => server.headers,
        "env" => server.env,
        "metadata" => server.metadata,
        "tags" => server.tags,
        "auth_token" => server.auth_token,
        "enabled" => server.is_enabled
      }

      Map.put(acc, key, config)
    end)
  end

  defp transport_label(%Servers{transport: "stdio"}), do: "stdio"
  defp transport_label(%Servers{transport: transport}) when is_binary(transport), do: transport
  defp transport_label(_), do: nil

  defp validate_entries(entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {attrs, idx}, {:ok, acc} ->
      changeset = Servers.changeset(%Servers{}, attrs)

      if changeset.valid? do
        {:cont, {:ok, acc ++ [{idx, changeset}]}}
      else
        {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, validated} -> {:ok, validated}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp upsert_servers(validated_entries) do
    servers =
      Enum.map(validated_entries, fn {_idx, changeset} ->
        attrs =
          changeset
          |> Changeset.apply_changes()
          |> Map.from_struct()
          |> Map.drop([
            :id,
            :inserted_at,
            :updated_at,
            :session_count,
            :__meta,
            :__meta__,
            :session_servers,
            :sessions,
            :__struct__
          ])

        Repo.insert(
          %Servers{name: attrs.name}
          |> Changeset.change(attrs),
          on_conflict: {
            :replace,
            [
              :display_name,
              :description,
              :transport,
              :url,
              :command,
              :args,
              :headers,
              :env,
              :metadata,
              :tags,
              :auth_token,
              :is_enabled,
              :definition_source,
              :updated_at
            ]
          },
          conflict_target: :name,
          returning: true
        )
        |> case do
          {:ok, server} ->
            server

          {:error, %Changeset{} = changeset} ->
            raise __MODULE__.ChangesetError, changeset: changeset
        end
      end)

    {:ok, servers}
  rescue
    error in [__MODULE__.ChangesetError] -> {:error, error.changeset}
  end

  defmodule ChangesetError do
    defexception [:changeset]

    @impl true
    def message(%__MODULE__{changeset: changeset}) do
      "changeset error: #{inspect(changeset.errors)}"
    end
  end

  defp sanitize_server_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&to_string/1)
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, acc} ->
      case Ecto.UUID.cast(id) do
        {:ok, uuid} -> {:cont, {:ok, [uuid | acc]}}
        :error -> {:halt, {:error, {:invalid_server_id, id}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, acc |> Enum.reverse() |> Enum.uniq()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_all_servers_exist(ids) do
    case ids do
      [] ->
        :ok

      _ ->
        count = Repo.aggregate(from(s in Servers, where: s.id in ^ids), :count, :id)
        if count == length(ids), do: :ok, else: {:error, :unknown_server}
    end
  end

  defp delete_obsolete_session_links(session_id, ids) do
    Repo.delete_all(
      from sms in SessionServer,
        where: sms.session_id == ^session_id and sms.mcp_server_id not in ^ids
    )
  end

  defp insert_missing_session_links(session_id, ids) do
    existing_ids =
      Repo.all(
        from sms in SessionServer,
          where: sms.session_id == ^session_id,
          select: sms.mcp_server_id
      )

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    ids
    |> Enum.reject(&(&1 in existing_ids))
    |> Enum.map(fn id ->
      %{
        id: Ecto.UUID.generate(),
        session_id: session_id,
        mcp_server_id: id,
        metadata: %{},
        attached_at: now,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> case do
      [] -> :ok
      rows -> Repo.insert_all(SessionServer, rows)
    end
  end
end
