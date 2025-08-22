defmodule TheMaestro.MCP.CLI.Commands.Interactive do
  @moduledoc """
  Interactive command for MCP CLI.

  Provides an interactive shell mode for MCP server management.
  """

  alias TheMaestro.MCP.{Config, ServerSupervisor}
  alias TheMaestro.MCP.CLI
  alias TheMaestro.Prompts.EngineeringTools.CLI, as: PromptCLI

  @doc """
  Execute the interactive command.
  """
  def execute(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case args do
      [] ->
        start_interactive_mode(options)

      ["shell"] ->
        start_shell_mode(options)

      ["repl"] ->
        start_repl_mode(options)

      _ ->
        CLI.print_error("Invalid interactive command. Use --help for usage.")
    end
  end

  @doc """
  Show help for the interactive command.
  """
  def show_help do
    IO.puts("""
    MCP Interactive Mode

    Usage:
      maestro mcp interactive [mode] [OPTIONS]

    Modes:
      (none)         Start default interactive mode
      shell          Start interactive shell with command history
      repl           Start REPL (Read-Eval-Print Loop) mode

    Options:
      --server <name>      Connect to specific server
      --auto-complete      Enable auto-completion
      --history            Enable command history
      --prompt <text>      Custom prompt text
      --help               Show this help message

    Interactive Commands:
      help                 Show available commands
      list                 List servers
      connect <server>     Connect to server
      disconnect           Disconnect from current server
      tools                List tools for current server
      call <tool> [args]   Call a tool
      status               Show connection status
      history              Show command history
      clear                Clear screen
      exit/quit            Exit interactive mode

    Examples:
      maestro mcp interactive
      maestro mcp interactive --server myServer
      maestro mcp interactive shell --auto-complete
    """)
  end

  ## Private Functions

  defp start_interactive_mode(options) do
    CLI.print_info("Starting MCP Interactive Mode")

    # Initialize interactive state
    state = %{
      current_server: Map.get(options, :server),
      auto_complete: Map.get(options, :auto_complete, true),
      history: Map.get(options, :history, true),
      prompt: Map.get(options, :prompt, "mcp> "),
      command_history: [],
      connected_servers: %{}
    }

    # Show welcome message
    show_welcome_message(state)

    # Auto-connect to server if specified
    state =
      case state.current_server do
        nil ->
          state

        server_name ->
          case connect_to_server(server_name, state) do
            {:ok, updated_state} ->
              updated_state

            {:error, reason} ->
              CLI.print_error("Failed to connect to '#{server_name}': #{inspect(reason)}")

              state
          end
      end

    # Start interactive loop
    interactive_loop(state)
  end

  defp start_shell_mode(options) do
    CLI.print_info("Starting MCP Shell Mode")

    # Shell mode with enhanced features
    state = %{
      current_server: Map.get(options, :server),
      auto_complete: Map.get(options, :auto_complete, true),
      history: Map.get(options, :history, true),
      prompt: Map.get(options, :prompt, "mcp-shell> "),
      command_history: load_command_history(),
      connected_servers: %{},
      shell_mode: true
    }

    show_shell_welcome(state)
    interactive_loop(state)
  end

  defp start_repl_mode(options) do
    CLI.print_info("Starting MCP REPL Mode")

    # REPL mode for advanced users
    state = %{
      current_server: Map.get(options, :server),
      auto_complete: true,
      history: true,
      prompt: "mcp-repl> ",
      command_history: [],
      connected_servers: %{},
      repl_mode: true,
      variables: %{}
    }

    show_repl_welcome(state)
    repl_loop(state)
  end

  defp interactive_loop(state) do
    # Display prompt and read input
    input = IO.gets(state.prompt)

    case input do
      :eof ->
        handle_exit(state)

      input when is_binary(input) ->
        trimmed_input = String.trim(input)

        if String.length(trimmed_input) > 0 do
          # Add to history
          updated_state = add_to_history(state, trimmed_input)

          # Parse and execute command
          case parse_interactive_command(trimmed_input) do
            {:command, command, args} ->
              case execute_interactive_command(command, args, updated_state) do
                {:ok, new_state} ->
                  interactive_loop(new_state)

                {:exit, _reason} ->
                  handle_exit(updated_state)
              end

            {:error, reason} ->
              CLI.print_error("Parse error: #{reason}")
              interactive_loop(updated_state)
          end
        else
          interactive_loop(state)
        end

      _ ->
        interactive_loop(state)
    end
  end

  defp repl_loop(state) do
    # Enhanced REPL with variable support and expressions
    input = IO.gets(state.prompt)

    case input do
      :eof ->
        handle_exit(state)

      input when is_binary(input) ->
        trimmed_input = String.trim(input)

        if String.length(trimmed_input) > 0 do
          updated_state = add_to_history(state, trimmed_input)

          case evaluate_repl_expression(trimmed_input, updated_state) do
            {:ok, result, new_state} ->
              if result != :no_output do
                IO.puts("=> #{inspect(result)}")
              end

              repl_loop(new_state)

            {:exit, _reason} ->
              handle_exit(updated_state)

            {:error, reason} ->
              CLI.print_error("Error: #{reason}")
              repl_loop(updated_state)
          end
        else
          repl_loop(state)
        end

      _ ->
        repl_loop(state)
    end
  end

  # Command parsing and execution

  defp parse_interactive_command(input) do
    case String.split(input, " ", trim: true) do
      [] -> {:error, "Empty command"}
      [command | args] -> {:command, String.downcase(command), args}
    end
  end

  defp execute_interactive_command(command, args, state) do
    case command do
      "help" -> handle_help_command(args, state)
      "?" -> handle_help_command(args, state)
      "list" -> handle_list_command(args, state)
      "ls" -> handle_list_command(args, state)
      "connect" -> handle_connect_command(args, state)
      "disconnect" -> handle_disconnect_command(args, state)
      "status" -> handle_status_command(args, state)
      "tools" -> handle_tools_command(args, state)
      "call" -> handle_call_command(args, state)
      "invoke" -> handle_call_command(args, state)
      "history" -> handle_history_command(args, state)
      "clear" -> handle_clear_command(args, state)
      "cls" -> handle_clear_command(args, state)
      "config" -> handle_config_command(args, state)
      "set" -> handle_set_command(args, state)
      "get" -> handle_get_command(args, state)
      
      # Prompt Engineering Commands
      "prompt" -> handle_prompt_command(args, state)
      "template" -> handle_template_command(args, state)
      "experiment" -> handle_experiment_command(args, state)
      "session" -> handle_session_command(args, state)
      "workspace" -> handle_workspace_command(args, state)
      "analyze" -> handle_analyze_command(args, state)
      "docs" -> handle_docs_command(args, state)
      
      "exit" -> {:exit, :user_exit}
      "quit" -> {:exit, :user_exit}
      "q" -> {:exit, :user_exit}
      _ -> handle_unknown_command(command, args, state)
    end
  end

  defp evaluate_repl_expression(expression, state) do
    cond do
      String.starts_with?(expression, ":") ->
        # REPL command
        command_part = String.slice(expression, 1..-1//1)

        case parse_interactive_command(command_part) do
          {:command, command, args} ->
            case execute_interactive_command(command, args, state) do
              {:ok, new_state} -> {:ok, :no_output, new_state}
              other -> other
            end

          error ->
            error
        end

      String.contains?(expression, "=") && not String.contains?(expression, "==") ->
        # Variable assignment
        handle_variable_assignment(expression, state)

      String.starts_with?(expression, "$") ->
        # Variable reference
        var_name = String.slice(expression, 1..-1//1)
        value = Map.get(state.variables, var_name, :undefined)
        {:ok, value, state}

      true ->
        # Try to execute as regular command
        case parse_interactive_command(expression) do
          {:command, command, args} ->
            case execute_interactive_command(command, args, state) do
              {:ok, new_state} -> {:ok, :no_output, new_state}
              other -> other
            end

          error ->
            error
        end
    end
  end

  # Command handlers

  defp handle_help_command(args, state) do
    case args do
      [] -> show_interactive_help()
      [topic] -> show_topic_help(topic)
      _ -> CLI.print_error("Usage: help [topic]")
    end

    {:ok, state}
  end

  defp handle_list_command(args, state) do
    case args do
      [] -> list_all_servers(state)
      ["servers"] -> list_all_servers(state)
      ["connected"] -> list_connected_servers(state)
      [server_name] -> show_server_details(server_name, state)
      _ -> CLI.print_error("Usage: list [servers|connected|<server-name>]")
    end

    {:ok, state}
  end

  defp handle_connect_command(args, state) do
    case args do
      [server_name] ->
        case connect_to_server(server_name, state) do
          {:ok, new_state} ->
            {:ok, new_state}

          {:error, reason} ->
            CLI.print_error("Connection failed: #{inspect(reason)}")
            {:ok, state}
        end

      _ ->
        CLI.print_error("Usage: connect <server-name>")
        {:ok, state}
    end
  end

  defp handle_disconnect_command(args, state) do
    case args do
      [] ->
        case state.current_server do
          nil ->
            CLI.print_warning("No server currently connected")
            {:ok, state}

          server_name ->
            case disconnect_from_server(server_name, state) do
              {:ok, new_state} ->
                {:ok, new_state}

              {:error, reason} ->
                CLI.print_error("Disconnect failed: #{inspect(reason)}")
                {:ok, state}
            end
        end

      [server_name] ->
        case disconnect_from_server(server_name, state) do
          {:ok, new_state} ->
            {:ok, new_state}

          {:error, reason} ->
            CLI.print_error("Disconnect failed: #{inspect(reason)}")
            {:ok, state}
        end

      _ ->
        CLI.print_error("Usage: disconnect [server-name]")
        {:ok, state}
    end
  end

  defp handle_status_command(_args, state) do
    show_connection_status(state)
    {:ok, state}
  end

  defp handle_tools_command(args, state) do
    case args do
      [] ->
        case state.current_server do
          nil ->
            CLI.print_error("No server connected. Use 'connect <server>' first")

          server_name ->
            list_server_tools(server_name, state)
        end

      [server_name] ->
        list_server_tools(server_name, state)

      _ ->
        CLI.print_error("Usage: tools [server-name]")
    end

    {:ok, state}
  end

  defp handle_call_command(args, state) do
    case args do
      [tool_name | tool_args] ->
        case state.current_server do
          nil ->
            CLI.print_error("No server connected. Use 'connect <server>' first")

          server_name ->
            call_server_tool(server_name, tool_name, tool_args, state)
        end

      _ ->
        CLI.print_error("Usage: call <tool-name> [args...]")
    end

    {:ok, state}
  end

  defp handle_history_command(_args, state) do
    show_command_history(state)
    {:ok, state}
  end

  defp handle_clear_command(_args, state) do
    # ANSI clear screen
    IO.write("\e[2J\e[H")
    {:ok, state}
  end

  defp handle_config_command(args, state) do
    case args do
      [] -> show_current_config(state)
      ["reload"] -> reload_configuration(state)
      _ -> CLI.print_error("Usage: config [reload]")
    end

    {:ok, state}
  end

  defp handle_set_command(args, state) do
    case args do
      [key, value] ->
        updated_state = set_session_variable(state, key, value)
        CLI.print_success("Set #{key} = #{value}")
        {:ok, updated_state}

      _ ->
        CLI.print_error("Usage: set <key> <value>")
        {:ok, state}
    end
  end

  defp handle_get_command(args, state) do
    case args do
      [key] ->
        value = get_session_variable(state, key)
        IO.puts("#{key} = #{inspect(value)}")
        {:ok, state}

      _ ->
        CLI.print_error("Usage: get <key>")
        {:ok, state}
    end
  end

  defp handle_unknown_command(command, _args, state) do
    CLI.print_error("Unknown command: #{command}")
    IO.puts("Type 'help' for available commands")
    {:ok, state}
  end

  defp handle_variable_assignment(expression, state) do
    case String.split(expression, "=", parts: 2) do
      [var_name, value_expr] ->
        trimmed_name = String.trim(var_name)
        trimmed_value = String.trim(value_expr)

        # Simple value parsing
        parsed_value =
          case trimmed_value do
            "true" ->
              true

            "false" ->
              false

            "nil" ->
              nil

            value ->
              if String.starts_with?(value, "\"") and String.ends_with?(value, "\"") do
                String.slice(value, 1..-2//1)
              else
                case Integer.parse(value) do
                  {int, ""} ->
                    int

                  _ ->
                    case Float.parse(value) do
                      {float, ""} -> float
                      # Keep as string
                      _ -> value
                    end
                end
              end
          end

        updated_variables = Map.put(state.variables, trimmed_name, parsed_value)
        new_state = %{state | variables: updated_variables}

        {:ok, parsed_value, new_state}

      _ ->
        {:error, "Invalid assignment syntax"}
    end
  end

  # Prompt Engineering Command Handlers

  defp handle_prompt_command(args, state) do
    execute_prompt_engineering_command("prompt", args, state)
  end

  defp handle_template_command(args, state) do
    execute_prompt_engineering_command("template", args, state)
  end

  defp handle_experiment_command(args, state) do
    execute_prompt_engineering_command("experiment", args, state)
  end

  defp handle_session_command(args, state) do
    execute_prompt_engineering_command("session", args, state)
  end

  defp handle_workspace_command(args, state) do
    execute_prompt_engineering_command("workspace", args, state)
  end

  defp handle_analyze_command(args, state) do
    execute_prompt_engineering_command("analyze", args, state)
  end

  defp handle_docs_command(args, state) do
    execute_prompt_engineering_command("docs", args, state)
  end

  defp execute_prompt_engineering_command(command, args, state) do
    # Build command string for PromptCLI
    command_string = case args do
      [] -> "#{command} help"
      [subcommand | rest] -> 
        case rest do
          [] -> "#{command} #{subcommand}"
          [name | _] -> "#{command} #{subcommand} #{name}"
        end
    end

    # Create context with user info
    context = %{
      user: System.get_env("USER") || "maestro_user",
      interactive_mode: true
    }

    case PromptCLI.handle_command(command_string, context) do
      {:ok, result} ->
        IO.puts(result)
        {:ok, state}

      {:error, reason} ->
        CLI.print_error("Prompt engineering command failed: #{reason}")
        {:ok, state}
    end
  rescue
    error ->
      CLI.print_error("Error executing prompt command: #{Exception.message(error)}")
      {:ok, state}
  end

  # State management

  defp add_to_history(state, command) do
    if state.history do
      updated_history = [command | state.command_history] |> Enum.take(100)
      %{state | command_history: updated_history}
    else
      state
    end
  end

  defp connect_to_server(server_name, state) do
    CLI.print_info("Connecting to server '#{server_name}'...")

    # Attempt to start/connect to server
    case ServerSupervisor.start_server(server_name) do
      {:ok, pid} ->
        # Update state with connection
        updated_connections = Map.put(state.connected_servers, server_name, pid)
        new_state = %{state | current_server: server_name, connected_servers: updated_connections}

        CLI.print_success("Connected to '#{server_name}'")
        {:ok, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp disconnect_from_server(server_name, state) do
    CLI.print_info("Disconnecting from server '#{server_name}'...")

    case ServerSupervisor.stop_server(server_name) do
      :ok ->
        # Update state
        updated_connections = Map.delete(state.connected_servers, server_name)
        new_current = if state.current_server == server_name, do: nil, else: state.current_server

        new_state = %{state | current_server: new_current, connected_servers: updated_connections}

        CLI.print_success("Disconnected from '#{server_name}'")
        {:ok, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Display functions

  defp show_welcome_message(state) do
    IO.puts("")
    IO.puts("🎯 Welcome to MCP Interactive Mode with Prompt Engineering!")
    IO.puts("")
    IO.puts("MCP Commands:")
    IO.puts("  help          - Show available commands")
    IO.puts("  list          - List configured servers")
    IO.puts("  connect <srv> - Connect to a server")
    IO.puts("  tools         - List tools for current server")
    IO.puts("  call <tool>   - Call a tool")
    IO.puts("")
    IO.puts("Prompt Engineering Commands:")
    IO.puts("  prompt        - Prompt management")
    IO.puts("  template      - Template management")
    IO.puts("  experiment    - Experiment management")
    IO.puts("  workspace     - Workspace management")
    IO.puts("  analyze       - Analysis tools")
    IO.puts("  docs          - Documentation tools")
    IO.puts("")
    IO.puts("  exit          - Exit interactive mode")
    IO.puts("")

    if state.current_server do
      IO.puts("Auto-connecting to: #{state.current_server}")
    else
      IO.puts("Type 'list' to see available servers, then 'connect <server>' to get started.")
    end

    IO.puts("")
  end

  defp show_shell_welcome(state) do
    IO.puts("")
    IO.puts("🐚 MCP Shell Mode - Enhanced Interactive Experience")
    IO.puts("")
    IO.puts("Features enabled:")
    if state.auto_complete, do: IO.puts("  ✅ Auto-completion")
    if state.history, do: IO.puts("  ✅ Command history")
    IO.puts("  ✅ Multi-server management")
    IO.puts("")
    IO.puts("Type 'help' for commands or 'exit' to quit.")
    IO.puts("")
  end

  defp show_repl_welcome(_state) do
    IO.puts("")
    IO.puts("🔄 MCP REPL Mode - Read-Eval-Print Loop")
    IO.puts("")
    IO.puts("REPL Features:")
    IO.puts("  • Variable assignment: var_name = value")
    IO.puts("  • Variable reference: $var_name")
    IO.puts("  • REPL commands: :command args")
    IO.puts("  • Expression evaluation")
    IO.puts("")
    IO.puts("Type ':help' for commands or ':exit' to quit.")
    IO.puts("")
  end

  defp show_interactive_help do
    IO.puts("")
    IO.puts("Interactive Commands:")
    IO.puts("")
    IO.puts("MCP Commands:")
    IO.puts("  help [topic]         - Show help (topics: servers, tools, config, prompts)")
    IO.puts("  list [servers|connected|<name>] - List servers or show details")
    IO.puts("  connect <server>     - Connect to MCP server")
    IO.puts("  disconnect [server]  - Disconnect from server")
    IO.puts("  status               - Show connection status")
    IO.puts("  tools [server]       - List available tools")
    IO.puts("  call <tool> [args]   - Call a tool on current server")
    IO.puts("")
    IO.puts("Prompt Engineering Commands:")
    IO.puts("  prompt <action> [name] [options] - Manage prompts (create, list, show, edit, delete)")
    IO.puts("  template <action> [name] [options] - Manage templates (create, list, show)")
    IO.puts("  experiment <action> [name] [options] - Manage experiments (create, run, status)")
    IO.puts("  workspace <action> [name] [options] - Manage workspaces (create, list, switch)")
    IO.puts("  analyze <type> [target] [options] - Analysis tools (prompt, performance)")
    IO.puts("  docs <action> [target] [options] - Documentation tools (generate, export)")
    IO.puts("")
    IO.puts("System Commands:")
    IO.puts("  history              - Show command history")
    IO.puts("  clear                - Clear screen")
    IO.puts("  config [reload]      - Show/reload configuration")
    IO.puts("  set <key> <value>    - Set session variable")
    IO.puts("  get <key>            - Get session variable")
    IO.puts("  exit/quit            - Exit interactive mode")
    IO.puts("")
  end

  defp show_topic_help(topic) do
    case topic do
      "servers" ->
        IO.puts("")
        IO.puts("Server Management:")
        IO.puts("  list servers    - Show all configured servers")
        IO.puts("  list connected  - Show currently connected servers")
        IO.puts("  connect <name>  - Connect to a server")
        IO.puts("  disconnect      - Disconnect current server")
        IO.puts("  status          - Show connection status")
        IO.puts("")

      "tools" ->
        IO.puts("")
        IO.puts("Tool Management:")
        IO.puts("  tools           - List tools for current server")
        IO.puts("  tools <server>  - List tools for specific server")
        IO.puts("  call <tool>     - Call tool with no arguments")
        IO.puts("  call <tool> arg1 arg2 - Call tool with arguments")
        IO.puts("")

      "config" ->
        IO.puts("")
        IO.puts("Configuration:")
        IO.puts("  config          - Show current configuration")
        IO.puts("  config reload   - Reload configuration from file")
        IO.puts("  set <key> <val> - Set session variable")
        IO.puts("  get <key>       - Get session variable")
        IO.puts("")

      "prompts" ->
        IO.puts("")
        IO.puts("Prompt Engineering:")
        IO.puts("  prompt create <name>    - Create new prompt")
        IO.puts("  prompt list             - List all prompts")
        IO.puts("  prompt show <name>      - Show prompt details")
        IO.puts("  template list           - List templates")
        IO.puts("  experiment create <name> - Create experiment")
        IO.puts("  workspace create <name> - Create workspace")
        IO.puts("  analyze prompt <name>   - Analyze prompt")
        IO.puts("  docs generate           - Generate documentation")
        IO.puts("")

      _ ->
        CLI.print_error("Unknown help topic: #{topic}")
        IO.puts("Available topics: servers, tools, config, prompts")
    end
  end

  defp list_all_servers(_state) do
    case Config.load_configuration() do
      {:ok, config} ->
        if map_size(config.servers) == 0 do
          IO.puts("No servers configured")
        else
          IO.puts("")
          IO.puts("Configured servers:")

          Enum.each(config.servers, fn {name, server} ->
            transport = get_transport_display(server)
            enabled = if Map.get(server, :enabled, true), do: "✅", else: "⭕"
            IO.puts("  #{enabled} #{name} (#{transport})")
          end)
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{inspect(reason)}")
    end
  end

  defp list_connected_servers(state) do
    if map_size(state.connected_servers) == 0 do
      IO.puts("No servers currently connected")
    else
      IO.puts("")
      IO.puts("Connected servers:")

      Enum.each(state.connected_servers, fn {name, pid} ->
        status = if Process.alive?(pid), do: "✅ Active", else: "❌ Dead"
        current = if name == state.current_server, do: " (current)", else: ""
        IO.puts("  #{name}: #{status}#{current}")
      end)
    end
  end

  defp show_server_details(server_name, _state) do
    case Config.load_configuration() do
      {:ok, config} ->
        case Map.get(config.servers, server_name) do
          nil ->
            CLI.print_error("Server '#{server_name}' not found")

          server ->
            IO.puts("")
            IO.puts("Server: #{server_name}")
            IO.puts("  Transport: #{get_transport_display(server)}")
            IO.puts("  Enabled: #{Map.get(server, :enabled, true)}")
            IO.puts("  Trust Level: #{Map.get(server, :trust_level, :medium)}")

            capabilities = Map.get(server, :capabilities, %{})
            IO.puts("  Capabilities:")
            IO.puts("    Tools: #{Map.get(capabilities, :tools, false)}")
            IO.puts("    Resources: #{Map.get(capabilities, :resources, false)}")
            IO.puts("    Prompts: #{Map.get(capabilities, :prompts, false)}")
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{inspect(reason)}")
    end
  end

  defp show_connection_status(state) do
    IO.puts("")
    IO.puts("Connection Status:")

    case state.current_server do
      nil ->
        IO.puts("  Current server: None")

      server_name ->
        IO.puts("  Current server: #{server_name}")

        case Map.get(state.connected_servers, server_name) do
          nil ->
            IO.puts("  Status: Not connected")

          pid ->
            status = if Process.alive?(pid), do: "Connected", else: "Dead process"
            IO.puts("  Status: #{status}")
        end
    end

    connected_count = map_size(state.connected_servers)
    IO.puts("  Total connected: #{connected_count}")

    if state.repl_mode do
      var_count = map_size(Map.get(state, :variables, %{}))
      IO.puts("  Variables: #{var_count}")
    end
  end

  defp list_server_tools(server_name, state) do
    case Map.get(state.connected_servers, server_name) do
      nil ->
        CLI.print_error("Server '#{server_name}' is not connected")

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          # Request tools from server
          case GenServer.call(pid, :list_tools, 5000) do
            {:ok, tools} ->
              if Enum.empty?(tools) do
                IO.puts("No tools available on '#{server_name}'")
              else
                IO.puts("")
                IO.puts("Tools available on '#{server_name}':")

                Enum.each(tools, fn tool ->
                  IO.puts("  • #{tool.name}: #{Map.get(tool, :description, "No description")}")
                end)
              end

            {:error, reason} ->
              CLI.print_error("Failed to list tools: #{inspect(reason)}")
          end
        else
          CLI.print_error("Server '#{server_name}' process is not alive")
        end

      _ ->
        CLI.print_error("Invalid server process for '#{server_name}'")
    end
  end

  defp call_server_tool(server_name, tool_name, tool_args, state) do
    case Map.get(state.connected_servers, server_name) do
      nil ->
        CLI.print_error("Server '#{server_name}' is not connected")

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          # Prepare tool arguments
          parsed_args = parse_tool_arguments(tool_args)

          IO.puts("Calling '#{tool_name}' on '#{server_name}' with args: #{inspect(parsed_args)}")

          # Call tool on server
          case GenServer.call(pid, {:call_tool, tool_name, parsed_args}, 30_000) do
            {:ok, result} ->
              IO.puts("")
              IO.puts("Tool result:")
              IO.puts(format_tool_result(result))

            {:error, reason} ->
              CLI.print_error("Tool call failed: #{inspect(reason)}")
          end
        else
          CLI.print_error("Server '#{server_name}' process is not alive")
        end

      _ ->
        CLI.print_error("Invalid server process for '#{server_name}'")
    end
  end

  defp show_command_history(state) do
    if Enum.empty?(state.command_history) do
      IO.puts("No command history")
    else
      IO.puts("")
      IO.puts("Command History (most recent first):")

      state.command_history
      # Show last 20 commands
      |> Enum.take(20)
      |> Enum.with_index(1)
      |> Enum.each(fn {command, index} ->
        IO.puts("  #{index}. #{command}")
      end)
    end
  end

  defp show_current_config(_state) do
    case Config.load_configuration() do
      {:ok, config} ->
        IO.puts("")
        IO.puts("Current Configuration:")
        IO.puts("  Version: #{Map.get(config, :version, "unknown")}")
        IO.puts("  Servers: #{map_size(config.servers)}")

        global = Map.get(config, :global, %{})
        IO.puts("  Global timeout: #{Map.get(global, :timeout, "default")}ms")
        IO.puts("  Max retries: #{Map.get(global, :max_retries, "default")}")

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{inspect(reason)}")
    end
  end

  defp reload_configuration(state) do
    case Config.reload_configuration() do
      {:ok, _config} ->
        CLI.print_success("Configuration reloaded successfully")

      {:error, reason} ->
        CLI.print_error("Failed to reload configuration: #{inspect(reason)}")
    end

    state
  end

  # Utility functions

  defp get_transport_display(server) do
    transport = Map.get(server, :transport, %{})

    case Map.get(transport, :type) do
      :stdio -> "stdio"
      :http -> "http"
      :sse -> "sse"
      other -> "#{other}"
    end
  end

  defp parse_tool_arguments(args) do
    # Simple argument parsing - in real implementation would be more sophisticated
    Enum.map(args, fn arg ->
      cond do
        String.starts_with?(arg, "\"") && String.ends_with?(arg, "\"") ->
          String.slice(arg, 1..-2//1)

        arg in ["true", "false"] ->
          String.to_atom(arg)

        Integer.parse(arg) != :error ->
          {int, _} = Integer.parse(arg)
          int

        Float.parse(arg) != :error ->
          {float, _} = Float.parse(arg)
          float

        true ->
          arg
      end
    end)
  end

  defp format_tool_result(result) do
    case result do
      result when is_binary(result) -> result
      result -> inspect(result, pretty: true, width: 80)
    end
  end

  defp set_session_variable(state, key, value) do
    if Map.has_key?(state, :variables) do
      updated_variables = Map.put(state.variables, key, value)
      %{state | variables: updated_variables}
    else
      state
    end
  end

  defp get_session_variable(state, key) do
    Map.get(state, :variables, %{}) |> Map.get(key, :undefined)
  end

  defp load_command_history do
    # In real implementation, would load from persistent storage
    []
  end

  defp handle_exit(state) do
    if Map.get(state, :shell_mode, false) do
      save_command_history(state.command_history)
    end

    # Disconnect all servers
    Enum.each(state.connected_servers, fn {name, _pid} ->
      ServerSupervisor.stop_server(name)
    end)

    CLI.print_info("Goodbye! 👋")
    {:ok, :exited}
  end

  defp save_command_history(_history) do
    # In real implementation, would save to persistent storage
    :ok
  end
end
