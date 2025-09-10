defmodule TheMaestro.Repo.Migrations.CreateSuppliedContextItems do
  use Ecto.Migration

  def change do
    create table(:supplied_context_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string
      add :name, :string
      add :text, :text
      add :version, :integer
      add :tags, :map
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:supplied_context_items, [:type, :name],
             name: :supplied_context_items_type_name_index
           )
  end
end
