defmodule TheMaestro.MCP.SessionServer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "session_mcp_servers" do
    field :alias, :string
    field :attached_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :session, TheMaestro.Conversations.Session, type: :binary_id
    belongs_to :mcp_server, TheMaestro.MCP.Servers, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(session_server, attrs) do
    session_server
    |> cast(attrs, [:alias, :attached_at, :metadata, :session_id, :mcp_server_id])
    |> put_default_attached_at()
    |> validate_required([:session_id, :mcp_server_id])
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:mcp_server_id)
    |> unique_constraint([:session_id, :mcp_server_id])
  end

  defp put_default_attached_at(changeset) do
    case get_field(changeset, :attached_at) do
      nil -> put_change(changeset, :attached_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end
