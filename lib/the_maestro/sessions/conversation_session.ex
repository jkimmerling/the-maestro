defmodule TheMaestro.Sessions.ConversationSession do
  @moduledoc """
  Schema for conversation sessions that can be saved and restored.

  A conversation session represents a checkpoint of an agent's state,
  including its complete message history and configuration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: binary(),
          session_name: String.t(),
          agent_id: String.t(),
          user_id: String.t() | nil,
          session_data: String.t(),
          message_count: non_neg_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "conversation_sessions" do
    field :session_name, :string
    field :agent_id, :string
    field :user_id, :string
    field :session_data, :string
    field :message_count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for conversation sessions.

  ## Required fields
  - agent_id
  - session_data

  ## Optional fields
  - session_name (auto-generated if not provided)
  - user_id
  - message_count (defaults to 0)
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation_session, attrs) do
    conversation_session
    |> cast(attrs, [:session_name, :agent_id, :user_id, :session_data, :message_count])
    |> validate_required([:agent_id, :session_data])
    |> validate_length(:session_name, min: 1, max: 255)
    |> validate_length(:agent_id, min: 1, max: 255)
    |> validate_number(:message_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:agent_id, :session_name],
      message: "A session with this name already exists for this agent"
    )
    |> maybe_generate_session_name()
  end

  # Private functions

  defp maybe_generate_session_name(changeset) do
    case get_field(changeset, :session_name) do
      nil ->
        timestamp =
          DateTime.utc_now()
          |> DateTime.to_string()
          |> String.replace(~r/[\s\-\.:Z]/, "")

        put_change(changeset, :session_name, "session_#{timestamp}")

      _existing_name ->
        changeset
    end
  end
end
