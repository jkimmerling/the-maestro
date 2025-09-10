defmodule TheMaestro.Repo.Migrations.CreateChatHistory do
  use Ecto.Migration

  def change do
    create table(:chat_history, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :turn_index, :integer
      add :actor, :string
      add :provider, :string
      add :request_headers, :map
      add :response_headers, :map
      add :combined_chat, :map
      add :edit_version, :integer
      add :thread_id, :uuid
      add :parent_thread_id, :uuid
      add :fork_from_entry_id, :uuid
      add :thread_label, :string
      add :session_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create index(:chat_history, [:session_id])
    create index(:chat_history, [:thread_id])

    create unique_index(:chat_history, [:session_id, :turn_index],
             name: :chat_history_session_turn_index
           )

    create unique_index(:chat_history, [:thread_id, :turn_index],
             name: :chat_history_thread_turn_index
           )
  end
end
