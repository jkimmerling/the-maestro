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

    # Virtual JSON fields for form editing
    field :tools_json, :string, virtual: true
    field :mcps_json, :string, virtual: true
    field :memory_json, :string, virtual: true

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
      :tools_json,
      :mcps_json,
      :memory_json,
      :auth_id,
      :base_system_prompt_id,
      :persona_id
    ])
    |> validate_required([:name, :auth_id])
    |> validate_length(:name, min: 3, max: 50)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_-]+$/)
    |> decode_json_field(:tools_json, :tools)
    |> decode_json_field(:mcps_json, :mcps)
    |> decode_json_field(:memory_json, :memory)
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

  defp decode_json_field(changeset, src_field, dest_field) do
    case get_change(changeset, src_field) do
      nil -> changeset
      "" -> changeset
      json when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, %{} = map} -> put_change(changeset, dest_field, map)
          {:ok, _other} -> add_error(changeset, src_field, "must be a JSON object")
          {:error, %Jason.DecodeError{position: pos}} ->
            add_error(changeset, src_field, "invalid JSON at position #{pos}")
        end
    end
  end

  # no-op helpers removed after moving virtual defaults to Agents.change_agent/2
end
