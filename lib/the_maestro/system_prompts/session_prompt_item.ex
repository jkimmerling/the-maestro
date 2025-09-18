defmodule TheMaestro.SystemPrompts.SessionPromptItem do
  use Ecto.Schema
  import Ecto.Changeset
  @type id :: Ecto.UUID.t()
  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "session_prompt_items" do
    field :provider, Ecto.Enum, values: [:openai, :anthropic, :gemini]
    field :position, :integer, default: 0
    field :enabled, :boolean, default: true
    field :overrides, :map, default: %{}

    belongs_to :session, TheMaestro.Conversations.Session
    belongs_to :supplied_context_item, TheMaestro.SuppliedContext.SuppliedContextItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(session_prompt_item, attrs) do
    session_prompt_item
    |> cast(attrs, [
      :session_id,
      :supplied_context_item_id,
      :provider,
      :position,
      :enabled,
      :overrides
    ])
    |> validate_required([
      :session_id,
      :supplied_context_item_id,
      :provider,
      :position,
      :enabled
    ])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> normalize_overrides()
    |> unique_constraint(:position,
      name: "session_prompt_items_session_provider_position_index",
      message: "position already in use for this provider"
    )
    |> unique_constraint(:supplied_context_item_id,
      name: "session_prompt_items_session_prompt_unique_index",
      message: "prompt already attached to session"
    )
  end

  defp normalize_overrides(changeset) do
    update_change(changeset, :overrides, fn
      nil -> %{}
      map when is_map(map) -> map
      _ -> %{}
    end)
  end
end
