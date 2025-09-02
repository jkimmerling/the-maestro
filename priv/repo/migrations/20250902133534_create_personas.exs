defmodule TheMaestro.Repo.Migrations.CreatePersonas do
  use Ecto.Migration

  def change do
    create table(:personas, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :prompt_text, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:personas, [:name])
  end
end
