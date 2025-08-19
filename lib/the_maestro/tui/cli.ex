defmodule TheMaestro.TUI.CLI do
  @moduledoc """
  Terminal User Interface (TUI) for The Maestro AI agent.

  This module provides a terminal-based interface as an alternative "head" 
  for interacting with the core agent, providing a feature-complete CLI experience.

  Uses pure Elixir with ANSI escape codes for cross-platform Mac/Linux support.
  """

  alias TheMaestro.Agents.{Agent, DynamicSupervisor}
  alias TheMaestro.Models.Model
  alias TheMaestro.TUI.{AuthFlow, ModelSelection, ProviderSelection}
  alias TheMaestro.MCP.Registry

  @doc """
  Main entry point for the escript executable.
  """
  def main(args \\ []) do
    # Set environment variable to prevent Phoenix startup
    System.put_env("RUNNING_AS_ESCRIPT", "true")

    # Parse command line arguments (future enhancement)
    _parsed_args = parse_args(args)

    # Handle provider and model selection flow
    case handle_provider_and_model_selection() do
      {:ok, {provider, model, auth_context}} ->
        # Initialize the TUI with provider, model, and auth context
        initialize_tui({provider, model, auth_context})

        # Start the main loop
        run_tui()

      {:error, reason} ->
        IO.puts([IO.ANSI.red(), "Setup failed: #{reason}", IO.ANSI.reset()])
        System.halt(1)
    end
  end

  defp initialize_tui({provider, model, auth_context}) do
    # Clear screen and hide cursor
    IO.write([
      IO.ANSI.clear(),
      IO.ANSI.home(),
      # Hide cursor ANSI escape code
      "\e[?25l"
    ])

    # Set up signal handlers for clean exit
    Process.flag(:trap_exit, true)

    # Install SIGINT (Ctrl-C) handler
    # Use a more compatible approach for signal handling
    parent = self()

    spawn_link(fn ->
      Process.register(self(), :signal_handler)
      signal_handler(parent)
    end)

    # Build welcome message based on provider and model selection
    provider_name = get_provider_name(provider)
    model_info = ModelSelection.get_model_info(model)

    model_display =
      if model_info do
        model_info.name
      else
        # Extract model name from Model struct or fallback to string
        case model do
          %Model{name: name} when not is_nil(name) -> name
          %Model{id: id} -> id
          model_id when is_binary(model_id) -> model_id
          _ -> inspect(model)
        end
      end

    auth_type =
      case auth_context.type do
        :api_key -> "API Key"
        :oauth -> "OAuth"
        :service_account -> "Service Account"
        _ -> "Unknown"
      end

    welcome_messages = [
      %{type: :system, content: "Welcome to The Maestro TUI!"},
      %{type: :system, content: "✓ Provider: #{provider_name}"},
      %{type: :system, content: "✓ Model: #{model_display}"},
      %{type: :system, content: "✓ Authentication: #{auth_type}"},
      %{type: :system, content: ""},
      %{type: :system, content: "Type your message and press Enter to chat with the agent."},
      %{type: :system, content: "Press Ctrl-C or 'q' to exit."}
    ]

    # Initial state with MCP integration
    initial_state = %{
      conversation_history: welcome_messages,
      current_input: "",
      provider: provider,
      model: model,
      auth_context: auth_context,
      status_message: "",
      streaming_buffer: "",
      mcp_servers: get_mcp_server_status(),
      last_mcp_tool_call: nil,
      show_mcp_panel: false
    }

    # Store state in process dictionary for simple state management
    Process.put(:tui_state, initial_state)
    # Also store configuration separately for agent creation
    Process.put(:tui_provider, provider)
    Process.put(:tui_model, model)
    Process.put(:tui_auth_context, auth_context)
  end

  defp run_tui do
    state = Process.get(:tui_state)

    # Check for messages (including PubSub messages and shutdown)
    receive do
      :shutdown ->
        cleanup_and_exit()

      # Handle agent status messages
      {:status_update, status} ->
        new_state = handle_status_update(state, status)
        Process.put(:tui_state, new_state)
        run_tui()

      {:tool_call_start, tool_info} ->
        new_state = handle_tool_call_start(state, tool_info)
        Process.put(:tui_state, new_state)
        run_tui()

      {:tool_call_end, tool_result} ->
        new_state = handle_tool_call_end(state, tool_result)
        Process.put(:tui_state, new_state)
        run_tui()

      {:stream_chunk, chunk} ->
        new_state = handle_stream_chunk(state, chunk)
        Process.put(:tui_state, new_state)
        run_tui()

      {:processing_complete, final_response} ->
        new_state = handle_processing_complete(state, final_response)
        Process.put(:tui_state, new_state)
        run_tui()
    after
      # Small timeout to allow for input processing
      100 -> :ok
    end

    # Render the interface
    render_interface(state)

    # Handle input
    case get_input() do
      {:quit} ->
        cleanup_and_exit()

      {:input, text} ->
        new_state = handle_user_input(state, text)
        Process.put(:tui_state, new_state)
        run_tui()

      {:show_mcp_panel} ->
        new_state = %{state | show_mcp_panel: !state.show_mcp_panel}
        Process.put(:tui_state, new_state)
        run_tui()

      {:show_mcp_status} ->
        show_mcp_status_info(state)
        run_tui()

      {:refresh_mcp} ->
        new_state = %{state | mcp_servers: get_mcp_server_status()}
        Process.put(:tui_state, new_state)
        run_tui()

      {:show_help} ->
        show_tui_help()
        run_tui()

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        cleanup_and_exit()
    end
  end

  defp render_interface(state) do
    # Get terminal dimensions
    {width, height} = get_terminal_size()

    # Clear screen and move to top
    IO.write([IO.ANSI.clear(), IO.ANSI.home()])

    # Render header
    header = "╔" <> String.duplicate("═", width - 2) <> "╗"
    title_line = "║" <> center_text("The Maestro TUI", width - 2) <> "║"
    separator = "╠" <> String.duplicate("═", width - 2) <> "╣"

    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), header])
    IO.puts([IO.ANSI.bright(), IO.ANSI.white(), title_line])
    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), separator, IO.ANSI.reset()])

    # Calculate areas
    # Leave space for header, status line, input, and borders
    conversation_height = height - 10

    # Render conversation history
    IO.puts([IO.ANSI.bright(), "Conversation History:", IO.ANSI.reset()])
    render_conversation_history(state.conversation_history, conversation_height, width)

    # Render status line
    status_separator = "╠" <> String.duplicate("═", width - 2) <> "╣"
    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), status_separator, IO.ANSI.reset()])
    render_status_line(state, width)

    # Render input area
    input_separator = "╠" <> String.duplicate("═", width - 2) <> "╣"
    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), input_separator, IO.ANSI.reset()])

    IO.puts([IO.ANSI.bright(), "Input: ", IO.ANSI.reset(), state.current_input])

    # Show MCP panel if enabled
    if state.show_mcp_panel do
      render_mcp_panel(state.mcp_servers, width)
    end

    IO.puts([
      IO.ANSI.faint(),
      "Commands: 'mcp' (toggle servers), 'help', 'q' (quit)",
      IO.ANSI.reset()
    ])

    # Bottom border
    footer = "╚" <> String.duplicate("═", width - 2) <> "╝"
    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), footer, IO.ANSI.reset()])
  end

  defp render_conversation_history(history, max_lines, width) do
    # Take the most recent messages that fit
    messages =
      history
      |> Enum.take(-max_lines)
      |> Enum.with_index()

    Enum.each(messages, fn {message, _index} ->
      color = message_color(message.type)
      type_str = format_message_type(message.type)
      content = truncate_text(message.content, width - 12)

      IO.puts([color, "[#{type_str}] ", IO.ANSI.reset(), content])
    end)

    # Fill remaining lines with empty space
    used_lines = length(messages)
    remaining_lines = max_lines - used_lines

    Enum.each(1..remaining_lines, fn _ ->
      IO.puts("")
    end)
  end

  defp get_input do
    # Read line from stdin
    case IO.gets("") do
      :eof ->
        {:quit}

      {:error, reason} ->
        {:error, reason}

      line when is_binary(line) ->
        trimmed = String.trim(line)

        case trimmed do
          "q" -> {:quit}
          "mcp" -> {:show_mcp_panel}
          "mcp status" -> {:show_mcp_status}
          "mcp refresh" -> {:refresh_mcp}
          "help" -> {:show_help}
          "" -> {:input, ""}
          text -> {:input, text}
        end
    end
  rescue
    _ -> {:quit}
  catch
    :exit, _ -> {:quit}
  end

  defp handle_user_input(state, "") do
    state
  end

  defp handle_user_input(state, input) do
    # Add user message to history immediately
    user_message = %{type: :user, content: input}
    temp_history = state.conversation_history ++ [user_message]
    temp_state = %{state | conversation_history: temp_history, current_input: ""}

    # Store temporary state and render it
    Process.put(:tui_state, temp_state)

    # Get agent response (this will trigger PubSub messages)
    case get_agent_response(input, temp_state) do
      {:ok, response} ->
        agent_message = %{type: :agent, content: response}
        final_history = limit_conversation_history(temp_history ++ [agent_message])

        %{
          temp_state
          | conversation_history: final_history,
            status_message: "",
            streaming_buffer: ""
        }

      {:error, reason} ->
        error_message = %{type: :system, content: "Error: #{reason}"}
        final_history = limit_conversation_history(temp_history ++ [error_message])

        %{
          temp_state
          | conversation_history: final_history,
            status_message: "",
            streaming_buffer: ""
        }
    end
  end

  defp get_agent_response(input, _state) do
    # Get or create an agent for this TUI session
    agent_id = get_session_agent_id()

    case ensure_agent_exists(agent_id) do
      {:ok, _pid} ->
        # Subscribe to the agent's PubSub messages for real-time updates
        subscribe_to_agent_messages(agent_id)

        # Send message to agent and get response
        case Agent.send_message(agent_id, input) do
          {:ok, message} ->
            {:ok, message.content}

          {:error, reason} ->
            {:error, "Failed to get agent response: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to start agent: #{inspect(reason)}"}
    end
  end

  defp get_session_agent_id do
    # Create a unique agent ID based on provider, model, and auth context
    provider = Process.get(:tui_provider)
    model = Process.get(:tui_model)
    auth_context = Process.get(:tui_auth_context)

    # Extract model ID from Model struct or string
    model_id =
      case model do
        %Model{id: id} -> id
        model_id when is_binary(model_id) -> model_id
        _ -> "unknown"
      end

    # Create a unique identifier based on provider, model, and auth
    base_string =
      case auth_context.type do
        :api_key ->
          api_key = get_in(auth_context, [:credentials, :api_key]) || "default"
          "#{provider}-#{model_id}-apikey-#{api_key}"

        :oauth ->
          user_email = get_in(auth_context, [:credentials, :user_email]) || "oauth_user"
          "#{provider}-#{model_id}-oauth-#{user_email}"

        :service_account ->
          "#{provider}-#{model_id}-service"

        _ ->
          # For anonymous or unknown auth types
          case Process.get(:tui_agent_id) do
            nil ->
              agent_id =
                "#{provider}-#{model_id}-anon-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

              Process.put(:tui_agent_id, agent_id)
              agent_id

            existing_id ->
              existing_id
          end
      end

    # Hash the base string to create a consistent agent ID
    :crypto.hash(:sha256, base_string) |> Base.encode16(case: :lower) |> binary_part(0, 16)
  end

  defp ensure_agent_exists(agent_id) do
    case GenServer.whereis(Agent.via_tuple(agent_id)) do
      nil ->
        # Agent doesn't exist, start it with selected provider and auth context
        provider = Process.get(:tui_provider)
        model = Process.get(:tui_model)
        auth_context = Process.get(:tui_auth_context)

        # Get the provider module
        provider_module = get_provider_module(provider)

        DynamicSupervisor.start_agent(
          agent_id,
          llm_provider: provider_module,
          model: model,
          auth_context: auth_context
        )

      pid when is_pid(pid) ->
        # Agent already exists
        {:ok, pid}
    end
  end

  defp get_provider_module(:anthropic), do: TheMaestro.Providers.Anthropic
  defp get_provider_module(:google), do: TheMaestro.Providers.Gemini
  defp get_provider_module(:openai), do: TheMaestro.Providers.OpenAI
  defp get_provider_module(provider), do: provider

  defp get_provider_name(:anthropic), do: "Claude (Anthropic)"
  defp get_provider_name(:google), do: "Gemini (Google)"
  defp get_provider_name(:openai), do: "ChatGPT (OpenAI)"
  defp get_provider_name(provider), do: String.capitalize(to_string(provider))

  defp signal_handler(parent) do
    receive do
      {:EXIT, _pid, _reason} ->
        send(parent, :shutdown)

      :shutdown ->
        send(parent, :shutdown)

      _ ->
        signal_handler(parent)
    end
  end

  defp cleanup_and_exit do
    # Show cursor and clear screen
    IO.write([
      # Show cursor ANSI escape code
      "\e[?25h",
      IO.ANSI.clear(),
      IO.ANSI.home()
    ])

    IO.puts([IO.ANSI.green(), "Thank you for using The Maestro TUI!", IO.ANSI.reset()])
    System.halt(0)
  end

  # PubSub subscription and message handling functions

  defp subscribe_to_agent_messages(agent_id) do
    Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agent:#{agent_id}")
  end

  defp handle_status_update(state, :thinking) do
    %{state | status_message: "🤔 Thinking..."}
  end

  defp handle_status_update(state, status) do
    %{state | status_message: "Status: #{status}"}
  end

  defp handle_tool_call_start(state, %{name: tool_name, arguments: _args} = _tool_info) do
    # Enhanced MCP tool call display for TUI
    {mcp_server, emoji} = detect_mcp_server_for_tui(tool_name)

    status =
      if mcp_server != :unknown do
        "#{emoji} Using MCP tool: #{tool_name} via #{mcp_server}..."
      else
        emoji = get_tool_emoji(tool_name)
        "#{emoji} Using tool: #{tool_name}..."
      end

    mcp_info = %{
      type: :tool_start,
      tool_name: tool_name,
      server: mcp_server,
      timestamp: DateTime.utc_now()
    }

    %{state | status_message: status, last_mcp_tool_call: mcp_info}
  rescue
    e ->
      require Logger
      Logger.error("Tool status format error: #{inspect(e)}")
      %{state | status_message: "🔧 Using tool..."}
  end

  defp handle_tool_call_end(state, %{name: tool_name, result: result}) do
    # Enhanced MCP tool result display for TUI
    {mcp_server, _emoji} = detect_mcp_server_for_tui(tool_name)

    formatted_content =
      if mcp_server != :unknown do
        format_mcp_tool_result_for_tui(tool_name, result, mcp_server)
      else
        format_tool_result_for_display(tool_name, result)
      end

    tool_result_message = %{
      type: :tool_result,
      content: formatted_content,
      timestamp: DateTime.utc_now()
    }

    mcp_info = %{
      type: :tool_result,
      tool_name: tool_name,
      server: mcp_server,
      result: format_mcp_result_summary(result),
      timestamp: DateTime.utc_now()
    }

    new_history =
      limit_conversation_history(state.conversation_history ++ [tool_result_message])

    %{state | conversation_history: new_history, status_message: "", last_mcp_tool_call: mcp_info}
  rescue
    e ->
      require Logger
      Logger.error("Tool result format error: #{inspect(e)}")
      # Still clear status but don't add malformed result
      %{state | status_message: ""}
  end

  defp handle_stream_chunk(state, chunk) do
    %{
      state
      | status_message: "✍️ Generating response...",
        streaming_buffer: state.streaming_buffer <> chunk
    }
  end

  defp handle_processing_complete(state, _final_response) do
    %{state | status_message: "", streaming_buffer: ""}
  end

  defp render_status_line(state, width) do
    status = String.slice(state.status_message, 0, width - 4)
    padded_status = String.pad_trailing(status, width - 2)
    IO.puts([IO.ANSI.bright(), IO.ANSI.yellow(), padded_status, IO.ANSI.reset()])
  end

  defp get_tool_emoji("read_file"), do: "📖"
  defp get_tool_emoji("write_file"), do: "✏️"
  defp get_tool_emoji("list_directory"), do: "📁"
  defp get_tool_emoji("bash"), do: "⚡"
  defp get_tool_emoji("shell"), do: "⚡"
  defp get_tool_emoji("execute_command"), do: "⚡"
  defp get_tool_emoji("grep"), do: "🔍"
  defp get_tool_emoji("openapi"), do: "🌐"
  defp get_tool_emoji("api_call"), do: "🌐"
  defp get_tool_emoji(_), do: "🔧"

  defp limit_conversation_history(history, max_messages \\ 100) do
    # Keep only the last max_messages, but always preserve system/welcome messages
    if length(history) <= max_messages do
      history
    else
      {system_messages, other_messages} =
        Enum.split_with(history, fn msg ->
          msg.type == :system and String.contains?(msg.content, "Welcome")
        end)

      recent_messages = Enum.take(other_messages, -max_messages + length(system_messages))
      system_messages ++ recent_messages
    end
  end

  defp format_tool_result_for_display(tool_name, result) do
    separator = String.duplicate("─", String.length("🔧 Tool: #{tool_name}"))

    case result do
      {:ok, data} when is_binary(data) ->
        content =
          if String.length(data) > 500, do: String.slice(data, 0, 500) <> "...", else: data

        "🔧 Tool: #{tool_name}\n#{separator}\n#{content}"

      {:ok, data} ->
        formatted_data = inspect(data, limit: 100, pretty: true)
        "🔧 Tool: #{tool_name}\n#{separator}\n#{formatted_data}"

      {:error, reason} ->
        "🔧 Tool: #{tool_name}\n#{separator}\n❌ Error: #{reason}"

      data when is_binary(data) ->
        content =
          if String.length(data) > 500, do: String.slice(data, 0, 500) <> "...", else: data

        "🔧 Tool: #{tool_name}\n#{separator}\n#{content}"

      data ->
        formatted_data = inspect(data, limit: 100, pretty: true)
        "🔧 Tool: #{tool_name}\n#{separator}\n#{formatted_data}"
    end
  end

  # Helper functions
  defp get_terminal_size do
    # Try to get terminal size, fallback to defaults
    case :io.columns() do
      {:ok, width} ->
        case :io.rows() do
          {:ok, height} -> {width, height}
          _ -> {width, 24}
        end

      _ ->
        {80, 24}
    end
  end

  defp center_text(text, width) do
    text_length = String.length(text)

    if text_length >= width do
      String.slice(text, 0, width)
    else
      padding = (width - text_length) / 2
      left_pad = trunc(padding)
      right_pad = width - text_length - left_pad

      String.duplicate(" ", left_pad) <> text <> String.duplicate(" ", right_pad)
    end
  end

  defp truncate_text(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      text
    end
  end

  defp message_color(:user), do: IO.ANSI.cyan()
  defp message_color(:agent), do: IO.ANSI.green()
  defp message_color(:system), do: IO.ANSI.yellow()
  defp message_color(:tool_result), do: IO.ANSI.magenta()
  defp message_color(_), do: IO.ANSI.white()

  defp format_message_type(:user), do: "USER"
  defp format_message_type(:agent), do: "AGENT"
  defp format_message_type(:system), do: "SYSTEM"
  defp format_message_type(:tool_result), do: "TOOL"
  defp format_message_type(type), do: String.upcase(to_string(type))

  defp parse_args(args) do
    # Future enhancement: Implement proper argument parsing for CLI options
    # For now, just return empty options
    _args = args
    %{}
  end

  # Provider and model selection functions

  # Handles the complete provider and model selection flow.
  # Returns {:ok, {provider, model, auth_context}} or {:error, reason}.
  defp handle_provider_and_model_selection do
    # Always execute provider selection flow - users need to auth with providers
    execute_selection_flow()
  end

  defp execute_selection_flow do
    case ProviderSelection.select_provider() do
      {:ok, provider} ->
        handle_provider_authentication(provider)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_provider_authentication(provider) do
    case AuthFlow.authenticate_provider(provider) do
      {:ok, auth_context} ->
        handle_model_selection(provider, auth_context)

      {:error, :back_to_provider} ->
        execute_selection_flow()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_model_selection(provider, auth_context) do
    case ModelSelection.select_model(provider, auth_context) do
      {:ok, {provider, model, auth_context}} ->
        {:ok, {provider, model, auth_context}}

      {:error, :back_to_auth} ->
        execute_selection_flow()

      {:error, :back_to_provider} ->
        execute_selection_flow()

      {:error, reason} ->
        {:error, reason}
    end
  end

  # MCP Integration Helper Functions for TUI

  defp get_mcp_server_status do
    case Registry.list_servers(Registry) do
      {:ok, servers} ->
        servers
        |> Enum.map(&format_server_for_tui/1)
        |> Enum.sort_by(& &1.priority)

      {:error, _reason} ->
        # Return demo servers if registry not available
        [
          %{
            id: "context7_stdio",
            name: "Context7 (stdio)",
            status: :connecting,
            transport: "stdio",
            icon: "📚",
            priority: 1
          },
          %{
            id: "context7_sse",
            name: "Context7 (SSE)",
            status: :connecting,
            transport: "sse",
            icon: "🌐",
            priority: 2
          },
          %{
            id: "tavily_http",
            name: "Tavily (HTTP)",
            status: :connecting,
            transport: "http",
            icon: "🔍",
            priority: 3
          }
        ]
    end
  end

  defp format_server_for_tui({server_id, server_info}) do
    %{
      id: server_id,
      name: get_server_display_name_tui(server_id),
      status: Map.get(server_info, :status, :unknown),
      transport: Map.get(server_info, :transport_type, "unknown"),
      icon: get_server_icon_tui(server_id),
      priority: get_server_priority_tui(server_id)
    }
  end

  defp get_server_display_name_tui("context7_stdio"), do: "Context7 (stdio)"
  defp get_server_display_name_tui("context7_sse"), do: "Context7 (SSE)"
  defp get_server_display_name_tui("tavily_http"), do: "Tavily (HTTP)"

  defp get_server_display_name_tui(server_id),
    do: String.replace(server_id, "_", " ") |> String.capitalize()

  defp get_server_icon_tui("context7_stdio"), do: "📚"
  defp get_server_icon_tui("context7_sse"), do: "🌐"
  defp get_server_icon_tui("tavily_http"), do: "🔍"
  defp get_server_icon_tui(_), do: "🔧"

  defp get_server_priority_tui("context7_stdio"), do: 1
  defp get_server_priority_tui("context7_sse"), do: 2
  defp get_server_priority_tui("tavily_http"), do: 3
  defp get_server_priority_tui(_), do: 10

  defp detect_mcp_server_for_tui(tool_name) do
    case tool_name do
      tool when tool in ["resolve-library-id", "get-library-docs"] -> {"Context7 (stdio)", "📚"}
      tool when tool in ["search", "extract", "crawl"] -> {"Tavily (HTTP)", "🔍"}
      tool when tool in ["context7-sse", "sse-docs"] -> {"Context7 (SSE)", "🌐"}
      _ -> {:unknown, "🔧"}
    end
  end

  defp format_mcp_tool_result_for_tui(tool_name, result, mcp_server) do
    server_display =
      case mcp_server do
        {"Context7" <> _, _} -> "📚 Context7"
        {"Tavily" <> _, _} -> "🔍 Tavily"
        _ -> "🔧 #{mcp_server}"
      end

    separator = String.duplicate("─", String.length("#{server_display} Tool: #{tool_name}"))

    case result do
      result when is_binary(result) and byte_size(result) > 1000 ->
        preview = String.slice(result, 0, 500) <> "... (truncated for TUI display)"
        "#{server_display} Tool: #{tool_name}\n#{separator}\n#{preview}"

      result when is_binary(result) ->
        "#{server_display} Tool: #{tool_name}\n#{separator}\n#{result}"

      {:ok, data} when is_binary(data) ->
        content =
          if String.length(data) > 500, do: String.slice(data, 0, 500) <> "...", else: data

        "#{server_display} Tool: #{tool_name}\n#{separator}\n#{content}"

      {:error, reason} ->
        "#{server_display} Tool: #{tool_name}\n#{separator}\n❌ Error: #{reason}"

      other ->
        formatted = inspect(other, limit: 50, pretty: true)
        "#{server_display} Tool: #{tool_name}\n#{separator}\n#{formatted}"
    end
  end

  defp format_mcp_result_summary(result) when is_binary(result) do
    if String.length(result) > 100 do
      String.slice(result, 0, 100) <> "..."
    else
      result
    end
  end

  defp format_mcp_result_summary(result) do
    inspect(result, limit: 20, pretty: false)
  end

  defp render_mcp_panel(servers, width) do
    panel_width = min(width - 4, 70)
    panel_header = "╔ MCP Servers " <> String.duplicate("═", panel_width - 14) <> "╗"

    IO.puts([IO.ANSI.bright(), IO.ANSI.cyan(), panel_header, IO.ANSI.reset()])

    for server <- servers do
      status_color =
        case server.status do
          :connected -> IO.ANSI.green()
          :connecting -> IO.ANSI.yellow()
          _ -> IO.ANSI.red()
        end

      line = "║ #{server.icon} #{server.name} [#{server.transport}] "
      status_text = "#{server.status}"
      padding_len = panel_width - String.length(line) - String.length(status_text) - 2
      padding = String.duplicate(" ", max(0, padding_len))

      IO.puts([
        IO.ANSI.bright(),
        IO.ANSI.cyan(),
        "║ ",
        IO.ANSI.reset(),
        server.icon,
        " ",
        server.name,
        " [",
        server.transport,
        "] ",
        padding,
        status_color,
        status_text,
        IO.ANSI.bright(),
        IO.ANSI.cyan(),
        " ║",
        IO.ANSI.reset()
      ])
    end

    panel_footer = "╚" <> String.duplicate("═", panel_width - 2) <> "╝"
    IO.puts([IO.ANSI.bright(), IO.ANSI.cyan(), panel_footer, IO.ANSI.reset()])
  end

  defp show_mcp_status_info(state) do
    IO.puts([IO.ANSI.bright(), IO.ANSI.cyan(), "\n🔗 MCP Server Status Report", IO.ANSI.reset()])
    IO.puts(String.duplicate("=", 40))

    if length(state.mcp_servers) == 0 do
      IO.puts("No MCP servers configured or available.")
    else
      for server <- state.mcp_servers do
        status_color =
          case server.status do
            :connected -> IO.ANSI.green()
            :connecting -> IO.ANSI.yellow()
            _ -> IO.ANSI.red()
          end

        IO.puts([
          server.icon,
          " ",
          IO.ANSI.bright(),
          server.name,
          IO.ANSI.reset(),
          "\n  Status: ",
          status_color,
          "#{server.status}",
          IO.ANSI.reset(),
          "\n  Transport: #{server.transport}",
          "\n  ID: #{server.id}",
          "\n"
        ])
      end
    end

    if state.last_mcp_tool_call do
      IO.puts([IO.ANSI.bright(), "🔧 Last MCP Tool Call:", IO.ANSI.reset()])
      IO.puts("  Tool: #{state.last_mcp_tool_call.tool_name}")
      IO.puts("  Server: #{state.last_mcp_tool_call.server}")
      IO.puts("  Time: #{format_timestamp(state.last_mcp_tool_call.timestamp)}")

      if state.last_mcp_tool_call.type == :tool_result do
        IO.puts("  Result: #{state.last_mcp_tool_call.result}")
      end
    end

    IO.puts("\nPress Enter to continue...")
    IO.gets("")
  end

  defp show_tui_help do
    IO.puts([IO.ANSI.bright(), IO.ANSI.green(), "\n📖 The Maestro TUI Help", IO.ANSI.reset()])
    IO.puts(String.duplicate("=", 40))
    IO.puts("Commands:")
    IO.puts("  q            - Quit the TUI")
    IO.puts("  help         - Show this help")
    IO.puts("  mcp          - Toggle MCP server panel")
    IO.puts("  mcp status   - Show detailed MCP server status")
    IO.puts("  mcp refresh  - Refresh MCP server status")
    IO.puts("")
    IO.puts("MCP Integration Features:")
    IO.puts("  • Real-time MCP server status display")
    IO.puts("  • Enhanced tool execution with MCP server identification")
    IO.puts("  • Rich content display for Context7 documentation")
    IO.puts("  • Tavily search result formatting")
    IO.puts("  • Multi-transport support (stdio, HTTP, SSE)")
    IO.puts("")
    IO.puts("Press Enter to continue...")
    IO.gets("")
  end

  # Helper function for timestamp formatting in TUI
  defp format_timestamp(%DateTime{} = timestamp) do
    timestamp
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 8)
  end

  defp format_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> format_timestamp(dt)
      _ -> timestamp
    end
  end

  defp format_timestamp(_), do: "unknown"
end
