defmodule TheMaestro.Repo.Migrations.DropAgentsAndAgentFk do
  use Ecto.Migration

  def up do
    # Drop sessions.agent_id and its index/constraints
    execute("ALTER TABLE sessions DROP COLUMN IF EXISTS agent_id")

    # Drop agents table with CASCADE to remove dependent FKs
    execute("DROP TABLE IF EXISTS agents CASCADE")
  end

  def down do
    # Irreversible in this context (would require full schema)
    :ok
  end
end
