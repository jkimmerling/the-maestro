defmodule TheMaestro.MCP.CLI.Commands.Remove do
  @moduledoc """
  Remove command for MCP CLI.

  Provides functionality to remove MCP servers from the configuration
  with safety checks and confirmation prompts.
  """

  alias TheMaestro.MCP.{Config, ConnectionManager}
  alias TheMaestro.MCP.CLI

  @doc """
  Execute the remove command.

  ## Arguments

  - `server_name` - Name of the server to remove

  ## Options

  - `--force` - Skip confirmation prompts
  - `--preserve-data` - Keep server data/logs when removing
  """
  def execute(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case parse_remove_args(args, options) do
      {:ok, server_name} ->
        remove_server(server_name, options)

      {:error, reason} ->
        CLI.print_error(reason)
        {:error, reason}
    end
  end

  @doc """
  Show help for the remove command.
  """
  def show_help do
    IO.puts("""
    Remove MCP Server

    Usage:
      maestro mcp remove <server_name> [OPTIONS]

    Description:
      Removes an MCP server from the configuration. This will:
      - Stop any active connections to the server
      - Remove the server from the configuration file
      - Optionally clean up server data and logs

    Options:
      --force               Skip confirmation prompts
      --preserve-data       Keep server data/logs when removing
      --verbose             Show detailed output
      --help                Show this help message

    Safety Features:
      - Confirmation prompt (unless --force is used)
      - Active connection check and graceful shutdown
      - Option to preserve server data and logs

    Examples:
      maestro mcp remove oldServer                    # Remove with confirmation
      maestro mcp remove oldServer --force            # Remove without confirmation
      maestro mcp remove oldServer --preserve-data    # Keep data when removing
    """)
  end

  ## Private Functions

  defp parse_remove_args(args, _options) do
    case args do
      [] ->
        {:error, "Server name is required. Use --help for usage information."}

      [server_name | _rest] ->
        {:ok, server_name}
    end
  end

  defp remove_server(server_name, options) do
    CLI.print_if_verbose("Removing server '#{server_name}'...", options)

    case Config.get_configuration() do
      {:ok, current_config} ->
        case check_server_exists(current_config, server_name) do
          {:ok, server_config} ->
            if should_proceed_with_removal?(server_name, server_config, options) do
              perform_removal(current_config, server_name, server_config, options)
            else
              CLI.print_info("Server removal cancelled.")
            end

          {:error, :not_found} ->
            CLI.print_error("Server '#{server_name}' not found in configuration.")

          {:error, reason} ->
            CLI.print_error("Failed to check server: #{reason}")
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp check_server_exists(config, server_name) do
    case get_in(config, ["mcpServers", server_name]) do
      nil -> {:error, :not_found}
      server_config -> {:ok, server_config}
    end
  end

  defp should_proceed_with_removal?(server_name, server_config, options) do
    if Map.get(options, :force, false) do
      true
    else
      show_removal_summary(server_name, server_config)
      prompt_for_confirmation()
    end
  end

  defp show_removal_summary(server_name, server_config) do
    IO.puts("")
    IO.puts("Server to Remove:")
    IO.puts("  Name: #{server_name}")
    IO.puts("  Transport: #{detect_transport_type(server_config)}")

    if command = Map.get(server_config, "command") do
      IO.puts("  Command: #{command}")
    end

    if url = Map.get(server_config, "url") || Map.get(server_config, "httpUrl") do
      IO.puts("  URL: #{url}")
    end

    IO.puts("  Trust: #{Map.get(server_config, "trust", false)}")

    # Check if server is currently connected
    case check_server_status(server_name) do
      {:connected, info} ->
        IO.puts("  Status: 🟢 Currently Connected")
        IO.puts("  Connection will be stopped before removal.")

      {:disconnected, _} ->
        IO.puts("  Status: ⚫ Not Connected")

      {:error, _} ->
        IO.puts("  Status: Unknown")
    end

    IO.puts("")
  end

  defp check_server_status(server_name) do
    case ConnectionManager.get_connection(ConnectionManager, server_name) do
      {:ok, connection_info} ->
        {:connected, connection_info}

      {:error, :not_found} ->
        {:disconnected, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prompt_for_confirmation do
    IO.write("Are you sure you want to remove this server? [y/N]: ")

    case IO.read(:stdio, :line) do
      {:ok, input} ->
        case String.trim(String.downcase(input)) do
          "y" -> true
          "yes" -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp perform_removal(current_config, server_name, server_config, options) do
    # Step 1: Stop active connection if exists
    CLI.print_if_verbose("Stopping server connection...", options)
    stop_server_connection(server_name, options)

    # Step 2: Remove from configuration
    CLI.print_if_verbose("Updating configuration...", options)

    case remove_from_config(current_config, server_name) do
      {:ok, updated_config} ->
        save_updated_config(updated_config, server_name, server_config, options)

      {:error, reason} ->
        CLI.print_error("Failed to update configuration: #{reason}")
    end
  end

  defp stop_server_connection(server_name, options) do
    case ConnectionManager.stop_connection(ConnectionManager, server_name) do
      :ok ->
        CLI.print_if_verbose("Server connection stopped.", options)

      {:error, :not_found} ->
        CLI.print_if_verbose("Server was not connected.", options)

      {:error, reason} ->
        CLI.print_warning("Warning: Failed to stop server connection: #{reason}")
    end
  end

  defp remove_from_config(config, server_name) do
    case get_in(config, ["mcpServers"]) do
      servers when is_map(servers) ->
        updated_servers = Map.delete(servers, server_name)
        updated_config = put_in(config, ["mcpServers"], updated_servers)
        {:ok, updated_config}

      _ ->
        {:error, "Invalid mcpServers configuration"}
    end
  end

  defp save_updated_config(updated_config, server_name, server_config, options) do
    config_path = get_config_path()

    case Config.save_configuration(updated_config, config_path) do
      :ok ->
        CLI.print_success("Successfully removed server '#{server_name}'")

        unless Map.get(options, :preserve_data, false) do
          cleanup_server_data(server_name, options)
        end

        print_removal_summary(server_name, server_config, options)

      {:error, reason} ->
        CLI.print_error("Failed to save configuration: #{reason}")
    end
  end

  defp cleanup_server_data(server_name, options) do
    CLI.print_if_verbose("Cleaning up server data...", options)

    # Clean up any server-specific data, logs, or cache files
    # This is a placeholder - actual implementation would depend on
    # where server data is stored
    data_paths = [
      "./.maestro/logs/#{server_name}.log",
      "./.maestro/cache/#{server_name}/",
      "./.maestro/data/#{server_name}/"
    ]

    Enum.each(data_paths, fn path ->
      if File.exists?(path) do
        case File.rm_rf(path) do
          {:ok, _} ->
            CLI.print_if_verbose("Cleaned up: #{path}", options)

          {:error, reason} ->
            CLI.print_if_verbose("Could not clean up #{path}: #{reason}", options)
        end
      end
    end)
  end

  defp print_removal_summary(server_name, server_config, options) do
    unless CLI.is_quiet?(options) do
      IO.puts("")
      IO.puts("Removal Summary:")
      IO.puts("  ✓ Server '#{server_name}' removed from configuration")
      IO.puts("  ✓ Active connections stopped")

      if Map.get(options, :preserve_data, false) do
        IO.puts("  ✓ Server data preserved")
      else
        IO.puts("  ✓ Server data cleaned up")
      end

      IO.puts("")
      IO.puts("Use 'maestro mcp list' to see remaining servers.")
    end
  end

  defp detect_transport_type(server_config) do
    cond do
      Map.has_key?(server_config, "command") -> "STDIO"
      Map.has_key?(server_config, "url") -> "SSE"
      Map.has_key?(server_config, "httpUrl") -> "HTTP"
      true -> "Unknown"
    end
  end

  defp get_config_path do
    # Use project-specific config path
    "./.maestro/mcp_settings.json"
  end
end
