defmodule TheMaestro.MCP.CLI.Commands.Trust do
  @moduledoc """
  Trust management command for MCP CLI.

  Provides functionality to manage trust levels and permissions for MCP servers.
  """

  @doc """
  Execute the trust command.
  """
  def execute(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case args do
      ["allow", server_name] ->
        set_trust_level(server_name, true, options)

      ["block", server_name] ->
        set_trust_level(server_name, false, options)

      ["list"] ->
        list_trust_levels(options)

      ["reset", server_name] ->
        reset_trust_level(server_name, options)

      _ ->
        TheMaestro.MCP.CLI.print_error("Invalid trust command. Use --help for usage.")
    end
  end

  @doc """
  Show help for the trust command.
  """
  def show_help do
    IO.puts("""
    MCP Trust Management

    Usage:
      maestro mcp trust <subcommand> [OPTIONS]

    Commands:
      allow <server>           Set server as trusted
      block <server>           Set server as untrusted
      list                     List trust levels for all servers
      reset <server>           Reset trust level to default

    Options:
      --level <level>          Set specific trust level (low, medium, high)
      --help                   Show this help message

    Examples:
      maestro mcp trust allow myServer
      maestro mcp trust block dangerousServer
      maestro mcp trust list
      maestro mcp trust reset myServer
    """)
  end

  ## Private Functions

  defp set_trust_level(server_name, trusted, options) do
    action = if trusted, do: "trusted", else: "untrusted"
    TheMaestro.MCP.CLI.print_info("Setting server '#{server_name}' as #{action}...")

    # Load current configuration
    with {:ok, config} <- TheMaestro.MCP.Config.load_configuration(),
         {:ok, server} <- find_server_config(config, server_name) do
      # Determine trust level from options or default
      trust_level =
        cond do
          trusted && Map.has_key?(options, :level) ->
            validate_trust_level(Map.get(options, :level))

          trusted ->
            :high

          true ->
            :none
        end

      case trust_level do
        {:error, reason} ->
          TheMaestro.MCP.CLI.print_error("Invalid trust level: #{reason}")
          {:error, :invalid_level}

        level ->
          # Update server configuration with new trust level
          updated_server = Map.put(server, :trust_level, level)
          updated_servers = Map.put(config.servers, server_name, updated_server)
          updated_config = %{config | servers: updated_servers}

          # Save updated configuration
          case TheMaestro.MCP.Config.save_configuration(updated_config) do
            :ok ->
              TheMaestro.MCP.CLI.print_success(
                "Server '#{server_name}' is now #{action} (level: #{level})"
              )

              # Optionally restart server connection to apply new trust level
              if Map.get(options, :restart, true) do
                restart_server_connection(server_name)
              end

              {:ok, level}

            {:error, reason} ->
              TheMaestro.MCP.CLI.print_error("Failed to save configuration: #{inspect(reason)}")
              {:error, :save_failed}
          end
      end
    else
      {:error, :server_not_found} ->
        TheMaestro.MCP.CLI.print_error("Server '#{server_name}' not found in configuration")
        {:error, :server_not_found}

      {:error, reason} ->
        TheMaestro.MCP.CLI.print_error("Failed to load configuration: #{inspect(reason)}")
        {:error, :config_load_failed}
    end
  end

  defp list_trust_levels(options) do
    TheMaestro.MCP.CLI.print_info("Server trust levels:")

    case TheMaestro.MCP.Config.load_configuration() do
      {:ok, config} when map_size(config.servers) == 0 ->
        IO.puts("  No servers configured")
        {:ok, []}

      {:ok, config} ->
        # Display trust levels in formatted table
        servers_with_trust =
          config.servers
          |> Enum.map(fn {name, server} ->
            trust = Map.get(server, :trust_level, :medium)
            status = get_server_connection_status(name)
            {name, trust, status}
          end)
          |> Enum.sort_by(fn {name, _, _} -> name end)

        # Calculate column widths
        name_width =
          servers_with_trust
          |> Enum.map(fn {name, _, _} -> String.length(name) end)
          |> Enum.max()
          |> max(6)

        # Print header
        IO.puts("")
        IO.puts("  #{"Server" |> String.pad_trailing(name_width)} | Trust Level | Status")
        IO.puts("  #{String.duplicate("-", name_width)} | ----------- | ------")

        # Print server trust information
        Enum.each(servers_with_trust, fn {name, trust, status} ->
          trust_display = format_trust_level(trust)
          status_display = format_connection_status(status)

          IO.puts(
            "  #{name |> String.pad_trailing(name_width)} | #{trust_display |> String.pad_trailing(11)} | #{status_display}"
          )
        end)

        # Show summary
        trust_summary =
          servers_with_trust
          |> Enum.group_by(fn {_, trust, _} -> trust end)
          |> Enum.map(fn {trust, servers} -> {trust, length(servers)} end)
          |> Enum.sort_by(fn {trust, _} -> trust_level_priority(trust) end)

        unless Enum.empty?(trust_summary) do
          IO.puts("")
          IO.puts("  Summary:")

          Enum.each(trust_summary, fn {trust, count} ->
            IO.puts("    #{format_trust_level(trust)}: #{count} server(s)")
          end)
        end

        {:ok, servers_with_trust}

      {:error, reason} ->
        TheMaestro.MCP.CLI.print_error("Failed to load configuration: #{inspect(reason)}")
        {:error, :config_load_failed}
    end
  end

  defp reset_trust_level(server_name, options) do
    TheMaestro.MCP.CLI.print_info("Resetting trust level for server '#{server_name}'...")

    with {:ok, config} <- TheMaestro.MCP.Config.load_configuration(),
         {:ok, server} <- find_server_config(config, server_name) do
      # Reset to default trust level (medium)
      updated_server = Map.put(server, :trust_level, :medium)
      updated_servers = Map.put(config.servers, server_name, updated_server)
      updated_config = %{config | servers: updated_servers}

      case TheMaestro.MCP.Config.save_configuration(updated_config) do
        :ok ->
          TheMaestro.MCP.CLI.print_success("Trust level reset for '#{server_name}' (now: medium)")

          # Optionally restart server connection
          if Map.get(options, :restart, true) do
            restart_server_connection(server_name)
          end

          {:ok, :medium}

        {:error, reason} ->
          TheMaestro.MCP.CLI.print_error("Failed to save configuration: #{inspect(reason)}")
          {:error, :save_failed}
      end
    else
      {:error, :server_not_found} ->
        TheMaestro.MCP.CLI.print_error("Server '#{server_name}' not found in configuration")
        {:error, :server_not_found}

      {:error, reason} ->
        TheMaestro.MCP.CLI.print_error("Failed to load configuration: #{inspect(reason)}")
        {:error, :config_load_failed}
    end
  end

  # Helper functions for trust management

  defp find_server_config(config, server_name) do
    case Map.get(config.servers, server_name) do
      nil -> {:error, :server_not_found}
      server -> {:ok, server}
    end
  end

  defp validate_trust_level(level_str) when is_binary(level_str) do
    case String.downcase(level_str) do
      "none" -> :none
      "low" -> :low
      "medium" -> :medium
      "high" -> :high
      _ -> {:error, "Must be one of: none, low, medium, high"}
    end
  end

  defp validate_trust_level(level) when is_atom(level) do
    if level in [:none, :low, :medium, :high] do
      level
    else
      {:error, "Must be one of: none, low, medium, high"}
    end
  end

  defp format_trust_level(:none), do: "None"
  defp format_trust_level(:low), do: "Low"
  defp format_trust_level(:medium), do: "Medium"
  defp format_trust_level(:high), do: "High"
  defp format_trust_level(other), do: "#{other}"

  defp trust_level_priority(:none), do: 0
  defp trust_level_priority(:low), do: 1
  defp trust_level_priority(:medium), do: 2
  defp trust_level_priority(:high), do: 3

  defp get_server_connection_status(server_name) do
    # Check if server process is running and connected
    case TheMaestro.MCP.ServerSupervisor.get_server_pid(server_name) do
      {:ok, pid} when is_pid(pid) ->
        if Process.alive?(pid) do
          # Try to get server info to check connection health
          case GenServer.call(pid, :get_info, 1000) do
            {:ok, info} ->
              if Map.get(info, :connected, false), do: :connected, else: :disconnected

            _ ->
              :error
          end
        else
          :stopped
        end

      _ ->
        :stopped
    end
  catch
    _, _ -> :unknown
  end

  defp format_connection_status(:connected), do: "Connected"
  defp format_connection_status(:disconnected), do: "Disconnected"
  defp format_connection_status(:stopped), do: "Stopped"
  defp format_connection_status(:error), do: "Error"
  defp format_connection_status(:unknown), do: "Unknown"

  defp restart_server_connection(server_name) do
    TheMaestro.MCP.CLI.print_info(
      "Restarting connection for '#{server_name}' to apply trust changes..."
    )

    case TheMaestro.MCP.ServerSupervisor.restart_server(server_name) do
      :ok ->
        TheMaestro.MCP.CLI.print_success("Connection restarted successfully")

      {:error, reason} ->
        TheMaestro.MCP.CLI.print_warning("Failed to restart connection: #{inspect(reason)}")
    end
  end
end
