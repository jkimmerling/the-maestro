defmodule TheMaestro.Repo.Migrations.NilifyFkAuthAgentInSessionsAndAgents do
  use Ecto.Migration

  def change do
    # Agents.auth_id: allow NULL and on_delete: :nilify_all
    drop_if_exists constraint(:agents, :agents_auth_id_fkey)

    alter table(:agents) do
      modify :auth_id, references(:saved_authentications, on_delete: :nilify_all), null: true
    end

    # Sessions.agent_id: allow NULL and on_delete: :nilify_all
    drop_if_exists constraint(:sessions, :sessions_agent_id_fkey)

    alter table(:sessions) do
      modify :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all), null: true
    end
  end
end
