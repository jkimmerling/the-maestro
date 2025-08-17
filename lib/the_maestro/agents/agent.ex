defmodule TheMaestro.Agents.Agent do
  @moduledoc """
  A GenServer that represents a single AI agent conversation session.

  This GenServer manages the state of a conversation, including message history
  and the current processing state. It implements a placeholder ReAct loop
  that will be extended in future stories to handle LLM interactions and tool usage.
  """

  use GenServer

  alias TheMaestro.Models.Model

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
          auth_context: term(),
          model: Model.t() | nil
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

  defstruct [
    :agent_id,
    :message_history,
    :loop_state,
    :created_at,
    :llm_provider,
    :auth_context,
    :model
  ]

  # Client API

  @doc """
  Starts a new Agent GenServer.

  ## Parameters
    - `opts`: Options including `:agent_id` for the unique agent identifier,
              `:llm_provider` (atom or module) for the provider, `:provider_name` for named provider,
              and `:auth_context`
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)

    # Resolve LLM provider - support both module names and provider atoms
    llm_provider = resolve_llm_provider(opts)
    auth_context = Keyword.get(opts, :auth_context)
    model = Keyword.get(opts, :model)

    init_args = %{
      agent_id: agent_id,
      llm_provider: llm_provider,
      auth_context: auth_context,
      model: model
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

  @doc """
  Updates the authentication context for an agent.

  This is useful when the user's OAuth tokens are refreshed and the agent
  needs to use the updated credentials.

  ## Parameters
    - `agent_id`: The unique identifier for the agent
    - `auth_context`: The new authentication context
    
  ## Returns
    `:ok` if successful
  """
  @spec update_auth_context(String.t(), term()) :: :ok
  def update_auth_context(agent_id, auth_context) do
    GenServer.call(via_tuple(agent_id), {:update_auth_context, auth_context})
  end

  @doc """
  Saves the current agent session to the database.

  ## Parameters
    - `agent_id`: The unique identifier for the agent
    - `session_name`: Optional name for the session
    - `user_id`: Optional user ID for authenticated sessions
    
  ## Returns
    - `{:ok, conversation_session}`: Session saved successfully
    - `{:error, reason}`: If an error occurred
  """
  @spec save_session(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, TheMaestro.Sessions.ConversationSession.t()} | {:error, term()}
  def save_session(agent_id, session_name \\ nil, user_id \\ nil) do
    GenServer.call(via_tuple(agent_id), {:save_session, session_name, user_id})
  end

  @doc """
  Restores an agent session from the database.

  ## Parameters
    - `agent_id`: The unique identifier for the agent
    - `session_name`: The name of the session to restore
    
  ## Returns
    - `:ok`: Session restored successfully
    - `{:error, reason}`: If an error occurred
  """
  @spec restore_session(String.t(), String.t()) :: :ok | {:error, term()}
  def restore_session(agent_id, session_name) do
    GenServer.call(via_tuple(agent_id), {:restore_session, session_name})
  end

  @doc """
  Lists all saved sessions for an agent.

  ## Parameters
    - `agent_id`: The unique identifier for the agent
    
  ## Returns
    List of conversation session structs
  """
  @spec list_sessions(String.t()) :: [TheMaestro.Sessions.ConversationSession.t()]
  def list_sessions(agent_id) do
    TheMaestro.Sessions.list_sessions_for_agent(agent_id)
  end

  @doc """
  Lists all available LLM providers and their supported models.
  """
  @spec list_providers() :: %{atom() => %{module: module(), models: [String.t()]}}
  def list_providers do
    providers = Application.get_env(:the_maestro, :providers, %{})
    # Convert keyword list to map if needed
    if is_list(providers), do: Map.new(providers), else: providers
  end

  @doc """
  Gets the default LLM provider from configuration.
  """
  @spec get_default_provider() :: atom()
  def get_default_provider do
    case Application.get_env(:the_maestro, :llm_provider, %{}) do
      %{default: provider} -> provider
      _ -> :gemini
    end
  end

  @doc """
  Returns the via tuple for an agent with the given ID.
  This is used for process registration and lookup.
  """
  @spec via_tuple(String.t()) :: {:via, Registry, {module(), String.t()}}
  def via_tuple(agent_id) do
    {:via, Registry, {TheMaestro.Agents.Registry, agent_id}}
  end

  # Server Callbacks

  @impl true
  def init(%{
        agent_id: agent_id,
        llm_provider: llm_provider,
        auth_context: auth_context,
        model: model
      }) do
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
      auth_context: final_auth_context,
      model: model
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

    # Update state to thinking mode and broadcast status
    thinking_state = %{
      state
      | message_history: state.message_history ++ [user_message],
        loop_state: :thinking
    }

    # Broadcast that we're thinking
    broadcast_status_update(state.agent_id, :thinking)

    # Attempt to get response from LLM provider
    case get_llm_response_with_streaming(thinking_state, message) do
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

        # Broadcast completion
        broadcast_processing_complete(state.agent_id, assistant_message)

        {:reply, {:ok, assistant_message}, final_state}

      {:error, reason} ->
        Logger.error("Failed to get LLM response: #{inspect(reason)}")

        # Return error response but still update state
        error_message = %{
          type: :assistant,
          role: :assistant,
          content:
            "I'm sorry, I encountered an error processing your request. Error details: #{inspect(reason)}. Please check your authentication configuration.",
          timestamp: DateTime.utc_now()
        }

        error_state = %{
          thinking_state
          | message_history: thinking_state.message_history ++ [error_message],
            loop_state: :idle
        }

        # Broadcast completion even for errors
        broadcast_processing_complete(state.agent_id, error_message)

        {:reply, {:ok, error_message}, error_state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:update_auth_context, auth_context}, _from, state) do
    updated_state = %{state | auth_context: auth_context}
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:save_session, session_name, user_id}, _from, state) do
    require Logger

    case TheMaestro.Sessions.save_session(state, session_name, user_id) do
      {:ok, conversation_session} ->
        Logger.info(
          "Session '#{conversation_session.session_name}' saved for agent #{state.agent_id}"
        )

        {:reply, {:ok, conversation_session}, state}

      {:error, reason} ->
        Logger.error("Failed to save session for agent #{state.agent_id}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:restore_session, session_name}, _from, current_state) do
    require Logger

    case TheMaestro.Sessions.restore_session(current_state.agent_id, session_name) do
      {:ok, restored_state} ->
        Logger.info("Session '#{session_name}' restored for agent #{current_state.agent_id}")

        # Preserve the current LLM provider and auth context, but update everything else
        updated_state = %{
          restored_state
          | llm_provider: current_state.llm_provider,
            auth_context: current_state.auth_context
        }

        # Broadcast that session was restored
        broadcast_session_restored(current_state.agent_id, session_name)

        {:reply, :ok, updated_state}

      {:error, reason} ->
        Logger.error(
          "Failed to restore session '#{session_name}' for agent #{current_state.agent_id}: #{inspect(reason)}"
        )

        {:reply, {:error, reason}, current_state}
    end
  end

  # Helper Functions

  defp get_llm_response_with_streaming(state, _current_message) do
    case state.auth_context do
      nil -> {:error, :no_auth_context}
      auth_context -> perform_llm_completion_with_streaming(state, auth_context)
    end
  end

  defp perform_llm_completion_with_streaming(state, auth_context) do
    messages = convert_message_history_to_llm_format(state.message_history)
    tool_definitions = TheMaestro.Tooling.get_tool_definitions()

    completion_opts =
      build_completion_opts_with_streaming(state, tool_definitions)

    if Enum.empty?(tool_definitions) do
      execute_basic_completion_with_streaming(
        state.llm_provider,
        auth_context,
        messages,
        completion_opts
      )
    else
      execute_tool_enabled_completion_with_streaming(
        state,
        auth_context,
        messages,
        completion_opts
      )
    end
  end

  defp build_completion_opts_with_streaming(state, tool_definitions) do
    stream_callback = fn
      {:chunk, chunk} -> broadcast_stream_chunk(state.agent_id, chunk)
      :complete -> :ok
    end

    # Use the selected model from state, fall back to default if not set
    # Always expect a Model struct, convert legacy formats if needed
    model =
      case Map.get(state, :model) do
        %Model{} = model_struct -> model_struct
        legacy_model when not is_nil(legacy_model) -> Model.from_legacy(legacy_model)
        nil -> get_default_model_for_provider(state.llm_provider)
      end

    model_id = model.id

    %{
      model: model_id,
      temperature: 0.0,
      max_tokens: 8192,
      tools: tool_definitions,
      stream_callback: stream_callback
    }
  end

  defp execute_basic_completion_with_streaming(provider, auth_context, messages, completion_opts) do
    basic_opts = Map.delete(completion_opts, :tools)

    case provider.complete_text(auth_context, messages, basic_opts) do
      {:ok, %{content: content}} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_tool_enabled_completion_with_streaming(
         state,
         auth_context,
         messages,
         completion_opts
       ) do
    provider = state.llm_provider

    if function_exported?(provider, :complete_with_tools, 3) do
      handle_tool_completion_with_streaming(state, auth_context, messages, completion_opts)
    else
      execute_basic_completion_with_streaming(provider, auth_context, messages, completion_opts)
    end
  end

  defp handle_tool_completion_with_streaming(state, auth_context, messages, completion_opts) do
    case state.llm_provider.complete_with_tools(auth_context, messages, completion_opts) do
      {:ok, %{content: content, tool_calls: []}} ->
        {:ok, content}

      {:ok, %{content: content, tool_calls: [_ | _] = tool_calls}} ->
        handle_tool_calls_with_streaming(state, auth_context, messages, tool_calls, content)

      {:ok, %{tool_calls: [_ | _] = tool_calls}} ->
        handle_tool_calls_with_streaming(state, auth_context, messages, tool_calls, nil)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_tool_calls_with_streaming(
         state,
         auth_context,
         messages,
         tool_calls,
         initial_content
       ) do
    require Logger

    # Execute each tool call with status broadcasting
    tool_results =
      Enum.map(tool_calls, fn tool_call ->
        # Broadcast tool call start
        broadcast_tool_call_start(state.agent_id, tool_call)

        result = execute_tool_call(tool_call)

        # Broadcast tool call end
        broadcast_tool_call_end(state.agent_id, tool_call, result)

        result
      end)

    # Add tool call messages and results to conversation
    updated_messages = messages ++ build_tool_messages(tool_calls, tool_results, initial_content)

    # Get follow-up response from LLM with tool results (with streaming)
    stream_callback = fn
      {:chunk, chunk} -> broadcast_stream_chunk(state.agent_id, chunk)
      :complete -> :ok
    end

    # Get the model, ensuring it's a Model struct
    model =
      case Map.get(state, :model) do
        %Model{} = model_struct -> model_struct
        legacy_model when not is_nil(legacy_model) -> Model.from_legacy(legacy_model)
        nil -> get_default_model_for_provider(state.llm_provider)
      end

    completion_opts = %{
      model: model.id,
      temperature: 0.0,
      max_tokens: 8192,
      stream_callback: stream_callback
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
    require Logger
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
    require Logger
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
        format_content_result(data)

      Map.has_key?(data, "result") ->
        "Result: #{Map.get(data, "result")}"

      true ->
        inspect(data)
    end
  end

  defp format_tool_result(data), do: inspect(data)

  defp format_content_result(data) do
    content = Map.get(data, "content")
    size = Map.get(data, "size")

    if size do
      "Read #{size} bytes from file"
    else
      format_truncated_content(content)
    end
  end

  defp format_truncated_content(content) do
    truncated = String.slice(content, 0, 100)
    suffix = if String.length(content) > 100, do: "...", else: ""
    "Content: #{truncated}#{suffix}"
  end

  defp convert_message_history_to_llm_format(message_history) do
    Enum.map(message_history, fn message ->
      %{
        role: message.role,
        content: message.content
      }
    end)
  end

  # Provider Resolution

  defp resolve_llm_provider(opts) do
    cond do
      # Explicit module provided
      provider_module = Keyword.get(opts, :llm_provider) ->
        if is_atom(provider_module) and provider_module not in [:gemini, :openai, :anthropic] do
          provider_module
        else
          resolve_provider_by_name(provider_module)
        end

      # Provider name provided
      provider_name = Keyword.get(opts, :provider_name) ->
        resolve_provider_by_name(provider_name)

      true ->
        # Use default provider
        resolve_provider_by_name(get_default_provider())
    end
  end

  defp resolve_provider_by_name(provider_name) when is_atom(provider_name) do
    providers = Application.get_env(:the_maestro, :providers, %{})

    # Convert keyword list to map if needed
    providers_map = if is_list(providers), do: Map.new(providers), else: providers

    case Map.get(providers_map, provider_name) do
      %{module: module} -> module
      # fallback
      nil -> TheMaestro.Providers.Gemini
    end
  end

  defp resolve_provider_by_name(_), do: TheMaestro.Providers.Gemini

  defp get_default_model_for_provider(provider_module) do
    providers = Application.get_env(:the_maestro, :providers, %{})
    # Convert keyword list to map if needed
    providers_map = if is_list(providers), do: Map.new(providers), else: providers

    default_model_id =
      case find_provider_by_module(providers_map, provider_module) do
        {_name, %{models: [first_model | _]}} -> first_model
        # fallback
        _ -> "gemini-2.5-flash"
      end

    # Convert the default model ID to a basic Model struct
    # The provider will enrich it when needed
    provider_atom = module_to_provider_atom(provider_module)

    Model.from_legacy_string(default_model_id)
    |> Model.enrich_with_provider_info(provider_atom)
  end

  defp find_provider_by_module(providers_map, target_module) do
    Enum.find(providers_map, fn {_name, config} ->
      Map.get(config, :module) == target_module
    end)
  end

  defp module_to_provider_atom(TheMaestro.Providers.Anthropic), do: :anthropic
  defp module_to_provider_atom(TheMaestro.Providers.Gemini), do: :google
  defp module_to_provider_atom(TheMaestro.Providers.OpenAI), do: :openai
  defp module_to_provider_atom(_), do: :google

  # Streaming and status broadcasting functions

  defp broadcast_status_update(agent_id, status) do
    Phoenix.PubSub.broadcast(
      TheMaestro.PubSub,
      "agent:#{agent_id}",
      {:status_update, status}
    )
  end

  defp broadcast_stream_chunk(agent_id, chunk) do
    Phoenix.PubSub.broadcast(
      TheMaestro.PubSub,
      "agent:#{agent_id}",
      {:stream_chunk, chunk}
    )
  end

  defp broadcast_tool_call_start(agent_id, tool_call) do
    Phoenix.PubSub.broadcast(
      TheMaestro.PubSub,
      "agent:#{agent_id}",
      {:tool_call_start,
       %{
         name: Map.get(tool_call, "name"),
         arguments: Map.get(tool_call, "arguments", %{})
       }}
    )
  end

  defp broadcast_tool_call_end(agent_id, tool_call, result) do
    Phoenix.PubSub.broadcast(
      TheMaestro.PubSub,
      "agent:#{agent_id}",
      {:tool_call_end,
       %{
         name: Map.get(tool_call, "name"),
         result: result
       }}
    )
  end

  defp broadcast_processing_complete(agent_id, final_response) do
    Phoenix.PubSub.broadcast(
      TheMaestro.PubSub,
      "agent:#{agent_id}",
      {:processing_complete, final_response}
    )
  end

  defp broadcast_session_restored(agent_id, session_name) do
    Phoenix.PubSub.broadcast(
      TheMaestro.PubSub,
      "agent:#{agent_id}",
      {:session_restored, session_name}
    )
  end
end
