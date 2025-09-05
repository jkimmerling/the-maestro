defmodule TheMaestro.Repo.Migrations.AddWorkingDirToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :working_dir, :string
    end

    create index(:sessions, [:working_dir])
  end
end
