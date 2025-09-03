defmodule TheMaestro.Repo.Migrations.CreateToolRuns do
  use Ecto.Migration

  def change do
    create table(:tool_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :status, :string
      add :exit_code, :integer
      add :args, :map, default: %{}
      add :cwd, :string
      add :bytes_read, :integer
      add :bytes_written, :integer
      add :stdout, :text
      add :stderr, :text
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :provider, :map, default: %{}
      add :call_request, :map, default: %{}
      add :call_response, :map, default: %{}
      add :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:tool_runs, [:agent_id])
    create index(:tool_runs, [:session_id])
    create index(:tool_runs, [:name, :inserted_at])
  end
end
