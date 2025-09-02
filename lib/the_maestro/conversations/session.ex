defmodule TheMaestro.Conversations.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sessions" do
    field :name, :string
    field :last_used_at, :utc_datetime

    belongs_to :agent, TheMaestro.Agents.Agent, type: :binary_id
    field :latest_chat_entry_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:name, :last_used_at, :agent_id, :latest_chat_entry_id])
    |> validate_required([:agent_id])
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:latest_chat_entry_id)
  end
end
