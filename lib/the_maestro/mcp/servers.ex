defmodule TheMaestro.MCP.Servers do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @transports ~w(stdio stream-http http sse)
  @http_transports ~w(stream-http http sse)
  @sources ~w(manual cli json toml)

  schema "mcp_servers" do
    field :name, :string
    field :display_name, :string
    field :description, :string
    field :transport, :string
    field :url, :string
    field :command, :string
    field :args, {:array, :string}, default: []
    field :headers, :map, default: %{}
    field :env, :map, default: %{}
    field :metadata, :map, default: %{}
    field :tags, {:array, :string}, default: []
    field :auth_token, :string
    field :is_enabled, :boolean, default: false
    field :definition_source, :string, default: "manual"
    field :session_count, :integer, virtual: true, default: 0

    has_many :session_servers, TheMaestro.MCP.SessionServer, foreign_key: :mcp_server_id

    many_to_many :sessions, TheMaestro.Conversations.Session,
      join_through: TheMaestro.MCP.SessionServer,
      join_keys: [mcp_server_id: :id, session_id: :id]

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t() | nil,
          display_name: String.t() | nil,
          description: String.t() | nil,
          transport: String.t() | nil,
          url: String.t() | nil,
          command: String.t() | nil,
          args: [String.t()],
          headers: map(),
          env: map(),
          metadata: map(),
          tags: [String.t()],
          auth_token: String.t() | nil,
          is_enabled: boolean() | nil,
          definition_source: String.t() | nil,
          session_count: non_neg_integer(),
          session_servers: list(),
          sessions: list(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc false
  def changeset(servers, attrs) do
    servers
    |> cast(attrs, [
      :name,
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
      :definition_source
    ])
    |> validate_required([:name, :display_name, :transport, :definition_source])
    |> update_change(:definition_source, &normalize_source/1)
    |> update_change(:name, &normalize_name/1)
    |> update_change(:display_name, &String.trim/1)
    |> update_change(:transport, &normalize_transport/1)
    |> update_change(:command, &maybe_trim/1)
    |> update_change(:url, &maybe_trim/1)
    |> validate_inclusion(:transport, @transports)
    |> validate_inclusion(:definition_source, @sources)
    |> validate_url_required_when_needed()
    |> validate_command_required_when_needed()
    |> normalize_args()
    |> normalize_map(:headers)
    |> normalize_map(:env)
    |> normalize_map(:metadata)
    |> update_change(:tags, &normalize_tags/1)
    |> unique_constraint(:name)
  end

  def normalize_name(nil), do: nil

  def normalize_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.replace(~r/\s+/, "-")
    |> String.downcase()
  end

  defp normalize_transport(nil), do: nil

  defp normalize_transport(t) when is_binary(t) do
    t
    |> String.trim()
    |> String.downcase()
    |> case do
      "http" -> "stream-http"
      other -> other
    end
  end

  defp validate_url_required_when_needed(changeset) do
    transport = get_field(changeset, :transport)
    url = get_field(changeset, :url)

    if transport in @http_transports and blank?(url) do
      add_error(changeset, :url, "is required for #{transport} transport")
    else
      changeset
    end
  end

  defp validate_command_required_when_needed(changeset) do
    transport = get_field(changeset, :transport)
    command = get_field(changeset, :command)

    if transport == "stdio" and blank?(command) do
      add_error(changeset, :command, "is required for stdio transport")
    else
      changeset
    end
  end

  defp normalize_args(changeset) do
    case get_change(changeset, :args) do
      nil ->
        if get_field(changeset, :args) == nil do
          put_change(changeset, :args, [])
        else
          changeset
        end

      args when is_list(args) ->
        trimmed =
          args
          |> Enum.reject(&blank?/1)
          |> Enum.map(&String.trim/1)

        put_change(changeset, :args, trimmed)

      _ ->
        add_error(changeset, :args, "must be a list of strings")
    end
  end

  defp normalize_map(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        current = get_field(changeset, field)

        if current == nil do
          put_change(changeset, field, %{})
        else
          changeset
        end

      value when is_map(value) ->
        changeset

      _ ->
        changeset
        |> add_error(field, "must be a map")
        |> put_change(field, %{})
    end
  end

  defp normalize_tags(nil), do: []

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.reject(&blank?/1)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  defp normalize_tags(_), do: []

  defp normalize_source(nil), do: "manual"

  defp normalize_source(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "command" -> "cli"
      other -> other
    end
  end

  defp normalize_source(_), do: "manual"

  defp blank?(value), do: value in [nil, ""]

  defp maybe_trim(nil), do: nil
  defp maybe_trim(value) when is_binary(value), do: String.trim(value)
  defp maybe_trim(value), do: value
end
