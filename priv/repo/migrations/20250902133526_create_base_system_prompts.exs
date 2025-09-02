defmodule TheMaestro.Repo.Migrations.CreateBaseSystemPrompts do
  use Ecto.Migration

  def change do
    create table(:base_system_prompts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :prompt_text, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:base_system_prompts, [:name])
  end
end
