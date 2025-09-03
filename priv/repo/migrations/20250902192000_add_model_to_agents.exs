defmodule TheMaestro.Repo.Migrations.AddModelToAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :model_id, :string
    end

    create index(:agents, [:model_id])
  end
end
