defmodule TheMaestro.Conversations.ToolChangeLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tool_change_logs" do
    belongs_to :chat_entry, TheMaestro.Conversations.ChatEntry, type: :binary_id
    field :session_id, :binary_id
    field :provider, :string
    field :tool_name, :string
    field :file_path, :string
    field :change_type, :string
    field :diff, :string
    field :summary, :map, default: %{}
    field :metadata, :map, default: %{}
    timestamps(type: :utc_datetime)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :chat_entry_id,
      :session_id,
      :provider,
      :tool_name,
      :file_path,
      :change_type,
      :diff,
      :summary,
      :metadata
    ])
    |> validate_required([:tool_name])
  end
end
