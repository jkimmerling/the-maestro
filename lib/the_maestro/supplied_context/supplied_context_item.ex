defmodule TheMaestro.SuppliedContext.SuppliedContextItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "supplied_context_items" do
    field :type, Ecto.Enum, values: [:persona, :system_prompt]
    field :name, :string
    field :text, :string
    field :version, :integer
    field :tags, :map
    field :metadata, :map

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(supplied_context_item, attrs) do
    supplied_context_item
    |> cast(attrs, [:type, :name, :text, :version, :tags, :metadata])
    |> validate_required([:type, :name, :text, :version])
  end
end
