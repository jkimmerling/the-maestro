defmodule TheMaestro.Repo.Migrations.CreateChatHistory do
  use Ecto.Migration

  def up do
    create table(:chat_history, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :turn_index, :integer, null: false
      add :actor, :string, null: false
      add :provider, :string
      add :request_headers, :map, null: false, default: %{}
      add :response_headers, :map, null: false, default: %{}
      add :combined_chat, :map, null: false, default: %{}
      add :edit_version, :integer, null: false, default: 0

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chat_history, [:session_id])
    create unique_index(:chat_history, [:session_id, :turn_index])

    # Add a proper FK for sessions.latest_chat_entry_id -> chat_history(id)
    alter table(:sessions) do
      modify :latest_chat_entry_id,
             references(:chat_history, type: :binary_id, on_delete: :nilify_all)
    end
  end

  def down do
    # Drop FK on sessions.latest_chat_entry_id
    alter table(:sessions) do
      modify :latest_chat_entry_id, :binary_id
    end

    drop_if_exists unique_index(:chat_history, [:session_id, :turn_index])
    drop_if_exists index(:chat_history, [:session_id])
    drop table(:chat_history)
  end
end
