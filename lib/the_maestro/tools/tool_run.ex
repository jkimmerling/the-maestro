defmodule TheMaestro.Tools.ToolRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tool_runs" do
    field :name, :string
    field :status, :string, default: "started"
    field :exit_code, :integer
    field :args, :map, default: %{}
    field :cwd, :string
    field :bytes_read, :integer
    field :bytes_written, :integer
    field :stdout, :string
    field :stderr, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :provider, :map, default: %{}
    field :call_request, :map, default: %{}
    field :call_response, :map, default: %{}

    belongs_to :agent, TheMaestro.Agents.Agent
    belongs_to :session, TheMaestro.Conversations.Session

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(tool_run, attrs) do
    tool_run
    |> cast(attrs, [
      :name,
      :status,
      :exit_code,
      :args,
      :cwd,
      :bytes_read,
      :bytes_written,
      :stdout,
      :stderr,
      :started_at,
      :finished_at,
      :provider,
      :call_request,
      :call_response,
      :agent_id,
      :session_id
    ])
    |> validate_required([:name, :status])
    |> validate_length(:name, min: 2, max: 80)
  end
end
