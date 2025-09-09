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

    # Saved authentication moved from Agent; keep Agent for cutover
    belongs_to :saved_authentication, TheMaestro.SavedAuthentication,
      foreign_key: :auth_id,
      type: :integer

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
    |> cast(attrs, [
      :name,
      :last_used_at,
      :agent_id,
      :latest_chat_entry_id,
      :working_dir,
      :auth_id,
      :model_id,
      :persona,
      :memory,
      :tools,
      :mcps
    ])
    # Phase 2: require SavedAuth (auth_id). Keep agent_id optional for cutover.
    |> validate_required_cutover()
    |> validate_change(:working_dir, fn :working_dir, v ->
      cond do
        is_nil(v) or v == "" -> []
        is_binary(v) and File.dir?(v) -> []
        true -> [working_dir: "directory does not exist or is not accessible"]
      end
    end)
    |> foreign_key_constraint(:auth_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:latest_chat_entry_id)
  end

  # During cutover, allow either auth_id or agent_id; prefer auth_id.
  defp validate_required_cutover(%Ecto.Changeset{} = cs) do
    auth = get_field(cs, :auth_id)
    agent = get_field(cs, :agent_id)

    if is_nil(auth) and is_nil(agent) do
      add_error(cs, :auth_id, "can't be blank (or provide agent_id during cutover)")
    else
      cs
    end
  end
end
