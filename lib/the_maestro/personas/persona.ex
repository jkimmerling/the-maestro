defmodule TheMaestro.Personas.Persona do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "personas" do
    field :name, :string
    field :prompt_text, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(persona, attrs) do
    persona
    |> cast(attrs, [:name, :prompt_text])
    |> validate_required([:name, :prompt_text])
    |> validate_length(:name, min: 3, max: 50)
    |> unique_constraint(:name)
  end
end
