defmodule TheMaestro.Repo.Migrations.AddWorkingDirectoryToAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :working_directory, :string
    end

    create index(:agents, [:working_directory])
  end
end

