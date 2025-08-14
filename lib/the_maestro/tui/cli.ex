defmodule TheMaestro.TUI.CLI do
  @moduledoc """
  Terminal User Interface (TUI) for The Maestro AI agent.

  This module provides a terminal-based interface as an alternative "head" 
  for interacting with the core agent, providing a feature-complete CLI experience.

  Uses pure Elixir with ANSI escape codes for cross-platform Mac/Linux support.
  """

  alias TheMaestro.Agents.{Agent, DynamicSupervisor}
  alias TheMaestro.Providers.Gemini

  @doc """
  Main entry point for the escript executable.
  """
  def main(args \\ []) do
    # Set environment variable to prevent Phoenix startup
    System.put_env("RUNNING_AS_ESCRIPT", "true")

    # Parse command line arguments (future enhancement)
    _parsed_args = parse_args(args)

    # Check authentication requirements and handle login
    case handle_authentication() do
      {:ok, auth_info} ->
        # Initialize the TUI with authentication info
        initialize_tui(auth_info)

        # Start the main loop
        run_tui()

      {:error, reason} ->
        IO.puts([IO.ANSI.red(), "Authentication failed: #{reason}", IO.ANSI.reset()])
        System.halt(1)
    end
  end

  defp initialize_tui(auth_info) do
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

    # Build welcome message based on authentication status
    welcome_messages =
      case auth_info do
        %{authenticated: true, method: :api_key} ->
          [
            %{type: :system, content: "Welcome to The Maestro TUI!"},
            %{type: :system, content: "Authenticated with API Key"},
            %{
              type: :system,
              content: "Type your message and press Enter to chat with the agent."
            },
            %{type: :system, content: "Press Ctrl-C or 'q' to exit."}
          ]

        %{authenticated: true, method: :oauth, user_email: email} ->
          [
            %{type: :system, content: "Welcome to The Maestro TUI!"},
            %{type: :system, content: "Authenticated as: #{email}"},
            %{
              type: :system,
              content: "Type your message and press Enter to chat with the agent."
            },
            %{type: :system, content: "Press Ctrl-C or 'q' to exit."}
          ]

        %{authenticated: true, user_email: email} ->
          # Legacy OAuth format
          [
            %{type: :system, content: "Welcome to The Maestro TUI!"},
            %{type: :system, content: "Authenticated as: #{email}"},
            %{
              type: :system,
              content: "Type your message and press Enter to chat with the agent."
            },
            %{type: :system, content: "Press Ctrl-C or 'q' to exit."}
          ]

        %{authenticated: false} ->
          [
            %{type: :system, content: "Welcome to The Maestro TUI!"},
            %{type: :system, content: "Running in anonymous mode"},
            %{
              type: :system,
              content: "Type your message and press Enter to chat with the agent."
            },
            %{type: :system, content: "Press Ctrl-C or 'q' to exit."}
          ]
      end

    # Initial state
    initial_state = %{
      conversation_history: welcome_messages,
      current_input: "",
      auth_info: auth_info,
      status_message: "",
      streaming_buffer: ""
    }

    # Store state in process dictionary for simple state management
    Process.put(:tui_state, initial_state)
    # Also store auth info separately for agent creation
    Process.put(:tui_auth_info, auth_info)
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
    IO.puts([IO.ANSI.faint(), "Press Enter to send, Ctrl-C or 'q' to quit", IO.ANSI.reset()])

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
    case get_agent_response(input, state.auth_info) do
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

  defp get_agent_response(input, auth_info) do
    # Get or create an agent for this TUI session
    agent_id = get_session_agent_id(auth_info)

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

  defp get_session_agent_id(auth_info) do
    # Create a unique agent ID for this TUI session
    case auth_info do
      %{authenticated: true, method: :api_key} ->
        # For API key auth, use a hash of the API key
        api_key = auth_info[:api_key] || "default"
        :crypto.hash(:sha256, api_key) |> Base.encode16(case: :lower) |> binary_part(0, 16)

      %{authenticated: true, method: :oauth, user_email: email} ->
        # Use a hash of the email for OAuth sessions
        :crypto.hash(:sha256, email) |> Base.encode16(case: :lower) |> binary_part(0, 16)

      %{authenticated: true, user_email: email} ->
        # Legacy OAuth format
        :crypto.hash(:sha256, email) |> Base.encode16(case: :lower) |> binary_part(0, 16)

      %{authenticated: false} ->
        # For anonymous sessions, use a session-specific ID
        # We'll store this in the process dictionary to maintain consistency
        case Process.get(:tui_agent_id) do
          nil ->
            agent_id = "anon_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
            Process.put(:tui_agent_id, agent_id)
            agent_id

          existing_id ->
            existing_id
        end
    end
  end

  defp ensure_agent_exists(agent_id) do
    case GenServer.whereis(Agent.via_tuple(agent_id)) do
      nil ->
        # Agent doesn't exist, start it with proper auth context
        provider = Agent.get_default_provider()
        auth_info = Process.get(:tui_auth_info)

        # Create the appropriate auth context based on the authentication method
        auth_context = create_auth_context_for_provider(auth_info, provider)

        DynamicSupervisor.start_agent(
          agent_id,
          llm_provider: provider,
          auth_context: auth_context
        )

      pid when is_pid(pid) ->
        # Agent already exists
        {:ok, pid}
    end
  end

  defp create_auth_context_for_provider(auth_info, provider) do
    case {auth_info.method, provider} do
      {:api_key, _} ->
        # For API key authentication, create context in provider format
        %{
          type: :api_key,
          credentials: %{api_key: auth_info.api_key},
          config: %{}
        }

      {:oauth, _} ->
        # For OAuth authentication, create OAuth context with tokens
        %{
          type: :oauth,
          credentials: %{
            access_token: auth_info.access_token,
            user_email: auth_info.user_email
          },
          config: %{}
        }

      _ ->
        # Fallback - let provider initialize its own auth
        nil
    end
  end

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

  defp handle_tool_call_start(state, %{name: tool_name, arguments: _args}) do
    emoji = get_tool_emoji(tool_name)
    status = "#{emoji} Using tool: #{tool_name}..."
    %{state | status_message: status}
  rescue
    e ->
      require Logger
      Logger.error("Tool status format error: #{inspect(e)}")
      %{state | status_message: "🔧 Using tool..."}
  end

  defp handle_tool_call_end(state, %{name: tool_name, result: result}) do
    # Add formatted tool result to conversation history
    tool_result_message = %{
      type: :tool_result,
      content: format_tool_result_for_display(tool_name, result),
      timestamp: DateTime.utc_now()
    }

    new_history =
      limit_conversation_history(state.conversation_history ++ [tool_result_message])

    %{state | conversation_history: new_history, status_message: ""}
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

  # Authentication handling functions

  # Handles authentication based on application configuration.
  # Returns {:ok, auth_info} or {:error, reason}.
  defp handle_authentication do
    # Read configuration to determine if authentication is required
    case read_authentication_config() do
      {:ok, true} ->
        # Authentication is required - detect available methods and let user choose
        detect_and_choose_authentication_method()

      {:ok, false} ->
        # Authentication is disabled - proceed in anonymous mode
        {:ok, %{authenticated: false}}

      {:error, reason} ->
        {:error, "Failed to read configuration: #{reason}"}
    end
  end

  defp read_authentication_config do
    # Read the configuration from the application environment
    # This will work whether we're in an escript or regular application
    case Application.get_env(:the_maestro, :require_authentication) do
      true -> {:ok, true}
      false -> {:ok, false}
      # Default to requiring authentication for security
      nil -> {:ok, true}
      _ -> {:error, "Invalid authentication configuration"}
    end
  end

  defp detect_and_choose_authentication_method do
    # Check if user has a saved authentication preference
    case load_auth_preference() do
      {:ok, auth_method} ->
        # User has a saved preference, try to use it
        case attempt_saved_authentication_method(auth_method) do
          {:ok, auth_info} ->
            {:ok, auth_info}

          {:error, _reason} ->
            # Saved method failed, show menu to choose again
            IO.puts([IO.ANSI.yellow(), "Previous authentication method failed.", IO.ANSI.reset()])
            show_authentication_menu()
        end

      {:error, :no_preference} ->
        # No saved preference, show menu
        show_authentication_menu()

      {:error, reason} ->
        {:error, "Failed to load authentication preference: #{reason}"}
    end
  end

  defp show_authentication_menu do
    IO.write([IO.ANSI.clear(), IO.ANSI.home()])

    IO.puts([
      IO.ANSI.bright(),
      IO.ANSI.blue(),
      "┌────────────────────────────────────────────────────────────────────────────┐",
      IO.ANSI.reset()
    ])

    IO.puts([
      IO.ANSI.bright(),
      IO.ANSI.blue(),
      "│                           AUTHENTICATION METHOD                            │",
      IO.ANSI.reset()
    ])

    IO.puts([
      IO.ANSI.bright(),
      IO.ANSI.blue(),
      "└────────────────────────────────────────────────────────────────────────────┘",
      IO.ANSI.reset()
    ])

    IO.puts("")

    IO.puts([IO.ANSI.bright(), "Choose your preferred authentication method:", IO.ANSI.reset()])
    IO.puts("")

    # Check what methods are available
    api_key_available = System.get_env("GEMINI_API_KEY") != nil

    if api_key_available do
      IO.puts([
        IO.ANSI.bright(),
        IO.ANSI.green(),
        "1. ",
        IO.ANSI.reset(),
        IO.ANSI.bright(),
        "API Key",
        IO.ANSI.reset(),
        " (GEMINI_API_KEY detected)"
      ])

      IO.puts("   Fast and simple - uses your API key from environment variable")
    else
      IO.puts([
        IO.ANSI.faint(),
        "1. API Key (No GEMINI_API_KEY found in environment)",
        IO.ANSI.reset()
      ])
    end

    IO.puts("")

    IO.puts([
      IO.ANSI.bright(),
      IO.ANSI.cyan(),
      "2. ",
      IO.ANSI.reset(),
      IO.ANSI.bright(),
      "OAuth (Google Account)",
      IO.ANSI.reset()
    ])

    IO.puts("   Secure OAuth flow - sign in with your Google account")
    IO.puts("")

    if api_key_available do
      IO.puts([IO.ANSI.faint(), "Enter your choice (1-2): ", IO.ANSI.reset()])
    else
      IO.puts([
        IO.ANSI.faint(),
        "Enter your choice (2 for OAuth, or set GEMINI_API_KEY): ",
        IO.ANSI.reset()
      ])
    end

    case IO.gets("") do
      "1\n" when api_key_available ->
        handle_api_key_authentication()

      "2\n" ->
        handle_oauth_authentication()

      "1\n" ->
        IO.puts([
          IO.ANSI.red(),
          "No GEMINI_API_KEY found. Please set it or choose OAuth (2).",
          IO.ANSI.reset()
        ])

        :timer.sleep(2000)
        show_authentication_menu()

      _ ->
        IO.puts([IO.ANSI.red(), "Invalid choice. Please enter 1 or 2.", IO.ANSI.reset()])
        :timer.sleep(1000)
        show_authentication_menu()
    end
  end

  defp handle_api_key_authentication do
    IO.puts([IO.ANSI.bright(), "Using API Key authentication...", IO.ANSI.reset()])

    # Save user's preference
    save_auth_preference("api_key")

    # Create auth context for API key
    auth_info = %{
      authenticated: true,
      method: :api_key,
      api_key: System.get_env("GEMINI_API_KEY")
    }

    IO.puts([IO.ANSI.green(), "✓ API Key authentication configured!", IO.ANSI.reset()])
    :timer.sleep(1000)

    {:ok, auth_info}
  end

  defp handle_oauth_authentication do
    IO.puts([IO.ANSI.bright(), "Using Google OAuth authentication...", IO.ANSI.reset()])

    # Save user's preference
    save_auth_preference("oauth")

    # Start the Google OAuth device flow directly
    initiate_device_authorization_flow()
  end

  defp initiate_device_authorization_flow do
    IO.puts([IO.ANSI.bright(), "Checking for existing authentication...", IO.ANSI.reset()])

    # First, check if we have a valid stored token
    case load_stored_token() do
      {:ok, token_info} ->
        IO.puts([IO.ANSI.green(), "Found valid authentication token", IO.ANSI.reset()])
        {:ok, token_info}

      {:error, _reason} ->
        IO.puts([
          IO.ANSI.yellow(),
          "No valid token found, starting authentication...",
          IO.ANSI.reset()
        ])

        start_device_authorization()
    end
  end

  defp start_device_authorization do
    IO.puts([
      IO.ANSI.bright(),
      "Starting Google OAuth device authorization flow...",
      IO.ANSI.reset()
    ])

    # Use the Gemini provider's device authorization flow
    case Gemini.device_authorization_flow() do
      {:ok,
       %{auth_url: auth_url, state: state, code_verifier: code_verifier, polling_fn: polling_fn}} ->
        display_google_oauth_instructions(auth_url, state)
        poll_for_google_authorization(polling_fn, code_verifier)

      {:error, reason} ->
        {:error, "Failed to start Google OAuth: #{reason}"}
    end
  end

  defp display_google_oauth_instructions(auth_url, _state) do
    IO.write([IO.ANSI.clear(), IO.ANSI.home()])

    IO.puts([
      IO.ANSI.bright(),
      IO.ANSI.blue(),
      "┌────────────────────────────────────────────────────────────────────────────┐",
      IO.ANSI.reset()
    ])

    IO.puts([
      IO.ANSI.bright(),
      IO.ANSI.blue(),
      "│                        GOOGLE OAUTH AUTHORIZATION                          │",
      IO.ANSI.reset()
    ])

    IO.puts([
      IO.ANSI.bright(),
      IO.ANSI.blue(),
      "└────────────────────────────────────────────────────────────────────────────┘",
      IO.ANSI.reset()
    ])

    IO.puts("")

    IO.puts([
      IO.ANSI.bright(),
      "To authorize The Maestro TUI with Google, please:",
      IO.ANSI.reset()
    ])

    IO.puts("")

    IO.puts([
      IO.ANSI.bright(),
      "1. Open your browser and visit:",
      IO.ANSI.reset()
    ])

    IO.puts([
      "   ",
      IO.ANSI.bright(),
      IO.ANSI.cyan(),
      auth_url,
      IO.ANSI.reset()
    ])

    IO.puts("")

    IO.puts([
      IO.ANSI.bright(),
      "2. Sign in with your Google account and authorize The Maestro",
      IO.ANSI.reset()
    ])

    IO.puts("")

    IO.puts([
      IO.ANSI.bright(),
      "3. Copy the authorization code from the browser and paste it below",
      IO.ANSI.reset()
    ])

    IO.puts("")
  end

  defp poll_for_google_authorization(polling_fn, code_verifier) do
    IO.puts([
      IO.ANSI.faint(),
      "Waiting for you to complete authorization in your browser...",
      IO.ANSI.reset()
    ])

    # Get the authorization code from the user
    case polling_fn.() do
      "" ->
        {:error, "No authorization code provided"}

      auth_code ->
        # Complete the device authorization with the code
        case Gemini.complete_device_authorization(auth_code, code_verifier) do
          {:ok, auth_info} ->
            handle_successful_google_authorization(auth_info)

          {:error, reason} ->
            {:error, "Failed to complete Google OAuth: #{inspect(reason)}"}
        end
    end
  end

  defp handle_successful_google_authorization(auth_info) do
    # Convert Gemini provider auth format to TUI format
    tui_auth_info = %{
      authenticated: true,
      method: :oauth,
      access_token: auth_info.access_token,
      user_email: auth_info[:user_email] || "google_user"
    }

    # Store the token for future use
    store_token(tui_auth_info)

    IO.puts([IO.ANSI.green(), "✓ Google OAuth authorization successful!", IO.ANSI.reset()])
    # Brief pause to show success message
    :timer.sleep(1000)

    {:ok, tui_auth_info}
  end

  defp store_token(auth_info) do
    # Store token in user's home directory
    home_dir = System.user_home!()
    maestro_dir = Path.join(home_dir, ".maestro")
    token_file = Path.join(maestro_dir, "tui_credentials.json")

    # Ensure directory exists
    File.mkdir_p!(maestro_dir)

    # Create token data
    token_data = %{
      access_token: auth_info.access_token,
      user_email: auth_info.user_email,
      stored_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Write to file
    case Jason.encode(token_data) do
      {:ok, json} ->
        File.write!(token_file, json)
        # Set file permissions to be readable only by owner (600)
        File.chmod!(token_file, 0o600)

      {:error, _} ->
        :error
    end
  end

  defp load_stored_token do
    # Try to load OAuth credentials from the Gemini provider's cache first
    case Gemini.initialize_auth() do
      {:ok, %{type: :oauth, credentials: credentials}} ->
        # Convert to TUI format
        auth_info = %{
          authenticated: true,
          method: :oauth,
          access_token: credentials.access_token,
          user_email: credentials[:user_email] || "google_user"
        }

        {:ok, auth_info}

      {:ok, _other_auth} ->
        {:error, "No OAuth credentials found"}

      {:error, _reason} ->
        # Fallback to TUI-specific token file
        load_tui_specific_token()
    end
  end

  defp load_tui_specific_token do
    home_dir = System.user_home!()
    token_file = Path.join([home_dir, ".maestro", "tui_credentials.json"])

    case File.read(token_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, token_data} ->
            auth_info = %{
              authenticated: true,
              method: :oauth,
              access_token: token_data["access_token"],
              user_email: token_data["user_email"] || "google_user"
            }

            {:ok, auth_info}

          {:error, _} ->
            {:error, "Invalid token file format"}
        end

      {:error, _} ->
        {:error, "No stored token found"}
    end
  end

  # Authentication preference management
  defp load_auth_preference do
    home_dir = System.user_home!()
    pref_file = Path.join([home_dir, ".maestro", "auth_preference.txt"])

    case File.read(pref_file) do
      {:ok, content} ->
        method = String.trim(content)

        if method in ["api_key", "oauth"] do
          {:ok, method}
        else
          {:error, :invalid_preference}
        end

      {:error, :enoent} ->
        {:error, :no_preference}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp save_auth_preference(method) when method in ["api_key", "oauth"] do
    home_dir = System.user_home!()
    maestro_dir = Path.join(home_dir, ".maestro")
    pref_file = Path.join(maestro_dir, "auth_preference.txt")

    # Ensure directory exists
    File.mkdir_p!(maestro_dir)

    # Write preference
    File.write!(pref_file, method)
  end

  defp attempt_saved_authentication_method("api_key") do
    # Check if API key is still available
    case System.get_env("GEMINI_API_KEY") do
      nil ->
        {:error, "GEMINI_API_KEY not found"}

      api_key ->
        auth_info = %{
          authenticated: true,
          method: :api_key,
          api_key: api_key
        }

        {:ok, auth_info}
    end
  end

  defp attempt_saved_authentication_method("oauth") do
    # Try to load existing OAuth token
    case load_stored_token() do
      {:ok, auth_info} ->
        {:ok, auth_info}

      {:error, _reason} ->
        {:error, "No valid OAuth token found"}
    end
  end
end
