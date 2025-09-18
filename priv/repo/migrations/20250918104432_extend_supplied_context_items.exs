defmodule TheMaestro.Repo.Migrations.ExtendSuppliedContextItems do
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    drop_if_exists(
      index(:supplied_context_items, [:type, :name],
        name: "supplied_context_items_type_name_index"
      )
    )

    rename(table(:supplied_context_items), :tags, to: :labels)

    execute("UPDATE supplied_context_items SET labels = '{}'::jsonb WHERE labels IS NULL")
    execute("UPDATE supplied_context_items SET metadata = '{}'::jsonb WHERE metadata IS NULL")

    alter table(:supplied_context_items) do
      modify :labels, :map, null: false, default: fragment("'{}'::jsonb")
      modify :metadata, :map, null: false, default: fragment("'{}'::jsonb")

      add :provider, :string, null: false, default: "shared"
      add :render_format, :string, null: false, default: "text"
      add :position, :integer, null: false, default: 0
      add :is_default, :boolean, null: false, default: false
      add :immutable, :boolean, null: false, default: false
      add :source_ref, :string
      add :family_id, :binary_id
      add :editor, :string
      add :change_note, :text
    end

    execute("""
    UPDATE supplied_context_items
    SET provider = 'shared'
    WHERE provider IS NULL OR provider = ''
    """)

    execute("""
    UPDATE supplied_context_items
    SET family_id = id
    WHERE family_id IS NULL
    """)

    alter table(:supplied_context_items) do
      modify :family_id, :binary_id, null: false
    end

    execute("""
    WITH ranked AS (
      SELECT id,
             ROW_NUMBER() OVER (PARTITION BY type ORDER BY inserted_at, id) - 1 AS rn
      FROM supplied_context_items
    )
    UPDATE supplied_context_items AS sci
    SET position = ranked.rn
    FROM ranked
    WHERE ranked.id = sci.id
    """)

    create index(:supplied_context_items, [:provider, :type, :position],
             name: "supplied_context_items_provider_type_position_index"
           )

    create index(:supplied_context_items, [:family_id],
             name: "supplied_context_items_family_index"
           )

    create unique_index(:supplied_context_items, [:family_id, :version],
             name: "supplied_context_items_family_version_index"
           )

    create unique_index(:supplied_context_items, [:type, :provider, :name, :version],
             name: "supplied_context_items_type_provider_name_version_index"
           )
  end

  def down do
    drop_if_exists(
      index(:supplied_context_items, [:provider, :type, :position],
        name: "supplied_context_items_provider_type_position_index"
      )
    )

    drop_if_exists(
      index(:supplied_context_items, [:family_id], name: "supplied_context_items_family_index")
    )

    drop_if_exists(
      index(:supplied_context_items, [:family_id, :version],
        name: "supplied_context_items_family_version_index"
      )
    )

    drop_if_exists(
      index(:supplied_context_items, [:type, :provider, :name, :version],
        name: "supplied_context_items_type_provider_name_version_index"
      )
    )

    alter table(:supplied_context_items) do
      remove :change_note
      remove :editor
      remove :family_id
      remove :source_ref
      remove :immutable
      remove :is_default
      remove :position
      remove :render_format
      remove :provider
      modify :metadata, :map, default: nil, null: true
      modify :labels, :map, default: nil, null: true
    end

    execute("UPDATE supplied_context_items SET metadata = NULL WHERE metadata = '{}'::jsonb")
    execute("UPDATE supplied_context_items SET labels = NULL WHERE labels = '{}'::jsonb")

    rename(table(:supplied_context_items), :labels, to: :tags)

    create unique_index(:supplied_context_items, [:type, :name],
             name: :supplied_context_items_type_name_index
           )
  end
end
