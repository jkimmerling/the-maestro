defmodule TheMaestro.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "agents" do
    field :name, :string
    field :tools, :map, default: %{}
    field :mcps, :map, default: %{}
    field :memory, :map, default: %{}

    # Associations (note auth_id remains integer FK)
    belongs_to :saved_authentication, TheMaestro.SavedAuthentication, foreign_key: :auth_id, type: :integer
    belongs_to :base_system_prompt, TheMaestro.Prompts.BaseSystemPrompt, type: :binary_id
    belongs_to :persona, TheMaestro.Personas.Persona, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :name,
      :tools,
      :mcps,
      :memory,
      :auth_id,
      :base_system_prompt_id,
      :persona_id
    ])
    |> validate_required([:name, :auth_id])
    |> validate_length(:name, min: 3, max: 50)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_-]+$/)
    |> normalize_maps()
    |> foreign_key_constraint(:auth_id)
    |> foreign_key_constraint(:base_system_prompt_id)
    |> foreign_key_constraint(:persona_id)
    |> unique_constraint(:name)
  end

  defp normalize_maps(changeset) do
    changeset
    |> update_change(:tools, &ensure_map/1)
    |> update_change(:mcps, &ensure_map/1)
    |> update_change(:memory, &ensure_map/1)
  end

  defp ensure_map(%{} = m), do: m
  defp ensure_map(_), do: %{}
end
