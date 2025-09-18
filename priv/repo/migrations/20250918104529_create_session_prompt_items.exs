defmodule TheMaestro.Repo.Migrations.CreateSessionPromptItems do
  use Ecto.Migration

  def change do
    create table(:session_prompt_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :supplied_context_item_id,
          references(:supplied_context_items, type: :binary_id, on_delete: :delete_all),
          null: false

      add :provider, :string, null: false
      add :position, :integer, null: false, default: 0
      add :enabled, :boolean, null: false, default: true
      add :overrides, :map, null: false, default: fragment("'{}'::jsonb")

      timestamps(type: :utc_datetime)
    end

    create index(:session_prompt_items, [:session_id])
    create index(:session_prompt_items, [:supplied_context_item_id])

    create unique_index(:session_prompt_items, [:session_id, :provider, :position],
             name: "session_prompt_items_session_provider_position_index"
           )

    create unique_index(:session_prompt_items, [:session_id, :supplied_context_item_id],
             name: "session_prompt_items_session_prompt_unique_index"
           )
  end
end
