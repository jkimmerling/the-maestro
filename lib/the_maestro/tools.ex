defmodule TheMaestro.Tools do
  @moduledoc """
  The Tools context.
  """

  import Ecto.Query, warn: false
  alias TheMaestro.Repo

  alias TheMaestro.Tools.ToolRun

  @doc """
  Returns the list of tool_runs.
  """
  def list_tool_runs, do: Repo.all(ToolRun)

  @doc "Get a single tool_run."
  def get_tool_run!(id), do: Repo.get!(ToolRun, id)

  @doc "Create a tool_run."
  def create_tool_run(attrs) do
    %ToolRun{}
    |> ToolRun.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update a tool_run."
  def update_tool_run(%ToolRun{} = tool_run, attrs) do
    tool_run
    |> ToolRun.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a tool_run."
  def delete_tool_run(%ToolRun{} = tool_run) do
    Repo.delete(tool_run)
  end

  @doc "Return a changeset for tool_run changes."
  def change_tool_run(%ToolRun{} = tool_run, attrs \\ %{}) do
    ToolRun.changeset(tool_run, attrs)
  end

  # ---- Audit helpers ----

  @doc "Log the start of a tool run with optional metadata."
  def log_start(attrs) when is_map(attrs) do
    attrs = Map.put_new(attrs, :started_at, DateTime.utc_now())
    create_tool_run(attrs)
  end

  @doc "Log the finish of a tool run; accepts a ToolRun or id and attrs."
  def log_finish(%ToolRun{} = run, attrs), do: do_finish(run, attrs)
  def log_finish(id, attrs) when is_binary(id), do: Repo.get!(ToolRun, id) |> do_finish(attrs)

  defp do_finish(%ToolRun{} = run, attrs) do
    attrs = attrs |> Map.put_new(:finished_at, DateTime.utc_now())
    update_tool_run(run, attrs)
  end

  @doc "Log an error for a tool run; creates a new record if run is nil."
  def log_error(nil, attrs) do
    attrs = attrs |> Map.put(:status, "error") |> Map.put_new(:started_at, DateTime.utc_now())
    create_tool_run(attrs)
  end

  def log_error(%ToolRun{} = run, attrs), do: log_finish(run, Map.put(attrs, :status, "error"))
  def log_error(id, attrs) when is_binary(id), do: Repo.get!(ToolRun, id) |> log_error(attrs)

  @doc "Return recent tool runs for an agent (default limit 20)."
  def latest_for_agent(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    Repo.all(from tr in ToolRun, where: tr.agent_id == ^agent_id, order_by: [desc: tr.inserted_at], limit: ^limit)
  end
end
