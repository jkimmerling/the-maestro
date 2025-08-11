defmodule TheMaestro.Agents.Agent do
  @moduledoc """
  A GenServer that represents a single AI agent conversation session.
  
  This GenServer manages the state of a conversation, including message history
  and the current processing state. It will be extended in future stories to
  implement the ReAct loop and handle LLM interactions.
  """
  
  use GenServer
  
  # Client API
  
  @doc """
  Starts a new Agent GenServer.
  
  ## Parameters
    - `opts`: Options including `:agent_id` for the unique agent identifier
  """
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    GenServer.start_link(__MODULE__, %{agent_id: agent_id}, name: via_tuple(agent_id))
  end
  
  @doc """
  Sends a message to an agent and returns a placeholder response.
  
  In future stories, this will implement the full ReAct loop.
  
  ## Parameters
    - `agent_id`: The unique identifier for the agent
    - `message`: The user's message/prompt
  """
  def send_message(agent_id, message) do
    GenServer.call(via_tuple(agent_id), {:send_message, message})
  end
  
  @doc """
  Gets the current state of an agent for inspection.
  """
  def get_state(agent_id) do
    GenServer.call(via_tuple(agent_id), :get_state)
  end
  
  # Server Callbacks
  
  @impl true
  def init(%{agent_id: agent_id}) do
    state = %{
      agent_id: agent_id,
      message_history: [],
      loop_state: :idle,
      created_at: DateTime.utc_now()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:send_message, message}, _from, state) do
    # Add user message to history
    user_message = %{
      type: :user,
      content: message,
      timestamp: DateTime.utc_now()
    }
    
    # For now, return a hardcoded response (will be replaced with ReAct loop)
    assistant_response = %{
      type: :assistant,
      content: "I received your message: \"#{message}\". This is a placeholder response.",
      timestamp: DateTime.utc_now()
    }
    
    # Update state with both messages (newest last for chronological order)
    updated_history = state.message_history ++ [user_message, assistant_response]
    updated_state = %{state | 
      message_history: updated_history,
      loop_state: :idle
    }
    
    {:reply, {:ok, assistant_response}, updated_state}
  end
  
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
  
  # Helper Functions
  
  defp via_tuple(agent_id) do
    {:via, Registry, {TheMaestro.Agents.Registry, agent_id}}
  end
end