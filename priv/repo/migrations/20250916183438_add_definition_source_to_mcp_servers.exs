defmodule TheMaestro.Repo.Migrations.AddDefinitionSourceToMcpServers do
  use Ecto.Migration

  def change do
    alter table(:mcp_servers) do
      add :definition_source, :string, null: false, default: "manual"
    end
  end
end
