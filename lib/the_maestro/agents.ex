defmodule TheMaestro.Agents do
  @moduledoc """
  The Agents context provides the public API for managing AI agent processes.

  This module encapsulates all agent-related functionality and provides
  a clean interface for starting, communicating with, and managing
  agent processes through the DynamicSupervisor.
  """

  alias TheMaestro.Agents.{DynamicSupervisor, Agent}

  @doc """
  Starts a new agent process with the given ID.

  ## Examples

      iex> TheMaestro.Agents.start_agent("user_123")
      {:ok, #PID<0.123.0>}

  """
  def start_agent(agent_id, opts \\ []) do
    DynamicSupervisor.start_agent(agent_id, opts)
  end

  @doc """
  Sends a message to an agent and receives a response.

  ## Examples

      iex> TheMaestro.Agents.send_message("user_123", "Hello!")
      {:ok, %{type: :assistant, content: "I received your message...", timestamp: ~U[...]}}

  """
  def send_message(agent_id, message) do
    Agent.send_message(agent_id, message)
  end

  @doc """
  Gets the current state of an agent for inspection.
  """
  def get_agent_state(agent_id) do
    Agent.get_state(agent_id)
  end

  @doc """
  Terminates an agent process.
  """
  def terminate_agent(agent_pid) do
    DynamicSupervisor.terminate_agent(agent_pid)
  end

  @doc """
  Finds an existing agent process by ID, or starts a new one if it doesn't exist.

  This function is useful for ensuring an agent exists before sending messages.
  """
  def find_or_start_agent(agent_id, opts \\ []) do
    case Registry.lookup(TheMaestro.Agents.Registry, agent_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> start_agent(agent_id, opts)
    end
  end
end
