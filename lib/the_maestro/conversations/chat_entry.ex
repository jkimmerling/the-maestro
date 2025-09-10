defmodule TheMaestro.Conversations.ChatEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_history" do
    field :turn_index, :integer
    field :actor, :string
    field :provider, :string
    field :request_headers, :map, default: %{}
    field :response_headers, :map, default: %{}
    field :combined_chat, :map, default: %{}
    field :edit_version, :integer, default: 0
    field :thread_id, Ecto.UUID
    field :parent_thread_id, Ecto.UUID
    field :fork_from_entry_id, Ecto.UUID
    field :thread_label, :string
    field :session_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chat_entry, attrs) do
    chat_entry
    |> cast(attrs, [
      :session_id,
      :turn_index,
      :actor,
      :provider,
      :request_headers,
      :response_headers,
      :combined_chat,
      :edit_version,
      :thread_id,
      :parent_thread_id,
      :fork_from_entry_id,
      :thread_label
    ])
    |> validate_required([:session_id, :turn_index, :actor, :combined_chat])
    |> validate_inclusion(:actor, ["user", "assistant", "tool", "system"])
    |> foreign_key_constraint(:session_id)
    |> unique_constraint([:session_id, :turn_index])
    |> unique_constraint([:thread_id, :turn_index])
  end
end
