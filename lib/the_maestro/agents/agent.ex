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

        # Get available tool definitions
        tool_definitions = TheMaestro.Tooling.get_tool_definitions()

        # Tool-enabled completion options
        completion_opts = %{
          model: "gemini-1.5-pro",
          temperature: 0.7,
          max_tokens: 8192,
          tools: tool_definitions
        }

        # Try tool-enabled completion first if tools are available
        case {length(tool_definitions), state.llm_provider} do
          {0, _} ->
            # No tools available, use basic completion
            basic_completion_opts = Map.delete(completion_opts, :tools)

            case state.llm_provider.complete_text(auth_context, messages, basic_completion_opts) do
              {:ok, %{content: content}} ->
                {:ok, content}

              {:error, reason} ->
                {:error, reason}
            end

          {_, provider} ->
            # Tools available, try tool-enabled completion
            if function_exported?(provider, :complete_with_tools, 3) do
              case provider.complete_with_tools(auth_context, messages, completion_opts) do
                {:ok, %{content: content, tool_calls: []}} ->
                  # No tools called, return content
                  {:ok, content}

                {:ok, %{content: content, tool_calls: tool_calls}} when length(tool_calls) > 0 ->
                  # Tools were called, execute them and get follow-up response
                  handle_tool_calls(state, auth_context, messages, tool_calls, content)

                {:ok, %{tool_calls: tool_calls}} when length(tool_calls) > 0 ->
                  # Only tool calls, no content
                  handle_tool_calls(state, auth_context, messages, tool_calls, nil)

                {:error, reason} ->
                  {:error, reason}
              end
            else
              # Provider doesn't support tool completion, fallback to basic
              basic_completion_opts = Map.delete(completion_opts, :tools)

              case provider.complete_text(auth_context, messages, basic_completion_opts) do
                {:ok, %{content: content}} ->
                  {:ok, content}

                {:error, reason} ->
                  {:error, reason}
              end
            end
        end
    end
  end

  defp handle_tool_calls(state, auth_context, messages, tool_calls, initial_content) do
    require Logger

    # Execute each tool call
    tool_results =
      Enum.map(tool_calls, fn tool_call ->
        execute_tool_call(tool_call)
      end)

    # Add tool call messages and results to conversation
    updated_messages = messages ++ build_tool_messages(tool_calls, tool_results, initial_content)

    # Get follow-up response from LLM with tool results
    completion_opts = %{
      model: "gemini-1.5-pro",
      temperature: 0.7,
      max_tokens: 8192
    }

    case state.llm_provider.complete_text(auth_context, updated_messages, completion_opts) do
      {:ok, %{content: content}} ->
        # Return both the tool usage summary and the final response
        final_content = format_tool_response(tool_calls, tool_results, content)
        {:ok, final_content}

      {:error, reason} ->
        Logger.error("Failed to get follow-up response after tool calls: #{inspect(reason)}")
        # Return tool results even if follow-up fails
        tool_summary = format_tool_results_only(tool_calls, tool_results)
        {:ok, tool_summary}
    end
  end

  defp execute_tool_call(%{"name" => tool_name, "arguments" => arguments}) do
    Logger.info("Executing tool: #{tool_name} with arguments: #{inspect(arguments)}")

    case TheMaestro.Tooling.execute_tool(tool_name, arguments) do
      {:ok, result} ->
        Logger.info("Tool #{tool_name} executed successfully")
        {:ok, result}

      {:error, reason} ->
        Logger.warning("Tool #{tool_name} failed: #{reason}")
        {:error, reason}
    end
  end

  defp execute_tool_call(invalid_tool_call) do
    Logger.error("Invalid tool call format: #{inspect(invalid_tool_call)}")
    {:error, "Invalid tool call format"}
  end

  defp build_tool_messages(tool_calls, tool_results, initial_content) do
    # Add assistant message with tool calls if there was initial content
    assistant_msg =
      if initial_content do
        [%{role: :assistant, content: initial_content}]
      else
        []
      end

    # Add tool result messages
    tool_messages =
      Enum.zip(tool_calls, tool_results)
      |> Enum.map(fn {tool_call, result} ->
        result_content =
          case result do
            {:ok, data} -> Jason.encode!(data)
            {:error, reason} -> "Error: #{reason}"
          end

        %{
          role: :tool,
          content: result_content,
          tool_call_id: Map.get(tool_call, "id", "unknown")
        }
      end)

    assistant_msg ++ tool_messages
  end

  defp format_tool_response(tool_calls, tool_results, final_content) do
    tool_summary =
      Enum.zip(tool_calls, tool_results)
      |> Enum.map(fn {tool_call, result} ->
        tool_name = Map.get(tool_call, "name", "unknown")

        case result do
          {:ok, data} ->
            "✅ **#{tool_name}**: #{format_tool_result(data)}"

          {:error, reason} ->
            "❌ **#{tool_name}**: #{reason}"
        end
      end)
      |> Enum.join("\n")

    "#{tool_summary}\n\n#{final_content}"
  end

  defp format_tool_results_only(tool_calls, tool_results) do
    Enum.zip(tool_calls, tool_results)
    |> Enum.map(fn {tool_call, result} ->
      tool_name = Map.get(tool_call, "name", "unknown")

      case result do
        {:ok, data} ->
          "✅ **#{tool_name}**: #{format_tool_result(data)}"

        {:error, reason} ->
          "❌ **#{tool_name}**: #{reason}"
      end
    end)
    |> Enum.join("\n")
  end

  defp format_tool_result(data) when is_map(data) do
    # Format based on common tool result patterns
    cond do
      Map.has_key?(data, "content") ->
        content = Map.get(data, "content")
        size = Map.get(data, "size")

        if size do
          "Read #{size} bytes from file"
        else
          "Content: #{String.slice(content, 0, 100)}#{if String.length(content) > 100, do: "...", else: ""}"
        end

      Map.has_key?(data, "result") ->
        "Result: #{Map.get(data, "result")}"

      true ->
        inspect(data)
    end
  end

  defp format_tool_result(data), do: inspect(data)

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
