defmodule TheMaestro.Repo.Migrations.CreateSessionMcpServers do
  use Ecto.Migration

  def up do
    execute("DROP TABLE IF EXISTS session_mcp_servers")

    create table(:session_mcp_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :alias, :string
      add :attached_at, :utc_datetime, null: false, default: fragment("timezone('utc', now())")
      add :metadata, :map, null: false, default: %{}

      add :session_id,
          references(:sessions, on_delete: :delete_all, type: :binary_id),
          null: false

      add :mcp_server_id,
          references(:mcp_servers, on_delete: :delete_all, type: :binary_id),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:session_mcp_servers, [:session_id])
    create index(:session_mcp_servers, [:mcp_server_id])
    create unique_index(:session_mcp_servers, [:session_id, :mcp_server_id])
  end

  def down do
    drop table(:session_mcp_servers)
  end
end
