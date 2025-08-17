defmodule TheMaestro.MCP.Protocol do
  @moduledoc """
  Core MCP (Model Context Protocol) implementation following JSON-RPC 2.0 specification.

  This module provides functions to create and validate MCP protocol messages,
  handle responses, and format errors according to the MCP specification.
  """

  @protocol_version "2024-11-05"
  @jsonrpc_version "2.0"

  # MCP Error Codes
  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @internal_error -32_603

  @type json_rpc_message :: %{
          jsonrpc: String.t(),
          id: String.t() | nil,
          method: String.t(),
          params: map()
        }

  @type json_rpc_response :: %{
          jsonrpc: String.t(),
          id: String.t(),
          result: map()
        }

  @type json_rpc_error :: %{
          jsonrpc: String.t(),
          id: String.t(),
          error: %{
            code: integer(),
            message: String.t(),
            data: any()
          }
        }

  @doc """
  Create an MCP initialize message.

  ## Parameters

  * `request_id` - Unique identifier for this request
  * `client_info` - Map containing client name and version

  ## Examples

      iex> client_info = %{name: "the_maestro", version: "1.0.0"}
      iex> msg = TheMaestro.MCP.Protocol.initialize("123", client_info)
      iex> msg.method
      "initialize"
      iex> msg.params.protocolVersion
      "2024-11-05"
  """
  @spec initialize(String.t(), map()) :: json_rpc_message()
  def initialize(request_id, client_info) do
    %{
      jsonrpc: @jsonrpc_version,
      id: request_id,
      method: "initialize",
      params: %{
        protocolVersion: @protocol_version,
        capabilities: %{
          tools: %{listChanged: true},
          resources: %{subscribe: true, listChanged: true}
        },
        clientInfo: client_info
      }
    }
  end

  @doc """
  Create a list_tools request message.

  ## Parameters

  * `request_id` - Unique identifier for this request

  ## Examples

      iex> msg = TheMaestro.MCP.Protocol.list_tools("456")
      iex> msg.method
      "tools/list"
  """
  @spec list_tools(String.t()) :: json_rpc_message()
  def list_tools(request_id) do
    %{
      jsonrpc: @jsonrpc_version,
      id: request_id,
      method: "tools/list",
      params: %{}
    }
  end

  @doc """
  Create a call_tool request message.

  ## Parameters

  * `request_id` - Unique identifier for this request
  * `tool_name` - Name of the tool to call
  * `arguments` - Arguments to pass to the tool

  ## Examples

      iex> msg = TheMaestro.MCP.Protocol.call_tool("789", "test_tool", %{param: "value"})
      iex> msg.method
      "tools/call"
      iex> msg.params.name
      "test_tool"
  """
  @spec call_tool(String.t(), String.t(), map()) :: json_rpc_message()
  def call_tool(request_id, tool_name, arguments) do
    %{
      jsonrpc: @jsonrpc_version,
      id: request_id,
      method: "tools/call",
      params: %{
        name: tool_name,
        arguments: arguments
      }
    }
  end

  @doc """
  Validate a JSON-RPC message structure.

  ## Parameters

  * `message` - The message map to validate

  ## Examples

      iex> msg = %{jsonrpc: "2.0", id: "123", method: "test", params: %{}}
      iex> {:ok, validated} = TheMaestro.MCP.Protocol.validate_message(msg)
      iex> validated.jsonrpc
      "2.0"
  """
  @spec validate_message(map()) :: {:ok, json_rpc_message()} | {:error, String.t()}
  def validate_message(message) do
    with :ok <- validate_jsonrpc_field(message),
         :ok <- validate_required_fields(message) do
      {:ok, message}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Format an MCP protocol error response.

  ## Parameters

  * `request_id` - The ID of the request that caused the error
  * `code` - MCP error code
  * `message` - Error message description
  * `data` - Optional additional error data

  ## Examples

      iex> error = TheMaestro.MCP.Protocol.format_error("123", -32600, "Invalid Request")
      iex> error.error.code
      -32600
  """
  @spec format_error(String.t(), integer(), String.t(), any()) :: json_rpc_error()
  def format_error(request_id, code, message, data \\ nil) do
    error = %{
      code: code,
      message: message
    }

    error = if data, do: Map.put(error, :data, data), else: error

    %{
      jsonrpc: @jsonrpc_version,
      id: request_id,
      error: error
    }
  end

  @doc """
  Parse a JSON-RPC response, determining if it's successful or an error.

  ## Parameters

  * `response` - The response map to parse

  ## Examples

      iex> response = %{"jsonrpc" => "2.0", "id" => "123", "result" => %{"status" => "ok"}}
      iex> {:ok, parsed} = TheMaestro.MCP.Protocol.parse_response(response)
      iex> parsed.result.status
      "ok"
  """
  @spec parse_response(map()) :: {:ok, json_rpc_response()} | {:error, map()}
  def parse_response(response) do
    case response do
      %{"error" => error} ->
        # Convert error to atom keys for consistency
        converted_error = convert_error(error)
        {:error, converted_error}

      %{"result" => _result} = resp ->
        # Convert string keys to atoms for consistency
        converted = %{
          jsonrpc: resp["jsonrpc"],
          id: resp["id"],
          result: convert_result(resp["result"])
        }

        {:ok, converted}

      _ ->
        {:error, %{code: @invalid_request, message: "Invalid response format"}}
    end
  end

  # Private helper functions

  defp validate_jsonrpc_field(%{jsonrpc: @jsonrpc_version}), do: :ok
  defp validate_jsonrpc_field(%{"jsonrpc" => @jsonrpc_version}), do: :ok
  defp validate_jsonrpc_field(_), do: {:error, "Invalid or missing jsonrpc field"}

  defp validate_required_fields(message) do
    required_keys = [:method, "method"]

    has_method = Enum.any?(required_keys, &Map.has_key?(message, &1))

    if has_method do
      :ok
    else
      {:error, "Missing required method field"}
    end
  end

  defp convert_result(result) when is_map(result) do
    result
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> Enum.into(%{})
  end

  defp convert_result(result), do: result

  defp convert_error(error) when is_map(error) do
    error
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> Enum.into(%{})
  end

  defp convert_error(error), do: error

  @doc """
  Get standard MCP error codes.
  """
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
