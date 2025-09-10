defmodule TheMaestro.Repo.Migrations.DropDomainTables do
  use Ecto.Migration

  def change do
    # Drop domain tables if they already exist (do not touch Oban tables)
    # Relax/drop FKs before dropping tables to avoid dependency errors
    execute "ALTER TABLE IF EXISTS sessions DROP CONSTRAINT IF EXISTS sessions_latest_chat_entry_id_fkey"

    execute "ALTER TABLE IF EXISTS chat_history DROP CONSTRAINT IF EXISTS chat_history_session_id_fkey"

    execute "ALTER TABLE IF EXISTS tool_runs DROP CONSTRAINT IF EXISTS tool_runs_session_id_fkey"

    # Drop child tables first, then parents
    drop_if_exists table(:tool_runs)
    drop_if_exists table(:chat_history)
    drop_if_exists table(:sessions)
    drop_if_exists table(:saved_authentications)
    drop_if_exists table(:personas)
    drop_if_exists table(:base_system_prompts)
    drop_if_exists table(:agents)
  end
end
