defmodule TheMaestro.Conversations.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sessions" do
    field :name, :string
    field :last_used_at, :utc_datetime
    field :working_dir, :string

    # New session-centric fields that consolidate Agent data onto Session
    field :model_id, :string
    field :persona, :map, default: %{}
    field :memory, :map, default: %{}
    field :tools, :map, default: %{}
    field :mcps, :map, default: %{}

    # Saved authentication
    belongs_to :saved_authentication, TheMaestro.SavedAuthentication,
      foreign_key: :auth_id,
      type: :integer

    # Associate the latest chat snapshot for quick preload in dashboards
    belongs_to :latest_chat_entry, TheMaestro.Conversations.ChatEntry,
      foreign_key: :latest_chat_entry_id,
      type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :name,
      :last_used_at,
      :latest_chat_entry_id,
      :working_dir,
      :auth_id,
      :model_id,
      :persona,
      :memory,
      :tools,
      :mcps
    ])
    |> validate_required([:auth_id])
    |> validate_change(:working_dir, fn :working_dir, v ->
      cond do
        is_nil(v) or v == "" -> []
        is_binary(v) and File.dir?(v) -> []
        true -> [working_dir: "directory does not exist or is not accessible"]
      end
    end)
    |> foreign_key_constraint(:auth_id)
    |> foreign_key_constraint(:latest_chat_entry_id)
  end
end
