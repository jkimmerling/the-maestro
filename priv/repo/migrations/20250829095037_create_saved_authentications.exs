defmodule TheMaestro.Repo.Migrations.CreateSavedAuthentications do
  use Ecto.Migration

  def change do
    create table(:saved_authentications) do
      add :provider, :string, null: false, comment: "AI provider (anthropic, openai, gemini)"
      add :auth_type, :string, null: false, comment: "Authentication type (api_key, oauth)"
      add :credentials, :map, null: false, comment: "Encrypted credentials as JSON"
      add :expires_at, :utc_datetime, comment: "When credentials expire (for OAuth tokens)"

      timestamps()
    end

    # Unique constraint to ensure one credential per provider per auth type
    create unique_index(:saved_authentications, [:provider, :auth_type],
             name: :saved_authentications_provider_auth_type_index
           )

    # Index for finding expiring tokens
    create index(:saved_authentications, [:expires_at])
  end
end
