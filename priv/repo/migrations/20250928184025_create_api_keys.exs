defmodule TheMaestro.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :label, :string
      add :token_hash, :string
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:api_keys, [:token_hash])
    create index(:api_keys, [:revoked_at])
  end
end
