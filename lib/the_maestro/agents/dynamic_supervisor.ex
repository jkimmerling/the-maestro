defmodule TheMaestro.Agents.DynamicSupervisor do
  @moduledoc """
  A DynamicSupervisor responsible for managing Agent GenServer processes.

  This supervisor provides fault tolerance for agent processes, automatically
  restarting them if they crash. Each agent process represents a single
  conversation session with an AI model.
  """

  use DynamicSupervisor

  @doc """
  Starts the DynamicSupervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a new Agent process under the supervisor.

  ## Parameters
    - `agent_id`: A unique identifier for the agent session
    - `opts`: Options to pass to the Agent GenServer

  ## Returns
    - `{:ok, pid}` on success
    - `{:error, reason}` on failure
  """
  def start_agent(agent_id, opts \\ []) do
    child_spec = {TheMaestro.Agents.Agent, Keyword.put(opts, :agent_id, agent_id)}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Terminates an Agent process.

  ## Parameters
    - `agent_pid`: The PID of the agent process to terminate
  """
  def terminate_agent(agent_pid) do
    DynamicSupervisor.terminate_child(__MODULE__, agent_pid)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
