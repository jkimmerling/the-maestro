defmodule TheMaestro.Repo.Migrations.AddToolRuntimeToSessions do
  use Ecto.Migration

  def change do
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'sessions' AND column_name = 'tool_runtime'
      ) THEN
        ALTER TABLE sessions ADD COLUMN tool_runtime varchar NOT NULL DEFAULT 'local';
      END IF;
    END$$;
    """

    # Validation is enforced at changeset level to avoid idempotency issues
  end
end
