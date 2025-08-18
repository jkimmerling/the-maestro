defmodule TheMaestro.MCP.CLI.Formatters.JsonFormatter do
  @moduledoc """
  JSON formatter for MCP CLI output.

  Provides consistent JSON formatting for CLI command outputs with pretty
  printing and configurable options.
  """

  @doc """
  Format data as pretty-printed JSON.

  ## Parameters
  - `data` - The data to format (maps, lists, etc.)
  - `opts` - Formatting options (optional)

  ## Options
  - `:pretty` - Enable pretty printing (default: true)
  - `:indent` - Indentation string (default: "  ")

  ## Examples

      iex> JsonFormatter.format(%{name: "test", status: "ok"})
      "{\n  \"name\": \"test\",\n  \"status\": \"ok\"\n}"

      iex> JsonFormatter.format([%{id: 1}, %{id: 2}])
      "[\n  {\n    \"id\": 1\n  },\n  {\n    \"id\": 2\n  }\n]"
  """
  def format(data, opts \\ []) do
    pretty = Keyword.get(opts, :pretty, true)

    if pretty do
      Jason.encode!(data, pretty: true)
    else
      Jason.encode!(data)
    end
  end

  @doc """
  Format and print data as JSON to stdout.
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
    format(
      %{
        servers: servers,
        count: length(servers),
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      opts
    )
  end

  @doc """
  Format server status data with metadata.
  """
  def format_server_status(server_name, status, opts \\ []) do
    format(
      %{
        server: server_name,
        status: status,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      opts
    )
  end

  @doc """
  Format server tools data.
  """
  def format_server_tools(server_name, tools, opts \\ []) do
    format(
      %{
        server: server_name,
        tools: tools,
        count: length(tools),
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      opts
    )
  end

  @doc """
  Format server metrics data.
  """
  def format_metrics(metrics, opts \\ []) do
    format(
      %{
        metrics: metrics,
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      opts
    )
  end

  @doc """
  Format error response for JSON output.
  """
  def format_error(error_message, details \\ nil, opts \\ []) do
    error_data = %{
      error: true,
      message: error_message,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    error_data =
      if details do
        Map.put(error_data, :details, details)
      else
        error_data
      end

    format(error_data, opts)
  end

  @doc """
  Format success response for JSON output.
  """
  def format_success(message, data \\ nil, opts \\ []) do
    success_data = %{
      success: true,
      message: message,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    success_data =
      if data do
        Map.put(success_data, :data, data)
      else
        success_data
      end

    format(success_data, opts)
  end
end
