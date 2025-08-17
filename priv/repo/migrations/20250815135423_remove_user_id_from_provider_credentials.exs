defmodule TheMaestro.Repo.Migrations.RemoveUserIdFromProviderCredentials do
  use Ecto.Migration

  def change do
    # First drop the unique constraint that includes user_id
    drop_if_exists unique_index(:provider_credentials, [:user_id, :provider, :auth_method])

    # Remove the user_id column
    alter table(:provider_credentials) do
      remove :user_id, :string
    end

    # Add new unique constraint without user_id
    create unique_index(:provider_credentials, [:provider, :auth_method])
  end
end
