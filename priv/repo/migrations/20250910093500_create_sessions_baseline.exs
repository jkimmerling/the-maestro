defmodule TheMaestro.Repo.Migrations.CreateSessionsBaseline do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :last_used_at, :utc_datetime
      add :working_dir, :string

      add :model_id, :string
      add :persona, :map
      add :memory, :map
      add :tools, :map
      add :mcps, :map

      add :auth_id, references(:saved_authentications, on_delete: :nothing, type: :binary_id)

      add :latest_chat_entry_id,
          references(:chat_history, on_delete: :nilify_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:sessions, [:auth_id])
    create index(:sessions, [:latest_chat_entry_id])
  end
end
