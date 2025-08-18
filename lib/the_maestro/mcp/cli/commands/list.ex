defmodule TheMaestro.MCP.CLI.Commands.List do
  @moduledoc """
  List command for MCP CLI.

  Provides functionality to list all configured MCP servers with various
  display options including status information and available tools.
  """

  alias TheMaestro.MCP.{Config, ConnectionManager}
  alias TheMaestro.MCP.CLI.Formatters.YamlFormatter
  alias TheMaestro.MCP.CLI

  @doc """
  Execute the list command.

  ## Options

  - `--status` - Include connection status information
  - `--tools` - Include available tools for each server
  - `--format` - Output format (table, json, yaml)
  - `--verbose` - Show detailed information
  """
  def execute(_args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case load_servers(options) do
      {:ok, servers} ->
        format_and_display(servers, options)
        {:ok, :success}

      {:error, reason} ->
        CLI.print_error("Failed to load servers: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Show help for the list command.
  """
  def show_help do
    IO.puts("""
    List MCP Servers

    Usage:
      maestro mcp list [OPTIONS]

    Description:
      Lists all configured MCP servers with their basic information.
      Optionally includes status and tool information.

    Options:
      --status              Include connection status information
      --tools               Include available tools for each server
      --format <format>     Output format (table, json, yaml)
      --verbose             Show detailed server information
      --quiet               Minimal output
      --help                Show this help message

    Output Formats:
      table                 Human-readable table (default)
      json                  JSON format for scripting
      yaml                  YAML format for configuration

    Examples:
      maestro mcp list                     # Basic server list
      maestro mcp list --status            # Include connection status
      maestro mcp list --tools             # Include available tools
      maestro mcp list --format json       # JSON output
      maestro mcp list --status --verbose  # Detailed status information
    """)
  end

  ## Private Functions

  defp load_servers(options) do
    with {:ok, config} <- Config.get_configuration() do
      servers = get_in(config, ["mcpServers"]) || %{}

      server_list =
        servers
        |> Enum.map(fn {server_id, server_config} ->
          base_info = %{
            name: server_id,
            transport: detect_transport(server_config),
            trust: Map.get(server_config, "trust", false),
            timeout: Map.get(server_config, "timeout"),
            description: Map.get(server_config, "description", "")
          }

          base_info
          |> add_status_info(server_id, options)
          |> add_tools_info(server_id, options)
          |> add_detailed_info(server_config, options)
        end)

      {:ok, server_list}
    end
  end

  defp detect_transport(server_config) do
    cond do
      Map.has_key?(server_config, "command") -> "stdio"
      Map.has_key?(server_config, "url") -> "sse"
      Map.has_key?(server_config, "httpUrl") -> "http"
      true -> "unknown"
    end
  end

  defp add_status_info(server_info, server_id, options) do
    if Map.get(options, :status) do
      status = get_server_status(server_id)
      Map.merge(server_info, status)
    else
      server_info
    end
  end

  defp get_server_status(server_id) do
    case ConnectionManager.get_connection(ConnectionManager, server_id) do
      {:ok, connection_info} ->
        %{
          status: connection_info.status,
          last_heartbeat: format_heartbeat(connection_info.last_heartbeat),
          uptime: calculate_uptime(connection_info.started_at)
        }

      {:error, :not_found} ->
        %{
          status: :not_connected,
          last_heartbeat: nil,
          uptime: nil
        }

      {:error, _reason} ->
        %{
          status: :error,
          last_heartbeat: nil,
          uptime: nil
        }
    end
  end

  defp add_tools_info(server_info, server_id, options) do
    if Map.get(options, :tools) do
      tools = get_server_tools(server_id)
      Map.put(server_info, :tools, tools)
    else
      server_info
    end
  end

  defp get_server_tools(server_id) do
    case ConnectionManager.get_server_tools(ConnectionManager, server_id) do
      {:ok, tools} ->
        tools
        |> Enum.map(fn tool ->
          %{
            name: Map.get(tool, :name) || Map.get(tool, "name"),
            description: Map.get(tool, :description) || Map.get(tool, "description", "")
          }
        end)

      {:error, _reason} ->
        []
    end
  end

  defp add_detailed_info(server_info, server_config, options) do
    if CLI.verbose?(options) do
      details = %{
        command: Map.get(server_config, "command"),
        args: Map.get(server_config, "args", []),
        url: Map.get(server_config, "url"),
        httpUrl: Map.get(server_config, "httpUrl"),
        env: Map.get(server_config, "env", %{}),
        includeTools: Map.get(server_config, "includeTools", []),
        excludeTools: Map.get(server_config, "excludeTools", []),
        oauth: Map.get(server_config, "oauth"),
        rateLimiting: Map.get(server_config, "rateLimiting")
      }

      # Only include non-nil values
      details =
        details
        |> Enum.filter(fn {_key, value} ->
          value != nil and value != [] and value != %{}
        end)
        |> Enum.into(%{})

      Map.merge(server_info, details)
    else
      server_info
    end
  end

  defp format_and_display(servers, options) do
    format = CLI.get_output_format(options)

    case format do
      "json" ->
        output = Jason.encode!(%{servers: servers}, pretty: true)
        IO.puts(output)

      "yaml" ->
        output = YamlFormatter.format(%{servers: servers})
        IO.puts(output)

      _ ->
        display_table(servers, options)
    end
  end

  defp display_table(servers, options) do
    if Enum.empty?(servers) do
      CLI.print_info("No MCP servers configured.")
      :ok
    else
      headers = build_table_headers(options)
      rows = Enum.map(servers, fn server -> build_table_row(server, options) end)

      # Use simple table formatting for now
      display_simple_table(headers, rows)
    end
  end

  defp build_table_headers(options) do
    base_headers = ["Name", "Transport", "Trust"]

    base_headers
    |> maybe_add_header("Status", Map.get(options, :status))
    |> maybe_add_header("Uptime", Map.get(options, :status))
    |> maybe_add_header("Tools", Map.get(options, :tools))
    |> maybe_add_header("Description", CLI.verbose?(options))
  end

  defp maybe_add_header(headers, header, condition) do
    if condition, do: headers ++ [header], else: headers
  end

  defp build_table_row(server, options) do
    base_row = [
      server.name,
      String.upcase(server.transport),
      format_trust(server.trust)
    ]

    base_row
    |> maybe_add_cell(format_status(Map.get(server, :status)), Map.get(options, :status))
    |> maybe_add_cell(Map.get(server, :uptime, ""), Map.get(options, :status))
    |> maybe_add_cell(format_tools_count(Map.get(server, :tools, [])), Map.get(options, :tools))
    |> maybe_add_cell(
      truncate_text(server.description, 40),
      CLI.verbose?(options)
    )
  end

  defp maybe_add_cell(row, cell, condition) do
    if condition, do: row ++ [cell], else: row
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

  defp format_tools_count(tools) when is_list(tools) do
    count = length(tools)
    if count > 0, do: "#{count} tools", else: "No tools"
  end

  defp format_tools_count(_), do: "Unknown"

  defp format_heartbeat(nil), do: nil

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

  defp truncate_text(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      text
    end
  end

  defp truncate_text(text, _max_length), do: to_string(text)

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
