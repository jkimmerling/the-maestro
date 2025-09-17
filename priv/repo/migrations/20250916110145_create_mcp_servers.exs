defmodule TheMaestro.Repo.Migrations.CreateMcpServers do
  use Ecto.Migration

  def up do
    execute("DROP TABLE IF EXISTS session_mcp_bindings")
    execute("DROP TABLE IF EXISTS mcp_servers CASCADE")

    create table(:mcp_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :display_name, :string, null: false
      add :description, :text
      add :transport, :string, null: false
      add :url, :text
      add :command, :text
      add :args, {:array, :string}, null: false, default: []
      add :headers, :map, null: false, default: %{}
      add :env, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :tags, {:array, :string}, null: false, default: []
      add :auth_token, :text
      add :is_enabled, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:mcp_servers, [:name])
    create index(:mcp_servers, [:is_enabled])
  end

  def down do
    drop table(:mcp_servers)
  end
end
