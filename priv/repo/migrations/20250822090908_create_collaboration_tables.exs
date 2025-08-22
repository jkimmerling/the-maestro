defmodule TheMaestro.Repo.Migrations.CreateCollaborationTables do
  use Ecto.Migration

  def change do
    # Collaboration Sessions
    create table(:collaboration_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string, null: false
      add :participants, {:array, :string}, default: []
      add :collaboration_mode, :string, default: "asynchronous" # asynchronous, synchronous, review_only
      add :permissions, :map, default: %{}
      add :real_time_sync, :boolean, default: false
      add :change_tracking, :boolean, default: true
      add :comment_system, :boolean, default: true
      add :approval_workflow, :boolean, default: false
      add :conflict_resolution, :string, default: "manual" # manual, auto_merge, last_wins
      add :session_status, :string, default: "active" # active, paused, completed, archived
      add :created_by, :string, null: false
      add :expires_at, :utc_datetime

      timestamps()
    end

    # Session Changes (track all changes made in a session)
    create table(:session_changes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :change_id, :string, null: false
      add :session_id, :string, null: false
      add :user_id, :string, null: false
      add :change_type, :string, null: false # edit, add, delete, move, format
      add :content, :text
      add :position, :map # {line: 5, column: 10} or similar
      add :metadata, :map, default: %{}
      add :parent_change_id, :string # for linked changes
      add :status, :string, default: "applied" # pending, applied, reverted, conflicted

      timestamps()
    end

    # Session Comments
    create table(:session_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :comment_id, :string, null: false
      add :session_id, :string, null: false
      add :user_id, :string, null: false
      add :content, :text, null: false
      add :position, :map # reference to specific part of prompt
      add :comment_type, :string, default: "general" # general, suggestion, question, approval
      add :resolved, :boolean, default: false
      add :parent_comment_id, :string # for threaded comments
      add :metadata, :map, default: %{}

      timestamps()
    end

    # Approval Workflows
    create table(:approval_workflows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workflow_id, :string, null: false
      add :session_id, :string, null: false
      add :approver_ids, {:array, :string}, default: []
      add :approval_threshold, :integer, default: 1 # number of approvals needed
      add :workflow_status, :string, default: "pending" # pending, approved, rejected, needs_changes
      add :created_by, :string, null: false
      add :due_date, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps()
    end

    # Individual Approvals
    create table(:session_approvals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :approval_id, :string, null: false
      add :workflow_id, :string, null: false
      add :user_id, :string, null: false
      add :decision, :string, null: false # approved, rejected, needs_changes
      add :comment, :text
      add :metadata, :map, default: %{}

      timestamps()
    end

    # Session Synchronization Records
    create table(:session_syncs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sync_id, :string, null: false
      add :session_id, :string, null: false
      add :participants_synced, {:array, :string}, default: []
      add :sync_status, :string, default: "completed" # pending, in_progress, completed, failed
      add :changes_synced, :integer, default: 0
      add :conflicts_detected, :integer, default: 0
      add :sync_metadata, :map, default: %{}

      timestamps()
    end

    # Create indexes for performance
    create unique_index(:collaboration_sessions, [:session_id])
    create index(:collaboration_sessions, [:created_by])
    create index(:collaboration_sessions, [:session_status])
    create index(:collaboration_sessions, [:expires_at])

    create index(:session_changes, [:session_id])
    create index(:session_changes, [:user_id])
    create index(:session_changes, [:change_type])
    create index(:session_changes, [:status])
    create unique_index(:session_changes, [:change_id])

    create index(:session_comments, [:session_id])
    create index(:session_comments, [:user_id])
    create index(:session_comments, [:resolved])
    create unique_index(:session_comments, [:comment_id])

    create index(:approval_workflows, [:session_id])
    create index(:approval_workflows, [:workflow_status])
    create unique_index(:approval_workflows, [:workflow_id])

    create index(:session_approvals, [:workflow_id])
    create index(:session_approvals, [:user_id])
    create index(:session_approvals, [:decision])
    create unique_index(:session_approvals, [:approval_id])

    create index(:session_syncs, [:session_id])
    create index(:session_syncs, [:sync_status])
    create unique_index(:session_syncs, [:sync_id])
  end
end