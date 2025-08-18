defmodule TheMaestro.MCP.CLI.Formatters.TableFormatter do
  @moduledoc """
  Table formatter for MCP CLI output.

  Provides clean, human-readable table formatting with automatic column
  sizing, alignment, and various display options.
  """

  @doc """
  Format data as a table with headers and rows.

  ## Parameters
  - `data` - List of maps or list of lists representing table data
  - `headers` - List of header strings (optional, inferred from data if not provided)
  - `opts` - Formatting options

  ## Options
  - `:max_width` - Maximum column width (default: 40)
  - `:min_width` - Minimum column width (default: 10)
  - `:padding` - Column padding (default: 1)
  - `:separator` - Column separator (default: " | ")
  - `:border` - Enable table border (default: true)
  - `:truncate` - Truncate long values (default: true)

  ## Examples

      iex> data = [%{name: "server1", status: "connected"}, %{name: "server2", status: "disconnected"}]
      iex> TableFormatter.format(data, ["Name", "Status"])
      "Name    | Status      \n--------|-------------\nserver1 | connected   \nserver2 | disconnected\n"
  """
  def format(data, headers \\ nil, opts \\ [])

  def format([], _headers, _opts) do
    "No data available\n"
  end

  def format(data, headers, opts) when is_list(data) do
    max_width = Keyword.get(opts, :max_width, 40)
    min_width = Keyword.get(opts, :min_width, 10)
    padding = Keyword.get(opts, :padding, 1)
    separator = Keyword.get(opts, :separator, " | ")
    border = Keyword.get(opts, :border, true)
    truncate = Keyword.get(opts, :truncate, true)

    # Convert data to consistent format (list of maps)
    normalized_data = normalize_data(data)

    # Determine headers if not provided
    final_headers = headers || extract_headers(normalized_data)

    # Convert data to rows
    rows = convert_to_rows(normalized_data, final_headers, truncate, max_width)

    # Calculate column widths
    col_widths = calculate_column_widths(final_headers, rows, min_width, max_width)

    # Build table
    build_table(final_headers, rows, col_widths, separator, padding, border)
  end

  @doc """
  Format and print table to stdout.
  """
  def print(data, headers \\ nil, opts \\ []) do
    data
    |> format(headers, opts)
    |> IO.puts()
  end

  @doc """
  Format server list as a table.
  """
  def format_servers(servers, opts \\ []) do
    if Enum.empty?(servers) do
      "No MCP servers configured\n"
    else
      headers = ["Name", "Transport", "Trust", "Status", "Description"]
      format(servers, headers, opts)
    end
  end

  @doc """
  Format server tools as a table.
  """
  def format_server_tools(server_name, tools, opts \\ []) do
    if Enum.empty?(tools) do
      "No tools available for server: #{server_name}\n"
    else
      headers = ["Tool Name", "Description"]

      tools_data =
        tools
        |> Enum.map(fn tool ->
          %{
            "Tool Name" => Map.get(tool, :name) || Map.get(tool, "name", "Unknown"),
            "Description" => Map.get(tool, :description) || Map.get(tool, "description", "")
          }
        end)

      "Server: #{server_name}\n\n" <> format(tools_data, headers, opts)
    end
  end

  @doc """
  Format server status as a table.
  """
  def format_server_status(server_name, status, opts \\ []) do
    status_data = [
      %{"Property" => "Name", "Value" => server_name},
      %{"Property" => "Status", "Value" => format_status_value(Map.get(status, :status))},
      %{"Property" => "Last Heartbeat", "Value" => Map.get(status, :last_heartbeat, "N/A")},
      %{"Property" => "Uptime", "Value" => Map.get(status, :uptime, "N/A")},
      %{"Property" => "Connection", "Value" => Map.get(status, :connection_type, "Unknown")}
    ]

    format(status_data, ["Property", "Value"], opts)
  end

  ## Private Functions

  defp normalize_data(data) when is_list(data) do
    case List.first(data) do
      map when is_map(map) -> data
      list when is_list(list) -> convert_list_to_maps(data)
      _ -> []
    end
  end

  defp normalize_data(_data), do: []

  defp convert_list_to_maps(data) do
    if Enum.all?(data, &is_list/1) and not Enum.empty?(data) do
      headers = List.first(data)

      data
      |> Enum.drop(1)
      |> Enum.map(fn row ->
        headers
        |> Enum.zip(row)
        |> Enum.into(%{})
      end)
    else
      []
    end
  end

  defp extract_headers([first | _]) when is_map(first) do
    first
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp extract_headers(_), do: []

  defp convert_to_rows(data, headers, truncate, max_width) do
    Enum.map(data, fn item ->
      Enum.map(headers, fn header ->
        value = get_value(item, header)
        formatted_value = format_cell_value(value)

        if truncate and String.length(formatted_value) > max_width do
          String.slice(formatted_value, 0, max_width - 3) <> "..."
        else
          formatted_value
        end
      end)
    end)
  end

  defp get_value(item, header) when is_map(item) do
    # Try string key, then atom key
    Map.get(item, header) || Map.get(item, String.to_atom(header))
  end

  defp get_value(_item, _header), do: nil

  defp format_cell_value(nil), do: ""
  defp format_cell_value(value) when is_boolean(value), do: if(value, do: "✓", else: "✗")
  defp format_cell_value(value) when is_list(value), do: "#{length(value)} items"
  defp format_cell_value(value) when is_map(value), do: "#{map_size(value)} fields"
  defp format_cell_value(:connected), do: "🟢 Connected"
  defp format_cell_value(:connecting), do: "🟡 Connecting"
  defp format_cell_value(:disconnected), do: "🔴 Disconnected"
  defp format_cell_value(:not_connected), do: "⚫ Not Connected"
  defp format_cell_value(:error), do: "🔴 Error"
  defp format_cell_value(value), do: to_string(value)

  defp format_status_value(status) do
    format_cell_value(status)
  end

  defp calculate_column_widths(headers, rows, min_width, max_width) do
    all_rows = [headers | rows]

    if Enum.empty?(all_rows) do
      []
    else
      num_cols = length(headers)

      for col_idx <- 0..(num_cols - 1) do
        all_rows
        |> Enum.map(&Enum.at(&1, col_idx, ""))
        |> Enum.map(&String.length(to_string(&1)))
        |> Enum.max()
        |> max(min_width)
        |> min(max_width)
      end
    end
  end

  defp build_table(headers, rows, col_widths, separator, padding, border) do
    pad_str = String.duplicate(" ", padding)

    # Format header
    header_line = format_row(headers, col_widths, separator, pad_str)

    # Create separator line
    separator_line =
      if border do
        col_widths
        |> Enum.map(&String.duplicate("-", &1 + 2 * padding))
        |> Enum.join(String.replace(separator, " ", "-"))
      else
        ""
      end

    # Format data rows
    data_lines =
      rows
      |> Enum.map(&format_row(&1, col_widths, separator, pad_str))
      |> Enum.join("")

    # Combine all parts
    result = header_line

    result =
      if border and separator_line != "" do
        result <> separator_line <> "\n"
      else
        result
      end

    result <> data_lines
  end

  defp format_row(row, col_widths, separator, pad_str) do
    row
    |> Enum.with_index()
    |> Enum.map(fn {cell, idx} ->
      width = Enum.at(col_widths, idx, 10)
      cell_str = to_string(cell)
      padded = String.pad_trailing(cell_str, width)
      pad_str <> padded <> pad_str
    end)
    |> Enum.join(separator)
    |> Kernel.<>("\n")
  end
end
