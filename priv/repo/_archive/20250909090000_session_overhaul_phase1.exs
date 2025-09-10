defmodule TheMaestro.Repo.Migrations.SessionOverhaulPhase1 do
  use Ecto.Migration

  def up do
    # ----- chat_history: add thread identifiers for session-centric chats -----
    alter table(:chat_history) do
      add :thread_id, :binary_id
      add :parent_thread_id, :binary_id
      add :fork_from_entry_id, :binary_id
      add :thread_label, :string
    end

    # Make session_id nullable for compatibility during cutover (preserve existing FK)
    execute("ALTER TABLE chat_history ALTER COLUMN session_id DROP NOT NULL")

    create index(:chat_history, [:thread_id])
    create index(:chat_history, [:parent_thread_id])
    create index(:chat_history, [:fork_from_entry_id])
    create index(:chat_history, [:thread_label])

    # New uniqueness constraint once thread_id is in use; session-based unique index remains
    create unique_index(:chat_history, [:thread_id, :turn_index])

    # ----- sessions: add auth/model + jsonb fields previously on Agent -----
    alter table(:sessions) do
      add :auth_id, references(:saved_authentications, on_delete: :restrict)
      add :model_id, :string
      add :persona, :map, default: %{}, null: false
      add :memory, :map, default: %{}, null: false
      add :tools, :map, default: %{}, null: false
      add :mcps, :map, default: %{}, null: false
      # working_dir already exists via prior migration
    end

    create index(:sessions, [:auth_id])
    create index(:sessions, [:model_id])
  end

  def down do
    # ----- sessions: drop newly added fields -----
    drop_if_exists index(:sessions, [:model_id])
    drop_if_exists index(:sessions, [:auth_id])

    alter table(:sessions) do
      remove :mcps
      remove :tools
      remove :memory
      remove :persona
      remove :model_id
      remove :auth_id
    end

    # ----- chat_history: drop thread identifiers and reset session_id nullability -----
    drop_if_exists unique_index(:chat_history, [:thread_id, :turn_index])
    drop_if_exists index(:chat_history, [:thread_label])
    drop_if_exists index(:chat_history, [:fork_from_entry_id])
    drop_if_exists index(:chat_history, [:parent_thread_id])
    drop_if_exists index(:chat_history, [:thread_id])

    alter table(:chat_history) do
      remove :thread_label
      remove :fork_from_entry_id
      remove :parent_thread_id
      remove :thread_id
    end

    execute("ALTER TABLE chat_history ALTER COLUMN session_id SET NOT NULL")
  end
end
