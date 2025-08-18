defmodule TheMaestro.MCP.CLI.Commands.Tools do
  @moduledoc """
  Tools command for MCP CLI.

  Provides functionality to list, execute, and manage tools from MCP servers.
  """

  alias TheMaestro.MCP.{Config, ConnectionManager}
  alias TheMaestro.MCP.CLI
  alias TheMaestro.MCP.CLI.Formatters.YamlFormatter

  @doc """
  List available tools from MCP servers.
  """
  def list_tools(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case parse_list_args(args, options) do
      {:ok, server_filter} ->
        list_server_tools(server_filter, options)

      {:error, reason} ->
        CLI.print_error(reason)
        {:error, reason}
    end
  end

  @doc """
  Execute a tool from an MCP server.
  """
  def execute_tool(args, options) do
    case parse_execute_args(args, options) do
      {:ok, tool_name, server_name, params} ->
        run_tool(tool_name, server_name, params, options)

      {:error, reason} ->
        CLI.print_error(reason)
        {:error, reason}
    end
  end

  @doc """
  Debug tool execution.
  """
  def debug_tool(args, options) do
    # Add debug flag and execute tool
    debug_options = Map.put(options, :debug, true)
    execute_tool(args, debug_options)
  end

  @doc """
  Trace tool execution with full details.
  """
  def trace_tool(args, options) do
    # Add trace flag and execute tool
    trace_options = Map.merge(options, %{debug: true, trace: true, verbose: true})
    execute_tool(args, trace_options)
  end

  @doc """
  Show help for the tools command.
  """
  def show_help do
    IO.puts("""
    MCP Tools Management

    Usage:
      maestro mcp tools [OPTIONS]                    # List available tools
      maestro mcp run <tool> [PARAMS] [OPTIONS]      # Execute tool
      maestro mcp debug <tool> [PARAMS] [OPTIONS]    # Debug tool execution
      maestro mcp trace <tool> [PARAMS] [OPTIONS]    # Trace tool execution

    List Tools Options:
      --server <name>          Show tools from specific server only
      --available              Show only available (connected) tools
      --describe <tool>        Show detailed description of specific tool
      --format <format>        Output format (table, json, yaml)

    Execute Tool Options:
      --server <name>          Execute tool from specific server
      --timeout <ms>           Tool execution timeout
      --no-confirm             Skip confirmation prompts

    Tool Parameters:
      Tools can accept parameters in JSON format:
        maestro mcp run read_file '{"path": "/tmp/test.txt"}'
        maestro mcp run weather '{"location": "New York", "units": "metric"}'

    Examples:
      maestro mcp tools                              # List all available tools
      maestro mcp tools --server fileServer         # List tools from specific server
      maestro mcp tools --describe read_file        # Describe specific tool
      maestro mcp run read_file '{"path": "/etc/hosts"}'
      maestro mcp debug slow_tool '{"param": "value"}'  # Debug tool execution
      maestro mcp trace complex_tool '{}'            # Full execution trace
    """)
  end

  ## Private Functions

  defp parse_list_args(args, options) do
    server_filter = Map.get(options, :server)
    {:ok, server_filter}
  end

  defp parse_execute_args(args, options) do
    case args do
      [] ->
        {:error, "Tool name is required. Use --help for usage information."}

      [tool_name] ->
        {:ok, tool_name, Map.get(options, :server), %{}}

      [tool_name, params_json | _] ->
        case Jason.decode(params_json) do
          {:ok, params} ->
            {:ok, tool_name, Map.get(options, :server), params}

          {:error, _} ->
            {:error, "Invalid JSON parameters. Use valid JSON format."}
        end
    end
  end

  defp list_server_tools(server_filter, options) do
    case Config.get_configuration() do
      {:ok, config} ->
        servers = get_in(config, ["mcpServers"]) || %{}

        tools_info = collect_tools_info(servers, server_filter, options)

        if Map.get(options, :describe) do
          describe_specific_tool(Map.get(options, :describe), tools_info, options)
        else
          display_tools_list(tools_info, options)
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp collect_tools_info(servers, server_filter, options) do
    servers
    |> filter_servers(server_filter)
    |> Enum.flat_map(fn {server_id, _server_config} ->
      case get_server_tools(server_id, options) do
        {:ok, tools} ->
          Enum.map(tools, fn tool ->
            Map.merge(tool, %{server_id: server_id})
          end)

        {:error, _reason} ->
          []
      end
    end)
  end

  defp filter_servers(servers, nil), do: servers

  defp filter_servers(servers, server_filter) do
    case Map.get(servers, server_filter) do
      nil -> []
      server_config -> [{server_filter, server_config}]
    end
  end

  defp get_server_tools(server_id, options) do
    if Map.get(options, :available, false) do
      # Only get tools from connected servers
      case ConnectionManager.get_connection(ConnectionManager, server_id) do
        {:ok, _connection_info} ->
          ConnectionManager.get_server_tools(ConnectionManager, server_id)

        {:error, _reason} ->
          {:error, :not_connected}
      end
    else
      # Try to get tools, but don't filter by connection status
      ConnectionManager.get_server_tools(ConnectionManager, server_id)
    end
  end

  defp display_tools_list(tools_info, options) do
    if Enum.empty?(tools_info) do
      CLI.print_info("No tools found.")
      :ok
    end

    format = CLI.get_output_format(options)

    case format do
      "json" ->
        output = Jason.encode!(%{tools: tools_info}, pretty: true)
        IO.puts(output)

      "yaml" ->
        output = YamlFormatter.format(%{tools: tools_info})
        IO.puts(output)

      _ ->
        display_tools_table(tools_info, options)
    end
  end

  defp display_tools_table(tools_info, options) do
    headers = ["Tool Name", "Server", "Description"]

    rows =
      Enum.map(tools_info, fn tool ->
        [
          Map.get(tool, :name) || Map.get(tool, "name", "Unknown"),
          tool.server_id,
          truncate_text(Map.get(tool, :description) || Map.get(tool, "description", ""), 50)
        ]
      end)

    display_simple_table(headers, rows)

    unless CLI.is_quiet?(options) do
      IO.puts("")

      IO.puts(
        "Total: #{length(tools_info)} tools from #{count_unique_servers(tools_info)} servers"
      )
    end
  end

  defp describe_specific_tool(tool_name, tools_info, options) do
    case Enum.find(tools_info, fn tool ->
           (Map.get(tool, :name) || Map.get(tool, "name")) == tool_name
         end) do
      nil ->
        CLI.print_error("Tool '#{tool_name}' not found.")

      tool ->
        display_tool_details(tool, options)
    end
  end

  defp display_tool_details(tool, options) do
    tool_name = Map.get(tool, :name) || Map.get(tool, "name", "Unknown")

    IO.puts("")
    IO.puts("Tool Details: #{tool_name}")
    IO.puts("#{String.duplicate("=", String.length("Tool Details: #{tool_name}"))}")
    IO.puts("")

    IO.puts("Name: #{tool_name}")
    IO.puts("Server: #{tool.server_id}")

    description =
      Map.get(tool, :description) || Map.get(tool, "description", "No description available")

    IO.puts("Description: #{description}")

    # Show input schema if available
    if input_schema = Map.get(tool, :input_schema) || Map.get(tool, "inputSchema") do
      IO.puts("")
      IO.puts("Input Schema:")

      if CLI.is_verbose?(options) do
        IO.puts(Jason.encode!(input_schema, pretty: true))
      else
        display_schema_summary(input_schema)
      end
    end

    IO.puts("")
  end

  defp display_schema_summary(schema) when is_map(schema) do
    case Map.get(schema, "properties") do
      properties when is_map(properties) ->
        IO.puts("Parameters:")

        Enum.each(properties, fn {param_name, param_info} ->
          param_type = Map.get(param_info, "type", "unknown")
          param_desc = Map.get(param_info, "description", "")
          required = Map.get(schema, "required", []) |> Enum.member?(param_name)
          required_marker = if required, do: " (required)", else: ""

          if param_desc != "" do
            IO.puts("  #{param_name} (#{param_type})#{required_marker}: #{param_desc}")
          else
            IO.puts("  #{param_name} (#{param_type})#{required_marker}")
          end
        end)

      _ ->
        IO.puts("No parameter details available")
    end
  end

  defp display_schema_summary(_schema) do
    IO.puts("Schema format not recognized")
  end

  defp run_tool(tool_name, server_name, params, options) do
    CLI.print_if_verbose("Executing tool '#{tool_name}'...", options)

    # Find server if not specified
    server_name = server_name || find_server_for_tool(tool_name, options)

    unless server_name do
      CLI.print_error("Tool '#{tool_name}' not found or server not specified.")
      :ok
    end

    # Confirm execution unless --no-confirm is specified
    unless Map.get(options, :no_confirm, false) or should_skip_confirmation?(tool_name, params) do
      unless confirm_tool_execution(tool_name, server_name, params) do
        CLI.print_info("Tool execution cancelled.")
        :ok
      end
    end

    # Execute the tool
    timeout = Map.get(options, :timeout, 30_000)

    case execute_tool_on_server(server_name, tool_name, params, timeout, options) do
      {:ok, result} ->
        display_tool_result(tool_name, result, options)

      {:error, reason} ->
        CLI.print_error("Tool execution failed: #{reason}")
    end
  end

  defp find_server_for_tool(tool_name, _options) do
    # Search all connected servers for the tool
    case Config.get_configuration() do
      {:ok, config} ->
        servers = get_in(config, ["mcpServers"]) || %{}

        Enum.find_value(servers, fn {server_id, _server_config} ->
          case ConnectionManager.get_server_tools(ConnectionManager, server_id) do
            {:ok, tools} ->
              tool_exists =
                Enum.any?(tools, fn tool ->
                  (Map.get(tool, :name) || Map.get(tool, "name")) == tool_name
                end)

              if tool_exists, do: server_id, else: nil

            {:error, _} ->
              nil
          end
        end)

      {:error, _} ->
        nil
    end
  end

  defp should_skip_confirmation?(_tool_name, _params) do
    # Skip confirmation for read-only tools or simple operations
    false
  end

  defp confirm_tool_execution(tool_name, server_name, params) do
    IO.puts("")
    IO.puts("Tool Execution Confirmation:")
    IO.puts("  Tool: #{tool_name}")
    IO.puts("  Server: #{server_name}")

    unless Enum.empty?(params) do
      IO.puts("  Parameters:")
      display_params_summary(params)
    end

    IO.puts("")
    IO.write("Execute this tool? [y/N]: ")

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

  defp display_params_summary(params) when is_map(params) do
    Enum.each(params, fn {key, value} ->
      IO.puts("    #{key}: #{inspect(value)}")
    end)
  end

  defp display_params_summary(params) do
    IO.puts("    #{inspect(params)}")
  end

  defp execute_tool_on_server(server_name, tool_name, params, timeout, options) do
    if Map.get(options, :debug) or Map.get(options, :trace) do
      CLI.print_if_verbose(
        "Debug mode: Tool execution details will be shown",
        options
      )
    end

    start_time = System.monotonic_time(:millisecond)

    result =
      ConnectionManager.execute_tool(ConnectionManager, server_name, tool_name, params, timeout)

    end_time = System.monotonic_time(:millisecond)
    execution_time = end_time - start_time

    if Map.get(options, :debug) or Map.get(options, :trace) do
      CLI.print_if_verbose("Execution time: #{execution_time}ms", options)
    end

    result
  end

  defp display_tool_result(tool_name, result, options) do
    format = CLI.get_output_format(options)

    case format do
      "json" ->
        output = Jason.encode!(%{tool: tool_name, result: result}, pretty: true)
        IO.puts(output)

      "yaml" ->
        output =
          YamlFormatter.format(%{tool: tool_name, result: result})

        IO.puts(output)

      _ ->
        display_result_text(tool_name, result, options)
    end
  end

  defp display_result_text(tool_name, result, options) do
    IO.puts("")
    IO.puts("Tool Result: #{tool_name}")
    IO.puts("#{String.duplicate("=", String.length("Tool Result: #{tool_name}"))}")
    IO.puts("")

    case result do
      %{"content" => content} when is_list(content) ->
        Enum.each(content, fn item ->
          display_content_item(item, options)
        end)

      %{"content" => content} ->
        display_content_item(content, options)

      text when is_binary(text) ->
        IO.puts(text)

      data ->
        if CLI.is_verbose?(options) do
          IO.puts(Jason.encode!(data, pretty: true))
        else
          IO.puts(inspect(data))
        end
    end

    IO.puts("")
  end

  defp display_content_item(%{"type" => "text", "text" => text}, _options) do
    IO.puts(text)
  end

  defp display_content_item(item, options) do
    if CLI.is_verbose?(options) do
      IO.puts(Jason.encode!(item, pretty: true))
    else
      IO.puts(inspect(item))
    end
  end

  # Helper functions

  defp count_unique_servers(tools_info) do
    tools_info
    |> Enum.map(& &1.server_id)
    |> Enum.uniq()
    |> length()
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
