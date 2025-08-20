defmodule TheMaestro.MCP.ErrorHandler do
  @moduledoc """
  Centralized error handling for MCP protocol operations.

  This module provides functions for handling MCP-specific errors,
  converting errors to appropriate formats, and implementing error
  recovery strategies.
  """

  require Logger

  # MCP Error Codes from JSON-RPC 2.0 and MCP specification
  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @internal_error -32_603

  @type mcp_error :: %{
          code: integer(),
          message: String.t(),
          data: any()
        }

  @type error_context :: %{
          server_name: String.t() | nil,
          method: String.t() | nil,
          transport: atom() | nil,
          request_id: String.t() | nil
        }

  @doc """
  Handle and format an MCP error with context.

  ## Parameters

  * `error` - The error to handle
  * `context` - Context information about where the error occurred

  ## Examples

      iex> context = %{server_name: "test_server", method: "initialize"}
      iex> error = TheMaestro.MCP.ErrorHandler.handle_error(:timeout, context)
      iex> error.code
      -32603
  """
  @spec handle_error(term(), error_context()) :: mcp_error()
  def handle_error(error, context \\ %{})

  def handle_error(:timeout, context) do
    Logger.warning("MCP request timeout: #{format_context(context)}")

    %{
      code: @internal_error,
      message: "Request timeout",
      data: %{
        type: "timeout",
        context: context
      }
    }
  end

  def handle_error(:connection_failed, context) do
    Logger.error("MCP connection failed: #{format_context(context)}")

    %{
      code: @internal_error,
      message: "Connection failed",
      data: %{
        type: "connection_error",
        context: context
      }
    }
  end

  def handle_error(:transport_dead, context) do
    Logger.error("MCP transport process died: #{format_context(context)}")

    %{
      code: @internal_error,
      message: "Transport process terminated",
      data: %{
        type: "transport_error",
        context: context
      }
    }
  end

  def handle_error(:invalid_json, context) do
    Logger.warning("Invalid JSON received: #{format_context(context)}")

    %{
      code: @parse_error,
      message: "Parse error",
      data: %{
        type: "json_parse_error",
        context: context
      }
    }
  end

  def handle_error(:method_not_found, context) do
    Logger.warning("Method not found: #{format_context(context)}")

    %{
      code: @method_not_found,
      message: "Method not found",
      data: %{
        type: "method_not_found",
        context: context
      }
    }
  end

  def handle_error(:invalid_params, context) do
    Logger.warning("Invalid parameters: #{format_context(context)}")

    %{
      code: @invalid_params,
      message: "Invalid params",
      data: %{
        type: "invalid_params",
        context: context
      }
    }
  end

  def handle_error({:http_error, status_code, body}, context) do
    Logger.error("HTTP error #{status_code}: #{format_context(context)}")

    %{
      code: @internal_error,
      message: "HTTP error",
      data: %{
        type: "http_error",
        status_code: status_code,
        body: body,
        context: context
      }
    }
  end

  def handle_error({:json_decode_error, reason}, context) do
    Logger.warning("JSON decode error: #{inspect(reason)}, #{format_context(context)}")

    %{
      code: @parse_error,
      message: "JSON decode error",
      data: %{
        type: "json_decode_error",
        reason: inspect(reason),
        context: context
      }
    }
  end

  def handle_error({:validation_error, field, reason}, context) do
    Logger.warning("Validation error for #{field}: #{reason}, #{format_context(context)}")

    %{
      code: @invalid_request,
      message: "Validation error",
      data: %{
        type: "validation_error",
        field: field,
        reason: reason,
        context: context
      }
    }
  end

  def handle_error(error, context) when is_exception(error) do
    Logger.error(
      "Exception in MCP operation: #{Exception.message(error)}, #{format_context(context)}"
    )

    %{
      code: @internal_error,
      message: "Internal error",
      data: %{
        type: "exception",
        exception: Exception.message(error),
        context: context
      }
    }
  end

  def handle_error(error, context) do
    Logger.error("Unknown MCP error: #{inspect(error)}, #{format_context(context)}")

    %{
      code: @internal_error,
      message: "Unknown error",
      data: %{
        type: "unknown",
        error: inspect(error),
        context: context
      }
    }
  end

  @doc """
  Determine if an error is recoverable and suggest recovery strategy.

  ## Parameters

  * `error` - The MCP error to analyze

  ## Returns

  * `{:recoverable, strategy}` - Error is recoverable with suggested strategy
  * `:not_recoverable` - Error is not recoverable
  """
  @spec recoverable?(mcp_error()) :: {:recoverable, atom()} | :not_recoverable
  def recoverable?(%{code: @internal_error, data: %{type: "timeout"}}) do
    {:recoverable, :retry}
  end

  def recoverable?(%{code: @internal_error, data: %{type: "connection_error"}}) do
    {:recoverable, :reconnect}
  end

  def recoverable?(%{code: @internal_error, data: %{type: "transport_error"}}) do
    {:recoverable, :restart_transport}
  end

  def recoverable?(%{code: @internal_error, data: %{type: "http_error", status_code: code}})
      when code in [500, 502, 503, 504] do
    {:recoverable, :retry}
  end

  def recoverable?(%{code: @parse_error}) do
    # Parse errors are usually not recoverable unless it's a transient issue
    :not_recoverable
  end

  def recoverable?(%{code: @method_not_found}) do
    :not_recoverable
  end

  def recoverable?(%{code: @invalid_params}) do
    :not_recoverable
  end

  def recoverable?(%{code: @invalid_request}) do
    :not_recoverable
  end

  def recoverable?(_error) do
    # Default to not recoverable for unknown errors
    :not_recoverable
  end

  @doc """
  Convert an MCP error to a JSON-RPC error response.

  ## Parameters

  * `error` - The MCP error
  * `request_id` - The request ID to include in the response
  """
  @spec to_json_rpc_error(mcp_error(), String.t() | nil) :: map()
  def to_json_rpc_error(error, request_id \\ nil) do
    TheMaestro.MCP.Protocol.format_error(
      request_id,
      error.code,
      error.message,
      error.data
    )
  end

  @doc """
  Get a human-readable description of an MCP error.

  ## Parameters

  * `error` - The MCP error to describe
  """
  @spec describe_error(mcp_error()) :: String.t()
  def describe_error(%{code: @parse_error}) do
    "The server received invalid JSON that could not be parsed"
  end

  def describe_error(%{code: @invalid_request}) do
    "The JSON sent is not a valid request object"
  end

  def describe_error(%{code: @method_not_found}) do
    "The method does not exist or is not available"
  end

  def describe_error(%{code: @invalid_params}) do
    "Invalid method parameter(s)"
  end

  def describe_error(%{code: @internal_error, data: %{type: "timeout"}}) do
    "The request timed out"
  end

  def describe_error(%{code: @internal_error, data: %{type: "connection_error"}}) do
    "Failed to connect to the MCP server"
  end

  def describe_error(%{code: @internal_error, data: %{type: "transport_error"}}) do
    "The transport layer encountered an error"
  end

  def describe_error(%{code: @internal_error}) do
    "An internal error occurred on the server"
  end

  def describe_error(%{message: message}) do
    message
  end

  def describe_error(_error) do
    "An unknown error occurred"
  end

  # Private functions

  @spec format_context(error_context()) :: String.t()
  defp format_context(context) do
    context
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join(", ")
  end

  @doc """
  Get error code constants for testing and reference.
  """
  @spec error_codes() :: %{
          parse_error: integer(),
          invalid_request: integer(),
          method_not_found: integer(),
          invalid_params: integer(),
          internal_error: integer()
        }
  def error_codes do
    %{
      parse_error: @parse_error,
      invalid_request: @invalid_request,
      method_not_found: @method_not_found,
      invalid_params: @invalid_params,
      internal_error: @internal_error
    }
  end
end
