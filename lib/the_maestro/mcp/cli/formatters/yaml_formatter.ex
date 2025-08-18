defmodule TheMaestro.MCP.CLI.Formatters.YamlFormatter do
  @moduledoc """
  YAML formatter for MCP CLI output.

  Provides consistent YAML formatting for CLI command outputs with
  proper indentation and structure.
  """

  @doc """
  Format data as YAML string.

  ## Parameters
  - `data` - The data to format (maps, lists, etc.)
  - `opts` - Formatting options (optional)

  ## Options
  - `:indent` - Indentation size (default: 2)

  ## Examples

      iex> YamlFormatter.format(%{name: "test", status: "ok"})
      "name: test\nstatus: ok\n"

      iex> YamlFormatter.format([%{id: 1}, %{id: 2}])
      "- id: 1\n- id: 2\n"
  """
  def format(data, opts \\ []) do
    indent_size = Keyword.get(opts, :indent, 2)
    format_value(data, 0, indent_size)
  end

  @doc """
  Format and print data as YAML to stdout.
  """
  def print(data, opts \\ []) do
    data
    |> format(opts)
    |> IO.puts()
  end

  @doc """
  Format server list data with MCP-specific structure.
  """
  def format_servers(servers, opts \\ []) do
    server_data = %{
      servers: servers,
      count: length(servers),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    format(server_data, opts)
  end

  @doc """
  Format server status data with metadata.
  """
  def format_server_status(server_name, status, opts \\ []) do
    status_data = %{
      server: server_name,
      status: status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    format(status_data, opts)
  end

  @doc """
  Format server tools data.
  """
  def format_server_tools(server_name, tools, opts \\ []) do
    tools_data = %{
      server: server_name,
      tools: tools,
      count: length(tools),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    format(tools_data, opts)
  end

  ## Private Functions

  defp format_value(value, level, indent_size) when is_map(value) do
    if map_size(value) == 0 do
      "{}\n"
    else
      value
      |> Enum.map(fn {k, v} ->
        key = format_key(k)
        formatted_value = format_value(v, level + 1, indent_size)

        if is_binary(formatted_value) and not String.contains?(formatted_value, "\n") do
          # Simple value on same line
          "#{indent(level, indent_size)}#{key}: #{String.trim(formatted_value)}\n"
        else
          # Complex value (multiline)
          "#{indent(level, indent_size)}#{key}:\n#{formatted_value}"
        end
      end)
      |> Enum.join("")
    end
  end

  defp format_value(value, level, indent_size) when is_list(value) do
    if Enum.empty?(value) do
      "[]\n"
    else
      value
      |> Enum.map(fn item ->
        formatted_item = format_value(item, level + 1, indent_size)

        if is_binary(formatted_item) and not String.contains?(formatted_item, "\n") do
          # Simple values on same line as dash
          "#{indent(level, indent_size)}- #{String.trim(formatted_item)}\n"
        else
          # Complex values indented
          "#{indent(level, indent_size)}-\n#{formatted_item}"
        end
      end)
      |> Enum.join("")
    end
  end

  defp format_value(value, _level, _indent_size) when is_binary(value) do
    # Escape special YAML characters and handle multiline strings
    if String.contains?(value, "\n") do
      # Use literal block scalar for multiline
      "|\n" <> indent_multiline(value, 1, 2)
    else
      # Quote strings that might be ambiguous
      if needs_quoting?(value) do
        "\"#{escape_string(value)}\""
      else
        value
      end
    end
  end

  defp format_value(value, _level, _indent_size) when is_number(value) do
    to_string(value)
  end

  defp format_value(value, _level, _indent_size) when is_boolean(value) do
    to_string(value)
  end

  defp format_value(nil, _level, _indent_size) do
    "null"
  end

  defp format_value(value, _level, _indent_size) do
    to_string(value)
  end

  defp format_key(key) when is_atom(key), do: to_string(key)
  defp format_key(key) when is_binary(key), do: key
  defp format_key(key), do: to_string(key)

  defp indent(level, indent_size) do
    String.duplicate(" ", level * indent_size)
  end

  defp indent_multiline(text, level, indent_size) do
    text
    |> String.split("\n")
    |> Enum.map(fn line ->
      if String.trim(line) == "" do
        "\n"
      else
        "#{indent(level, indent_size)}#{line}\n"
      end
    end)
    |> Enum.join("")
  end

  defp needs_quoting?(value) do
    # Quote strings that could be interpreted as other YAML types
    String.match?(value, ~r/^(true|false|null|yes|no|on|off|\d+\.?\d*|[~#\[\]{}|>*&!%@`])/i) or
      String.contains?(value, ":") or
      String.starts_with?(value, " ") or
      String.ends_with?(value, " ")
  end

  defp escape_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\t", "\\t")
  end
end
