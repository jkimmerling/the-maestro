defmodule TheMaestro.Repo.Migrations.CreatePromptTemplates do
  use Ecto.Migration

  def change do
    create table(:prompt_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :template_id, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :category, :string, null: false
      add :template_content, :text, null: false
      add :parameters, :map, default: %{}
      add :usage_examples, {:array, :map}, default: []
      add :performance_metrics, :map, default: %{}
      add :version, :integer, default: 1
      add :parent_version, :integer
      add :created_by, :string, null: false
      add :tags, {:array, :string}, default: []
      add :validation_rules, :map, default: %{}
      add :optimization_suggestions, {:array, :string}, default: []

      timestamps()
    end

    create index(:prompt_templates, [:template_id])
    create index(:prompt_templates, [:category])
    create index(:prompt_templates, [:created_by])
    create index(:prompt_templates, [:version])
    create index(:prompt_templates, [:template_id, :version])
  end
end
