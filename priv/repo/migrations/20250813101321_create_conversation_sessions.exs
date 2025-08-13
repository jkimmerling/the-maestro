defmodule TheMaestro.Repo.Migrations.CreateConversationSessions do
  use Ecto.Migration

  def change do
    create table(:conversation_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_name, :string, size: 255
      add :agent_id, :string, null: false
      add :user_id, :string
      add :session_data, :text, null: false
      add :message_count, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:conversation_sessions, [:agent_id])
    create index(:conversation_sessions, [:user_id])
    create index(:conversation_sessions, [:inserted_at])
    create index(:conversation_sessions, [:updated_at])
    create unique_index(:conversation_sessions, [:agent_id, :session_name])
  end
end
