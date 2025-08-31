defmodule TheMaestro.Repo.Migrations.AddNamedSessions do
  @moduledoc """
  Add support for named authentication sessions per provider/auth_type combination.

  This migration:
  1. Adds a 'name' field to saved_authentications table
  2. Backfills existing records with default names
  3. Updates unique constraint to include name field
  4. Adds performance index for name lookups
  """
  use Ecto.Migration

  def up do
    # Step 1: Add name field with temporary default value
    alter table(:saved_authentications) do
      add :name, :string, null: false, default: "default"
    end

    # Step 2: Backfill existing records with meaningful names
    execute """
    UPDATE saved_authentications 
    SET name = CONCAT('default_', provider, '_', auth_type)
    """

    # Step 3: Remove the temporary default constraint
    alter table(:saved_authentications) do
      modify :name, :string, null: false
    end

    # Step 4: Add validation check for name format (alphanumeric, underscore, hyphen only)
    create constraint(:saved_authentications, :name_format, check: "name ~ '^[a-zA-Z0-9_-]+$'")

    # Step 5: Add length constraint (3-50 characters)
    create constraint(:saved_authentications, :name_length,
             check: "LENGTH(name) >= 3 AND LENGTH(name) <= 50"
           )

    # Step 6: Drop old unique constraint
    drop_if_exists unique_index(:saved_authentications, [:provider, :auth_type],
                     name: :saved_authentications_provider_auth_type_index
                   )

    # Step 7: Create new unique constraint including name
    create unique_index(:saved_authentications, [:provider, :auth_type, :name],
             name: :saved_authentications_provider_auth_type_name_index
           )

    # Step 8: Add performance index for provider + name queries
    create index(:saved_authentications, [:provider, :name])
  end

  def down do
    # Remove new indexes
    drop_if_exists index(:saved_authentications, [:provider, :name])

    drop_if_exists unique_index(:saved_authentications, [:provider, :auth_type, :name],
                     name: :saved_authentications_provider_auth_type_name_index
                   )

    # Restore original unique constraint
    create unique_index(:saved_authentications, [:provider, :auth_type],
             name: :saved_authentications_provider_auth_type_index
           )

    # Remove constraints
    drop constraint(:saved_authentications, :name_length)
    drop constraint(:saved_authentications, :name_format)

    # Remove name field
    alter table(:saved_authentications) do
      remove :name
    end
  end
end
