defmodule TheMaestro.Prompts.EngineeringTools.CollaborationSchemas do
  @moduledoc """
  Ecto schemas for collaboration system database tables
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias TheMaestro.Repo

  # Collaboration Session Schema
  defmodule CollaborationSession do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "collaboration_sessions" do
      field :session_id, :string
      field :participants, {:array, :string}, default: []
      field :collaboration_mode, :string, default: "asynchronous"
      field :permissions, :map, default: %{}
      field :real_time_sync, :boolean, default: false
      field :change_tracking, :boolean, default: true
      field :comment_system, :boolean, default: true
      field :approval_workflow, :boolean, default: false
      field :conflict_resolution, :string, default: "manual"
      field :session_status, :string, default: "active"
      field :created_by, :string
      field :expires_at, :utc_datetime

      timestamps()
    end

    @doc false
    def changeset(session, attrs) do
      session
      |> cast(attrs, [:session_id, :participants, :collaboration_mode, :permissions, 
                     :real_time_sync, :change_tracking, :comment_system, :approval_workflow,
                     :conflict_resolution, :session_status, :created_by, :expires_at])
      |> validate_required([:session_id, :created_by])
      |> validate_inclusion(:collaboration_mode, ["asynchronous", "synchronous", "review_only"])
      |> validate_inclusion(:conflict_resolution, ["manual", "auto_merge", "last_wins"])
      |> validate_inclusion(:session_status, ["active", "paused", "completed", "archived"])
      |> unique_constraint(:session_id)
    end
  end

  # Session Change Schema
  defmodule SessionChange do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "session_changes" do
      field :change_id, :string
      field :session_id, :string
      field :user_id, :string
      field :change_type, :string
      field :content, :string
      field :position, :map
      field :metadata, :map, default: %{}
      field :parent_change_id, :string
      field :status, :string, default: "applied"

      timestamps()
    end

    @doc false
    def changeset(change, attrs) do
      change
      |> cast(attrs, [:change_id, :session_id, :user_id, :change_type, :content, 
                     :position, :metadata, :parent_change_id, :status])
      |> validate_required([:change_id, :session_id, :user_id, :change_type])
      |> validate_inclusion(:change_type, ["edit", "add", "delete", "move", "format"])
      |> validate_inclusion(:status, ["pending", "applied", "reverted", "conflicted"])
      |> unique_constraint(:change_id)
    end
  end

  # Session Comment Schema
  defmodule SessionComment do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "session_comments" do
      field :comment_id, :string
      field :session_id, :string
      field :user_id, :string
      field :content, :string
      field :position, :map
      field :comment_type, :string, default: "general"
      field :resolved, :boolean, default: false
      field :parent_comment_id, :string
      field :metadata, :map, default: %{}

      timestamps()
    end

    @doc false
    def changeset(comment, attrs) do
      comment
      |> cast(attrs, [:comment_id, :session_id, :user_id, :content, :position, 
                     :comment_type, :resolved, :parent_comment_id, :metadata])
      |> validate_required([:comment_id, :session_id, :user_id, :content])
      |> validate_inclusion(:comment_type, ["general", "suggestion", "question", "approval"])
      |> unique_constraint(:comment_id)
    end
  end

  # Approval Workflow Schema
  defmodule ApprovalWorkflow do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "approval_workflows" do
      field :workflow_id, :string
      field :session_id, :string
      field :approver_ids, {:array, :string}, default: []
      field :approval_threshold, :integer, default: 1
      field :workflow_status, :string, default: "pending"
      field :created_by, :string
      field :due_date, :utc_datetime
      field :metadata, :map, default: %{}

      timestamps()
    end

    @doc false
    def changeset(workflow, attrs) do
      workflow
      |> cast(attrs, [:workflow_id, :session_id, :approver_ids, :approval_threshold,
                     :workflow_status, :created_by, :due_date, :metadata])
      |> validate_required([:workflow_id, :session_id, :created_by])
      |> validate_inclusion(:workflow_status, ["pending", "approved", "rejected", "needs_changes"])
      |> validate_number(:approval_threshold, greater_than: 0)
      |> unique_constraint(:workflow_id)
    end
  end

  # Session Approval Schema
  defmodule SessionApproval do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "session_approvals" do
      field :approval_id, :string
      field :workflow_id, :string
      field :user_id, :string
      field :decision, :string
      field :comment, :string
      field :metadata, :map, default: %{}

      timestamps()
    end

    @doc false
    def changeset(approval, attrs) do
      approval
      |> cast(attrs, [:approval_id, :workflow_id, :user_id, :decision, :comment, :metadata])
      |> validate_required([:approval_id, :workflow_id, :user_id, :decision])
      |> validate_inclusion(:decision, ["approved", "rejected", "needs_changes"])
      |> unique_constraint(:approval_id)
    end
  end

  # Session Sync Schema
  defmodule SessionSync do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "session_syncs" do
      field :sync_id, :string
      field :session_id, :string
      field :participants_synced, {:array, :string}, default: []
      field :sync_status, :string, default: "completed"
      field :changes_synced, :integer, default: 0
      field :conflicts_detected, :integer, default: 0
      field :sync_metadata, :map, default: %{}

      timestamps()
    end

    @doc false
    def changeset(sync, attrs) do
      sync
      |> cast(attrs, [:sync_id, :session_id, :participants_synced, :sync_status,
                     :changes_synced, :conflicts_detected, :sync_metadata])
      |> validate_required([:sync_id, :session_id])
      |> validate_inclusion(:sync_status, ["pending", "in_progress", "completed", "failed"])
      |> validate_number(:changes_synced, greater_than_or_equal_to: 0)
      |> validate_number(:conflicts_detected, greater_than_or_equal_to: 0)
      |> unique_constraint(:sync_id)
    end
  end

  # Database query functions
  @doc """
  Creates a new collaboration session in the database
  """
  def create_session(attrs) do
    %CollaborationSession{}
    |> CollaborationSession.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Retrieves a collaboration session by session_id
  """
  def get_session(session_id) do
    CollaborationSession
    |> where([s], s.session_id == ^session_id)
    |> Repo.one()
    |> case do
      nil -> {:error, "Session not found"}
      session -> {:ok, session}
    end
  end

  @doc """
  Updates a collaboration session
  """
  def update_session(session, attrs) do
    session
    |> CollaborationSession.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a new session change record
  """
  def create_change(attrs) do
    %SessionChange{}
    |> SessionChange.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets changes for a session
  """
  def get_session_changes(session_id) do
    SessionChange
    |> where([c], c.session_id == ^session_id)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a new comment
  """
  def create_comment(attrs) do
    %SessionComment{}
    |> SessionComment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets comments for a session
  """
  def get_session_comments(session_id) do
    SessionComment
    |> where([c], c.session_id == ^session_id)
    |> order_by([c], c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a new approval workflow
  """
  def create_approval_workflow(attrs) do
    %ApprovalWorkflow{}
    |> ApprovalWorkflow.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets approval workflow by ID
  """
  def get_approval_workflow(workflow_id) do
    ApprovalWorkflow
    |> where([w], w.workflow_id == ^workflow_id)
    |> Repo.one()
    |> case do
      nil -> {:error, "Workflow not found"}
      workflow -> {:ok, workflow}
    end
  end

  @doc """
  Creates a new approval record
  """
  def create_approval(attrs) do
    %SessionApproval{}
    |> SessionApproval.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a new sync record
  """
  def create_sync(attrs) do
    %SessionSync{}
    |> SessionSync.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets sync records for a session
  """
  def get_session_syncs(session_id) do
    SessionSync
    |> where([s], s.session_id == ^session_id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end
end