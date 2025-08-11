defmodule TheMaestro.Agents.Agent do
  @moduledoc """
  A GenServer that represents a single AI agent conversation session.

  This GenServer manages the state of a conversation, including message history
  and the current processing state. It implements a placeholder ReAct loop
  that will be extended in future stories to handle LLM interactions and tool usage.
  """

  use GenServer

  @typedoc """
  The state structure for an Agent GenServer process.

  ## Fields
    - `agent_id`: Unique identifier for this agent instance
    - `message_history`: List of messages in chronological order
    - `loop_state`: Current state of the ReAct loop (:idle, :thinking, :acting)
    - `created_at`: Timestamp when the agent was created
  """
  @type t :: %__MODULE__{
          agent_id: String.t(),
          message_history: list(message()),
          loop_state: atom(),
          created_at: DateTime.t()
        }

  @typedoc """
  A message in the conversation history.

  ## Fields
    - `type`: Either :user or :assistant
    - `content`: The text content of the message
    - `timestamp`: When the message was created
  """
  @type message :: %{
          type: :user | :assistant,
          content: String.t(),
          timestamp: DateTime.t()
        }

  defstruct [:agent_id, :message_history, :loop_state, :created_at]

  # Client API

  @doc """
  Starts a new Agent GenServer.

  ## Parameters
    - `opts`: Options including `:agent_id` for the unique agent identifier
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    GenServer.start_link(__MODULE__, %{agent_id: agent_id}, name: via_tuple(agent_id))
  end

  @doc """
  Sends a user prompt to an agent and returns a response.

  This function implements a placeholder ReAct loop that receives a prompt,
  updates the message history, and returns a hardcoded response without calling an LLM.

  ## Parameters
    - `agent_id`: The unique identifier for the agent
    - `message`: The user's message/prompt
    
  ## Returns
    - `{:ok, response}`: The agent's response message
    - `{:error, reason}`: If an error occurred
  """
  @spec send_message(String.t(), String.t()) :: {:ok, message()} | {:error, term()}
  def send_message(agent_id, message) do
    GenServer.call(via_tuple(agent_id), {:send_message, message})
  end

  @doc """
  Gets the current state of an agent for inspection.

  ## Parameters
    - `agent_id`: The unique identifier for the agent
    
  ## Returns
    The current agent state struct
  """
  @spec get_state(String.t()) :: t()
  def get_state(agent_id) do
    GenServer.call(via_tuple(agent_id), :get_state)
  end

  # Server Callbacks

  @impl true
  def init(%{agent_id: agent_id}) do
    state = %__MODULE__{
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
    updated_state = %{state | message_history: updated_history, loop_state: :idle}

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
