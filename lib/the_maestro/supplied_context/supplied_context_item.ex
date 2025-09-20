defmodule TheMaestro.SuppliedContext.SuppliedContextItem do
  use Ecto.Schema
  import Ecto.Changeset
  @type provider :: :shared | :openai | :anthropic | :gemini
  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "supplied_context_items" do
    field :type, Ecto.Enum, values: [:persona, :system_prompt]
    field :provider, Ecto.Enum, values: [:shared, :openai, :anthropic, :gemini], default: :shared

    field :render_format, Ecto.Enum,
      values: [:text, :anthropic_blocks, :gemini_parts],
      default: :text

    field :name, :string
    field :text, :string
    field :version, :integer
    field :labels, :map, default: %{}
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :immutable, :boolean, default: false
    field :source_ref, :string
    field :metadata, :map, default: %{}
    field :editor, :string
    field :change_note, :string

    belongs_to :family, __MODULE__, foreign_key: :family_id, type: :binary_id
    has_many :versions, __MODULE__, foreign_key: :family_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(supplied_context_item, attrs) do
    supplied_context_item
    |> cast(attrs, [
      :type,
      :provider,
      :render_format,
      :name,
      :text,
      :version,
      :labels,
      :position,
      :is_default,
      :immutable,
      :source_ref,
      :metadata,
      :family_id,
      :editor,
      :change_note
    ])
    |> maybe_put_family_id()
    |> validate_required([
      :type,
      :provider,
      :render_format,
      :name,
      :text,
      :version,
      :family_id
    ])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> normalize_maps()
    |> unique_constraint(:name,
      name: "supplied_context_items_type_provider_name_version_index",
      message: "already exists for this type/provider/version"
    )
    |> unique_constraint(:version,
      name: "supplied_context_items_family_version_index",
      message: "version already exists for this prompt"
    )
  end

  defp normalize_maps(changeset) do
    changeset
    |> update_change(:labels, &normalize_map/1)
    |> update_change(:metadata, &normalize_map/1)
  end

  defp maybe_put_family_id(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :family_id) || get_change(changeset, :family_id) do
      nil -> put_change(changeset, :family_id, Ecto.UUID.generate())
      _ -> changeset
    end
  end

  defp normalize_map(nil), do: %{}
  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_), do: %{}
end
