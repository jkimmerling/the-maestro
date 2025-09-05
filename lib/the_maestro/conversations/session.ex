defmodule TheMaestro.Conversations.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sessions" do
    field :name, :string
    field :last_used_at, :utc_datetime
    field :working_dir, :string

    belongs_to :agent, TheMaestro.Agents.Agent, type: :binary_id
    # Associate the latest chat snapshot for quick preload in dashboards
    belongs_to :latest_chat_entry, TheMaestro.Conversations.ChatEntry,
      foreign_key: :latest_chat_entry_id,
      type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:name, :last_used_at, :agent_id, :latest_chat_entry_id, :working_dir])
    |> validate_required([:agent_id])
    |> validate_change(:working_dir, fn :working_dir, v ->
      cond do
        is_nil(v) or v == "" -> []
        is_binary(v) and File.dir?(v) -> []
        true -> [working_dir: "directory does not exist or is not accessible"]
      end
    end)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:latest_chat_entry_id)
  end
end
