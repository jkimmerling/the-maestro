defmodule TheMaestro.Repo.Migrations.CreateSavedAuthentications do
  use Ecto.Migration

  def change do
    create table(:saved_authentications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string
      add :auth_type, :string
      add :name, :string
      add :credentials, :map
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:saved_authentications, [:provider, :auth_type, :name],
             name: :saved_authentications_provider_auth_type_name_index
           )

    # Database-level constraints to validate session name format and length
    create constraint(:saved_authentications, :name_format, check: "name ~ '^[A-Za-z0-9_-]+$'")

    create constraint(:saved_authentications, :name_length,
             check: "char_length(name) >= 3 AND char_length(name) <= 50"
           )
  end
end
