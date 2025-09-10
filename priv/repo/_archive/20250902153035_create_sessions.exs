defmodule TheMaestro.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :last_used_at, :utc_datetime
      add :agent_id, references(:agents, type: :binary_id, on_delete: :restrict), null: false
      add :latest_chat_entry_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create index(:sessions, [:agent_id])
    create index(:sessions, [:latest_chat_entry_id])
  end
end
