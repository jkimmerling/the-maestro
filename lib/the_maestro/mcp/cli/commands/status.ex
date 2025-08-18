defmodule TheMaestro.MCP.CLI.Commands.Status do
  @moduledoc """
  Status command for MCP CLI.

  Provides functionality to check server connection status, test connections,
  and perform health checks on MCP servers.
  """

  alias TheMaestro.MCP.{Config, ConnectionManager}
  alias TheMaestro.MCP.Config.ConfigValidator
  alias TheMaestro.MCP.CLI
  alias TheMaestro.MCP.CLI.Formatters.YamlFormatter

  @doc """
  Execute the status command.

  ## Arguments

  - `server_name` - Optional server name to check (if not provided, shows all)

  ## Options

  - `--all` - Show status for all servers
  - `--verbose` - Show detailed status information
  - `--watch` - Continuously monitor status (refresh every 5 seconds)
  """
  def execute(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    if Map.get(options, :watch) do
      watch_status(args, options)
    else
      show_status(args, options)
    end
  end

  @doc """
  Test connection to a specific server.
  """
  def test_connection(args, options) do
    case args do
      [] ->
        CLI.print_error("Server name is required for connection test.")

      [server_name | _] ->
        perform_connection_test(server_name, options)
    end
  end

  @doc """
  Perform health check on servers.
  """
  def health_check(args, options) do
    case args do
      [] ->
        perform_global_health_check(options)

      [server_name | _] ->
        perform_server_health_check(server_name, options)
    end
  end

  @doc """
  Show help for the status command.
  """
  def show_help do
    IO.puts("""
    MCP Server Status

    Usage:
      maestro mcp status [server_name] [OPTIONS]
      maestro mcp test <server_name> [OPTIONS]
      maestro mcp health [server_name] [OPTIONS]

    Description:
      Shows connection status, performance metrics, and health information
      for MCP servers. Can display status for a specific server or all servers.

    Commands:
      status [server]           Show connection status
      test <server>            Test server connection
      health [server]          Perform health check

    Options:
      --all                    Show status for all servers (default if no server specified)
      --verbose                Show detailed status information
      --watch                  Continuously monitor status (refresh every 5 seconds)
      --format <format>        Output format (table, json, yaml)
      --help                   Show this help message

    Status Information Includes:
      - Connection state (connected, disconnected, error)
      - Last heartbeat time
      - Server uptime
      - Available tools count
      - Recent error information
      - Performance metrics (with --verbose)

    Examples:
      maestro mcp status                      # Show all server status
      maestro mcp status myServer             # Show specific server status
      maestro mcp status --verbose            # Show detailed status for all servers
      maestro mcp status --watch              # Monitor status continuously
      maestro mcp test myServer               # Test connection to specific server
      maestro mcp health                      # Global health check
    """)
  end

  ## Private Functions

  defp show_status(args, options) do
    case args do
      [] ->
        show_all_servers_status(options)

      [server_name | _] ->
        show_single_server_status(server_name, options)
    end
  end

  defp show_all_servers_status(options) do
    CLI.print_if_verbose("Checking status for all servers...", options)

    case Config.get_configuration() do
      {:ok, config} ->
        case get_in(config, ["mcpServers"]) do
          servers when is_map(servers) and map_size(servers) > 0 ->
            server_statuses =
              servers
              |> Enum.map(fn {server_id, server_config} ->
                get_server_status_info(server_id, server_config, options)
              end)
              |> Enum.sort_by(fn status -> status.name end)

            display_server_statuses(server_statuses, options)

          _ ->
            CLI.print_info("No MCP servers configured.")
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp show_single_server_status(server_name, options) do
    CLI.print_if_verbose("Checking status for server '#{server_name}'...", options)

    case Config.get_configuration() do
      {:ok, config} ->
        case get_in(config, ["mcpServers", server_name]) do
          nil ->
            CLI.print_error("Server '#{server_name}' not found in configuration.")

          server_config ->
            status_info = get_server_status_info(server_name, server_config, options)
            display_single_server_status(status_info, options)
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp get_server_status_info(server_id, server_config, options) do
    base_info = %{
      name: server_id,
      transport: detect_transport_type(server_config),
      trust: Map.get(server_config, "trust", false),
      timeout: Map.get(server_config, "timeout"),
      description: Map.get(server_config, "description", "")
    }

    # Get connection status from ConnectionManager
    connection_status = get_connection_status(server_id)

    # Get tools information if verbose
    tools_info =
      if CLI.is_verbose?(options) do
        get_server_tools_info(server_id)
      else
        %{}
      end

    # Merge all information
    Map.merge(base_info, Map.merge(connection_status, tools_info))
  end

  defp get_connection_status(server_id) do
    case ConnectionManager.get_connection(ConnectionManager, server_id) do
      {:ok, connection_info} ->
        %{
          status: connection_info.status,
          last_heartbeat: connection_info.last_heartbeat,
          started_at: connection_info.started_at,
          uptime: calculate_uptime(connection_info.started_at),
          error_count: Map.get(connection_info, :error_count, 0),
          last_error: Map.get(connection_info, :last_error)
        }

      {:error, :not_found} ->
        %{
          status: :not_connected,
          last_heartbeat: nil,
          started_at: nil,
          uptime: nil,
          error_count: 0,
          last_error: nil
        }

      {:error, reason} ->
        %{
          status: :error,
          last_heartbeat: nil,
          started_at: nil,
          uptime: nil,
          error_count: 1,
          last_error: reason
        }
    end
  end

  defp get_server_tools_info(server_id) do
    case ConnectionManager.get_server_tools(ConnectionManager, server_id) do
      {:ok, tools} ->
        %{
          tools_count: length(tools),
          tools: tools
        }

      {:error, _reason} ->
        %{
          tools_count: 0,
          tools: []
        }
    end
  end

  defp display_server_statuses(server_statuses, options) do
    format = CLI.get_output_format(options)

    case format do
      "json" ->
        output = Jason.encode!(%{servers: server_statuses}, pretty: true)
        IO.puts(output)

      "yaml" ->
        output = YamlFormatter.format(%{servers: server_statuses})
        IO.puts(output)

      _ ->
        display_status_table(server_statuses, options)
    end
  end

  defp display_single_server_status(status_info, options) do
    format = CLI.get_output_format(options)

    case format do
      "json" ->
        output = Jason.encode!(status_info, pretty: true)
        IO.puts(output)

      "yaml" ->
        output = YamlFormatter.format(status_info)
        IO.puts(output)

      _ ->
        display_single_server_details(status_info, options)
    end
  end

  defp display_status_table(server_statuses, options) do
    if Enum.empty?(server_statuses) do
      CLI.print_info("No servers to display.")
      :ok
    else
      headers = build_status_table_headers(options)
      rows = Enum.map(server_statuses, fn status -> build_status_table_row(status, options) end)

      display_simple_table(headers, rows)

      # Show summary
      unless CLI.is_quiet?(options) do
        show_status_summary(server_statuses)
      end
    end
  end

  defp display_single_server_details(status_info, options) do
    IO.puts("")
    IO.puts("Server Details: #{status_info.name}")
    IO.puts("#{String.duplicate("=", String.length("Server Details: #{status_info.name}"))}")
    IO.puts("")

    IO.puts("Configuration:")
    IO.puts("  Transport: #{String.upcase(status_info.transport)}")
    IO.puts("  Trust: #{format_trust(status_info.trust)}")
    IO.puts("  Timeout: #{status_info.timeout || "default"}ms")

    if status_info.description != "" do
      IO.puts("  Description: #{status_info.description}")
    end

    IO.puts("")
    IO.puts("Connection Status:")
    IO.puts("  Status: #{format_status(status_info.status)}")

    if status_info.uptime do
      IO.puts("  Uptime: #{status_info.uptime}")
    end

    if status_info.last_heartbeat do
      IO.puts("  Last Heartbeat: #{format_heartbeat(status_info.last_heartbeat)}")
    end

    if status_info.error_count > 0 do
      IO.puts("  Error Count: #{status_info.error_count}")

      if status_info.last_error do
        IO.puts("  Last Error: #{status_info.last_error}")
      end
    end

    if Map.has_key?(status_info, :tools_count) do
      IO.puts("")
      IO.puts("Tools:")
      IO.puts("  Available Tools: #{status_info.tools_count}")

      if CLI.is_verbose?(options) and length(status_info.tools) > 0 do
        IO.puts("  Tool List:")

        Enum.each(status_info.tools, fn tool ->
          tool_name = Map.get(tool, :name) || Map.get(tool, "name", "Unknown")
          tool_desc = Map.get(tool, :description) || Map.get(tool, "description", "")

          if tool_desc != "" do
            IO.puts("    - #{tool_name}: #{tool_desc}")
          else
            IO.puts("    - #{tool_name}")
          end
        end)
      end
    end

    IO.puts("")
  end

  defp build_status_table_headers(options) do
    base_headers = ["Name", "Status", "Transport", "Trust"]

    base_headers
    |> maybe_add_header("Uptime", not CLI.is_quiet?(options))
    |> maybe_add_header("Tools", CLI.is_verbose?(options))
    |> maybe_add_header("Errors", CLI.is_verbose?(options))
  end

  defp build_status_table_row(status, options) do
    base_row = [
      status.name,
      format_status(status.status),
      String.upcase(status.transport),
      format_trust(status.trust)
    ]

    base_row
    |> maybe_add_cell(status.uptime || "", not CLI.is_quiet?(options))
    |> maybe_add_cell(Map.get(status, :tools_count, ""), CLI.is_verbose?(options))
    |> maybe_add_cell(status.error_count || 0, CLI.is_verbose?(options))
  end

  defp show_status_summary(server_statuses) do
    total = length(server_statuses)
    connected = Enum.count(server_statuses, fn s -> s.status == :connected end)
    disconnected = total - connected

    IO.puts("")

    IO.puts(
      "Summary: #{total} servers total, #{connected} connected, #{disconnected} disconnected"
    )
  end

  defp watch_status(args, options) do
    IO.puts("Watching server status... (Press Ctrl+C to exit)")
    IO.puts("")

    watch_loop(args, options)
  end

  defp watch_loop(args, options) do
    # Clear screen (ANSI escape sequence)
    IO.write("\e[2J\e[H")

    timestamp = DateTime.utc_now() |> DateTime.to_string()
    IO.puts("MCP Server Status - #{timestamp}")
    IO.puts("#{String.duplicate("=", 50)}")

    show_status(args, Map.put(options, :quiet, true))

    # Wait 5 seconds
    :timer.sleep(5000)

    # Continue watching
    watch_loop(args, options)
  end

  defp perform_connection_test(server_name, options) do
    CLI.print_if_verbose("Testing connection to '#{server_name}'...", options)

    case Config.get_configuration() do
      {:ok, config} ->
        case get_in(config, ["mcpServers", server_name]) do
          nil ->
            CLI.print_error("Server '#{server_name}' not found.")

          server_config ->
            run_connection_test(server_name, server_config, options)
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp run_connection_test(server_name, server_config, options) do
    IO.puts("Testing connection to '#{server_name}'...")
    IO.puts("Transport: #{detect_transport_type(server_config)}")

    # Add server ID for ConnectionManager
    server_config_with_id = Map.put(server_config, :id, server_name)

    start_time = System.monotonic_time(:millisecond)

    case ConnectionManager.test_connection(ConnectionManager, server_config_with_id) do
      {:ok, test_results} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        IO.puts("✓ Connection test passed (#{duration}ms)")

        if CLI.is_verbose?(options) and test_results do
          display_test_results(test_results)
        end

      {:error, reason} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        IO.puts("✗ Connection test failed (#{duration}ms)")
        CLI.print_error("Error: #{reason}")
    end
  end

  defp perform_global_health_check(options) do
    CLI.print_if_verbose("Performing global health check...", options)

    case Config.get_configuration() do
      {:ok, config} ->
        servers = get_in(config, ["mcpServers"]) || %{}

        if map_size(servers) == 0 do
          CLI.print_info("No servers configured for health check.")
        else
          results =
            servers
            |> Enum.map(fn {server_id, server_config} ->
              {server_id, perform_server_health_test(server_id, server_config)}
            end)

          display_health_check_results(results, options)
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp perform_server_health_check(server_name, options) do
    CLI.print_if_verbose(
      "Performing health check for '#{server_name}'...",
      options
    )

    case Config.get_configuration() do
      {:ok, config} ->
        case get_in(config, ["mcpServers", server_name]) do
          nil ->
            CLI.print_error("Server '#{server_name}' not found.")

          server_config ->
            result = perform_server_health_test(server_name, server_config)
            display_single_health_result(server_name, result, options)
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp perform_server_health_test(server_id, server_config) do
    # Perform comprehensive health check
    checks = %{
      connection: test_server_connection(server_id, server_config),
      tools: test_server_tools(server_id),
      performance: test_server_performance(server_id),
      configuration: test_server_configuration(server_config)
    }

    # Calculate overall health score
    passing_checks = Enum.count(checks, fn {_check, result} -> result.status == :pass end)
    total_checks = map_size(checks)
    health_score = if total_checks > 0, do: passing_checks / total_checks * 100, else: 0

    %{
      server_id: server_id,
      health_score: health_score,
      checks: checks,
      overall_status: if(health_score >= 80, do: :healthy, else: :unhealthy)
    }
  end

  defp test_server_connection(server_id, _server_config) do
    case ConnectionManager.get_connection(ConnectionManager, server_id) do
      {:ok, _connection_info} ->
        %{status: :pass, message: "Connection active"}

      {:error, :not_found} ->
        %{status: :warning, message: "Not connected"}

      {:error, reason} ->
        %{status: :fail, message: "Connection error: #{reason}"}
    end
  end

  defp test_server_tools(server_id) do
    case ConnectionManager.get_server_tools(ConnectionManager, server_id) do
      {:ok, tools} when is_list(tools) and length(tools) > 0 ->
        %{status: :pass, message: "#{length(tools)} tools available"}

      {:ok, []} ->
        %{status: :warning, message: "No tools available"}

      {:error, reason} ->
        %{status: :fail, message: "Tools error: #{reason}"}
    end
  end

  defp test_server_performance(server_id) do
    # Simple performance test - measure heartbeat response time
    case ConnectionManager.ping_server(ConnectionManager, server_id) do
      {:ok, response_time} when response_time < 1000 ->
        %{status: :pass, message: "Response time: #{response_time}ms"}

      {:ok, response_time} ->
        %{status: :warning, message: "Slow response: #{response_time}ms"}

      {:error, reason} ->
        %{status: :fail, message: "Performance test failed: #{reason}"}
    end
  end

  defp test_server_configuration(server_config) do
    case ConfigValidator.validate_server_config(
           "health_check",
           server_config
         ) do
      [] ->
        %{status: :pass, message: "Configuration valid"}

      errors ->
        %{status: :fail, message: "Configuration errors: #{length(errors)}"}
    end
  end

  defp display_health_check_results(results, options) do
    IO.puts("Health Check Results:")
    IO.puts("#{String.duplicate("=", 30)}")

    Enum.each(results, fn {server_id, result} ->
      display_single_health_result(server_id, result, options)
    end)

    # Summary
    total_servers = length(results)

    healthy_servers =
      Enum.count(results, fn {_id, result} -> result.overall_status == :healthy end)

    IO.puts("")
    IO.puts("Overall Health: #{healthy_servers}/#{total_servers} servers healthy")
  end

  defp display_single_health_result(server_id, result, options) do
    status_icon =
      case result.overall_status do
        :healthy -> "🟢"
        :unhealthy -> "🔴"
      end

    IO.puts("#{status_icon} #{server_id}: #{result.health_score}% healthy")

    if CLI.is_verbose?(options) do
      Enum.each(result.checks, fn {check_name, check_result} ->
        check_icon =
          case check_result.status do
            :pass -> "  ✓"
            :warning -> "  ⚠"
            :fail -> "  ✗"
          end

        IO.puts("#{check_icon} #{check_name}: #{check_result.message}")
      end)

      IO.puts("")
    end
  end

  defp display_test_results(test_results) do
    IO.puts("")
    IO.puts("Test Results:")

    Enum.each(test_results, fn {key, value} ->
      IO.puts("  #{key}: #{value}")
    end)
  end

  # Helper functions

  defp detect_transport_type(server_config) do
    cond do
      Map.has_key?(server_config, "command") -> "stdio"
      Map.has_key?(server_config, "url") -> "sse"
      Map.has_key?(server_config, "httpUrl") -> "http"
      true -> "unknown"
    end
  end

  defp format_trust(true), do: "✓"
  defp format_trust(false), do: "✗"
  defp format_trust("trusted"), do: "✓"
  defp format_trust("untrusted"), do: "✗"
  defp format_trust(_), do: "?"

  defp format_status(:connected), do: "🟢 Connected"
  defp format_status(:connecting), do: "🟡 Connecting"
  defp format_status(:disconnected), do: "🔴 Disconnected"
  defp format_status(:not_connected), do: "⚫ Not Connected"
  defp format_status(:error), do: "🔴 Error"
  defp format_status(nil), do: "Unknown"
  defp format_status(status), do: to_string(status)

  defp format_heartbeat(nil), do: "Never"

  defp format_heartbeat(timestamp) do
    case DateTime.from_unix(timestamp, :millisecond) do
      {:ok, dt} -> DateTime.to_string(dt)
      _ -> "Invalid"
    end
  end

  defp calculate_uptime(nil), do: nil

  defp calculate_uptime(started_at) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, started_at, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86_400 -> "#{div(diff, 3600)}h #{div(rem(diff, 3600), 60)}m"
      true -> "#{div(diff, 86_400)}d #{div(rem(diff, 86_400), 3600)}h"
    end
  end

  defp maybe_add_header(headers, header, condition) do
    if condition, do: headers ++ [header], else: headers
  end

  defp maybe_add_cell(row, cell, condition) do
    if condition, do: row ++ [to_string(cell)], else: row
  end

  defp display_simple_table(headers, rows) do
    # Calculate column widths
    col_widths = calculate_column_widths(headers, rows)

    # Print headers
    header_line =
      headers
      |> Enum.with_index()
      |> Enum.map(fn {header, idx} ->
        String.pad_trailing(header, Enum.at(col_widths, idx))
      end)
      |> Enum.join(" | ")

    IO.puts(header_line)

    # Print separator
    separator =
      col_widths
      |> Enum.map(&String.duplicate("-", &1))
      |> Enum.join("-|-")

    IO.puts(separator)

    # Print rows
    Enum.each(rows, fn row ->
      row_line =
        row
        |> Enum.with_index()
        |> Enum.map(fn {cell, idx} ->
          String.pad_trailing(to_string(cell), Enum.at(col_widths, idx))
        end)
        |> Enum.join(" | ")

      IO.puts(row_line)
    end)
  end

  defp calculate_column_widths(headers, rows) do
    all_rows = [headers | rows]

    if Enum.empty?(all_rows) do
      []
    else
      num_cols = length(hd(all_rows))

      for col_idx <- 0..(num_cols - 1) do
        all_rows
        |> Enum.map(&Enum.at(&1, col_idx, ""))
        |> Enum.map(&String.length(to_string(&1)))
        |> Enum.max()
        # Minimum column width
        |> max(10)
      end
    end
  end
end
