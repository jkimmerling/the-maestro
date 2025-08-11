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
    - `llm_provider`: The LLM provider module to use
    - `auth_context`: Authentication context for the LLM provider
  """
  @type t :: %__MODULE__{
          agent_id: String.t(),
          message_history: list(message()),
          loop_state: atom(),
          created_at: DateTime.t(),
          llm_provider: module(),
          auth_context: term()
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

  defstruct [:agent_id, :message_history, :loop_state, :created_at, :llm_provider, :auth_context]

  # Client API

  @doc """
  Starts a new Agent GenServer.

  ## Parameters
    - `opts`: Options including `:agent_id` for the unique agent identifier,
              `:llm_provider` for the provider module, and `:auth_context`
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    llm_provider = Keyword.get(opts, :llm_provider, TheMaestro.Providers.Gemini)
    auth_context = Keyword.get(opts, :auth_context)

    init_args = %{
      agent_id: agent_id,
      llm_provider: llm_provider,
      auth_context: auth_context
    }

    GenServer.start_link(__MODULE__, init_args, name: via_tuple(agent_id))
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
  def init(%{agent_id: agent_id, llm_provider: llm_provider, auth_context: auth_context}) do
    # Initialize authentication if auth_context is nil
    final_auth_context =
      case auth_context do
        nil ->
          case llm_provider.initialize_auth() do
            {:ok, context} ->
              context

            {:error, reason} ->
              # Log error but don't fail initialization - will handle during message processing
              require Logger

              Logger.warning(
                "Failed to initialize LLM auth during agent startup: #{inspect(reason)}"
              )

              nil
          end

        context ->
          context
      end

    state = %__MODULE__{
      agent_id: agent_id,
      message_history: [],
      loop_state: :idle,
      created_at: DateTime.utc_now(),
      llm_provider: llm_provider,
      auth_context: final_auth_context
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    require Logger

    # Add user message to history
    user_message = %{
      type: :user,
      role: :user,
      content: message,
      timestamp: DateTime.utc_now()
    }

    # Update state to thinking mode
    thinking_state = %{
      state
      | message_history: state.message_history ++ [user_message],
        loop_state: :thinking
    }

    # Attempt to get response from LLM provider
    case get_llm_response(thinking_state, message) do
      {:ok, llm_response} ->
        assistant_message = %{
          type: :assistant,
          role: :assistant,
          content: llm_response,
          timestamp: DateTime.utc_now()
        }

        # Update state with assistant response
        final_state = %{
          thinking_state
          | message_history: thinking_state.message_history ++ [assistant_message],
            loop_state: :idle
        }

        {:reply, {:ok, assistant_message}, final_state}

      {:error, reason} ->
        Logger.error("Failed to get LLM response: #{inspect(reason)}")

        # Return error response but still update state
        error_message = %{
          type: :assistant,
          role: :assistant,
          content:
            "I'm sorry, I encountered an error processing your request. Please check your authentication configuration.",
          timestamp: DateTime.utc_now()
        }

        error_state = %{
          thinking_state
          | message_history: thinking_state.message_history ++ [error_message],
            loop_state: :idle
        }

        {:reply, {:ok, error_message}, error_state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # Helper Functions

  defp get_llm_response(state, _current_message) do
    case state.auth_context do
      nil ->
        {:error, :no_auth_context}

      auth_context ->
        # Convert message history to LLM provider format
        messages = convert_message_history_to_llm_format(state.message_history)

        # Basic completion options
        completion_opts = %{
          model: "gemini-1.5-pro",
          temperature: 0.7,
          max_tokens: 8192
        }

        # Call the LLM provider
        case state.llm_provider.complete_text(auth_context, messages, completion_opts) do
          {:ok, %{content: content}} ->
            {:ok, content}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp convert_message_history_to_llm_format(message_history) do
    Enum.map(message_history, fn message ->
      %{
        role: message.role,
        content: message.content
      }
    end)
  end

  defp via_tuple(agent_id) do
    {:via, Registry, {TheMaestro.Agents.Registry, agent_id}}
  end
end
