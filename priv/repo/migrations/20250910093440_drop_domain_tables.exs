defmodule TheMaestro.Repo.Migrations.DropDomainTables do
  use Ecto.Migration

  def change do
    # Drop domain tables if they already exist (do not touch Oban tables)
    # Drop child references first to avoid FK constraint errors
    drop_if_exists table(:sessions)
    drop_if_exists table(:chat_history)
    drop_if_exists table(:saved_authentications)
    drop_if_exists table(:personas)
    drop_if_exists table(:base_system_prompts)
    drop_if_exists table(:agents)
  end
end
