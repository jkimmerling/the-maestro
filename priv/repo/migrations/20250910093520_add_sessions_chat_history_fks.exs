defmodule TheMaestro.Repo.Migrations.AddSessionsChatHistoryFks do
  use Ecto.Migration

  def change do
    alter table(:chat_history) do
      modify :session_id, references(:sessions, on_delete: :nothing, type: :binary_id),
        from: :binary_id
    end

    alter table(:sessions) do
      modify :latest_chat_entry_id,
             references(:chat_history, on_delete: :nilify_all, type: :binary_id),
             from: :binary_id
    end

    # index already exists from baseline creation
  end
end
