defmodule TheMaestro.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :tools, :map, null: false, default: %{}
      add :mcps, :map, null: false, default: %{}
      add :memory, :map, null: false, default: %{}
      add :auth_id, references(:saved_authentications, on_delete: :restrict), null: false

      add :base_system_prompt_id,
          references(:base_system_prompts, type: :binary_id, on_delete: :nilify_all)

      add :persona_id, references(:personas, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agents, [:name])
    create index(:agents, [:auth_id])
    create index(:agents, [:base_system_prompt_id])
    create index(:agents, [:persona_id])
  end
end
