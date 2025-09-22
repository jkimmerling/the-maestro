defmodule TheMaestro.Repo.Migrations.AddToolChangeLogs do
  use Ecto.Migration

  def change do
    create table(:tool_change_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chat_entry_id, references(:chat_history, type: :binary_id, on_delete: :nilify_all)
      add :session_id, :binary_id
      add :provider, :string
      add :tool_name, :string, null: false
      add :file_path, :string
      add :change_type, :string
      add :diff, :text
      add :summary, :map
      add :metadata, :map
      timestamps(type: :utc_datetime)
    end

    create index(:tool_change_logs, [:session_id])
    create index(:tool_change_logs, [:tool_name])
    create index(:tool_change_logs, [:inserted_at])
  end
end
