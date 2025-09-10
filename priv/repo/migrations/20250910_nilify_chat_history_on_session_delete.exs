defmodule TheMaestro.Repo.Migrations.NilifyChatHistoryOnSessionDelete do
  use Ecto.Migration

  def up do
    # Drop existing FK if present
    execute("ALTER TABLE chat_history DROP CONSTRAINT IF EXISTS chat_history_session_id_fkey")

    # Allow NULLs and set FK to ON DELETE SET NULL
    alter table(:chat_history) do
      modify :session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all),
        null: true
    end
  end

  def down do
    # Revert to NOT NULL and ON DELETE NO ACTION
    execute("ALTER TABLE chat_history DROP CONSTRAINT IF EXISTS chat_history_session_id_fkey")

    alter table(:chat_history) do
      modify :session_id, references(:sessions, type: :binary_id, on_delete: :nothing),
        null: false
    end
  end
end
