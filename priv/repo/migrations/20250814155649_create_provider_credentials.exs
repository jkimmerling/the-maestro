defmodule TheMaestro.Repo.Migrations.CreateProviderCredentials do
  use Ecto.Migration

  def change do
    create table(:provider_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      # 'anthropic', 'google', 'openai'
      add :provider, :string, null: false
      # 'oauth', 'api_key'
      add :auth_method, :string, null: false
      # encrypted credentials as JSON
      add :credentials, :text, null: false
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:provider_credentials, [:user_id])
    create index(:provider_credentials, [:provider])
    create index(:provider_credentials, [:auth_method])
    create index(:provider_credentials, [:expires_at])
    create unique_index(:provider_credentials, [:user_id, :provider, :auth_method])
  end
end
