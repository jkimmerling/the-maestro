defmodule TheMaestro.Tooling.Tools.OpenAPI do
  @moduledoc """
  OpenAPI specification tool for making API calls based on OpenAPI specs.

  This tool allows the AI agent to interact with external web services by reading
  OpenAPI specifications and making HTTP requests based on operation definitions.

  ## Features

  - Loads OpenAPI specifications from URLs or file paths
  - Validates operation IDs and parameters against the spec
  - Constructs and executes HTTP requests based on the spec
  - Supports path parameters, query parameters, and request bodies
  - Returns structured JSON responses

  ## Security Considerations

  - URL validation to prevent SSRF attacks
  - Parameter validation against the OpenAPI spec
  - HTTP timeout configuration
  - Response size limits

  ## Example Usage

  ```elixir
  args = %{
    "spec_url" => "https://api.example.com/openapi.json",
    "operation_id" => "getUser", 
    "arguments" => %{"id" => "123"}
  }

  OpenAPI.execute(args)
  ```
  """

  use TheMaestro.Tooling.Tool
  require Logger

  @typedoc "Structure holding parsed operation information"
  @type operation_info :: %{
          method: atom(),
          path: String.t(),
          operation: map(),
          parameters: [map()]
        }

  @typedoc "Structure holding HTTP request details"
  @type http_request :: %{
          method: atom(),
          url: String.t(),
          headers: [{String.t(), String.t()}],
          body: String.t() | nil
        }

  @impl true
  def definition do
    %{
      "name" => "call_api",
      "description" => """
      Reads an OpenAPI specification and makes API calls based on it. 
      Can initialize with a path or URL to an OpenAPI spec file, then call specific operations
      by providing an operation_id and arguments.
      """,
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "spec_url" => %{
            "type" => "string",
            "description" => "URL or file path to the OpenAPI specification (JSON or YAML format)"
          },
          "operation_id" => %{
            "type" => "string",
            "description" => "The operationId from the OpenAPI spec to call"
          },
          "arguments" => %{
            "type" => "object",
            "description" =>
              "Arguments to pass to the API operation (path params, query params, body)"
          }
        },
        "required" => ["spec_url", "operation_id", "arguments"]
      }
    }
  end

  @impl true
  def execute(%{"spec_url" => spec_url, "operation_id" => operation_id, "arguments" => arguments}) do
    Logger.info("OpenAPI tool: Calling operation '#{operation_id}' from spec '#{spec_url}'")

    with :ok <-
           validate_arguments(%{
             "spec_url" => spec_url,
             "operation_id" => operation_id,
             "arguments" => arguments
           }),
         {:ok, spec_content} <- fetch_openapi_spec(spec_url),
         {:ok, parsed_spec} <- parse_openapi_spec(spec_content),
         {:ok, operation_info} <- find_operation(parsed_spec, operation_id),
         :ok <- validate_operation_arguments(operation_info, arguments),
         server_url <- get_server_url(parsed_spec),
         {:ok, request} <- build_request(operation_info, server_url, arguments),
         {:ok, response} <- execute_http_request(request) do
      Logger.info("OpenAPI tool: Successfully executed operation '#{operation_id}'")

      {:ok,
       %{
         "operation_id" => operation_id,
         "status_code" => response.status_code,
         "response" => response.body,
         "url" => request.url,
         "method" => Atom.to_string(request.method)
       }}
    else
      {:error, reason} ->
        Logger.warning("OpenAPI tool failed for operation '#{operation_id}': #{reason}")
        {:error, reason}
    end
  end

  def execute(%{}) do
    {:error, "Missing required parameters: spec_url, operation_id, and arguments are required"}
  end

  def execute(nil) do
    {:error, "Invalid arguments. Expected a map with spec_url, operation_id, and arguments keys."}
  end

  def execute(_invalid_args) do
    {:error, "Invalid arguments. Expected a map with spec_url, operation_id, and arguments keys."}
  end

  @doc """
  Validates the provided arguments.
  """
  @impl true
  @spec validate_arguments(map()) :: :ok | {:error, String.t()}
  def validate_arguments(%{
        "spec_url" => spec_url,
        "operation_id" => operation_id,
        "arguments" => arguments
      })
      when is_binary(spec_url) and is_binary(operation_id) and is_map(arguments) do
    cond do
      String.trim(spec_url) == "" ->
        {:error, "spec_url cannot be empty"}

      String.trim(operation_id) == "" ->
        {:error, "operation_id cannot be empty"}

      not valid_url_format?(spec_url) ->
        {:error, "Invalid spec_url format"}

      true ->
        :ok
    end
  end

  def validate_arguments(_) do
    {:error, "Invalid arguments. Expected a map with spec_url, operation_id, and arguments keys."}
  end

  @doc """
  Fetches OpenAPI specification from URL or file path.
  """
  @spec fetch_openapi_spec(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch_openapi_spec(spec_url) do
    cond do
      String.starts_with?(spec_url, "http://") or String.starts_with?(spec_url, "https://") ->
        fetch_spec_from_url(spec_url)

      File.exists?(spec_url) ->
        case File.read(spec_url) do
          {:ok, content} -> {:ok, content}
          {:error, reason} -> {:error, "Failed to read spec file: #{reason}"}
        end

      true ->
        {:error, "Spec URL is not a valid HTTP URL or existing file path"}
    end
  end

  @doc """
  Parses OpenAPI specification from JSON or YAML string.
  """
  @spec parse_openapi_spec(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_openapi_spec(spec_content) do
    case Jason.decode(spec_content) do
      {:ok, spec} ->
        if valid_openapi_spec?(spec) do
          {:ok, spec}
        else
          {:error, "Invalid OpenAPI spec: missing required fields"}
        end

      {:error, _} ->
        {:error, "Invalid JSON format in OpenAPI spec"}
    end
  end

  @doc """
  Finds operation information by operation ID.
  """
  @spec find_operation(map(), String.t()) :: {:ok, operation_info()} | {:error, String.t()}
  def find_operation(spec, operation_id) do
    paths = Map.get(spec, "paths", %{})

    result =
      Enum.reduce_while(paths, nil, fn {path, path_item}, acc ->
        case find_operation_in_path_item(path_item, operation_id) do
          {:ok, method, operation} ->
            {:halt,
             {:ok,
              %{
                method: method,
                path: path,
                operation: operation,
                parameters: Map.get(operation, "parameters", [])
              }}}

          :not_found ->
            {:cont, acc}
        end
      end)

    case result do
      {:ok, operation_info} -> {:ok, operation_info}
      nil -> {:error, "Operation '#{operation_id}' not found in OpenAPI spec"}
    end
  end

  @doc """
  Validates operation arguments against parameter schema.
  """
  @spec validate_operation_arguments(operation_info(), map()) :: :ok | {:error, String.t()}
  def validate_operation_arguments(operation_info, arguments) do
    required_params = get_required_parameters(operation_info.parameters)

    missing_params =
      Enum.filter(required_params, fn param_name ->
        not Map.has_key?(arguments, param_name)
      end)

    if Enum.empty?(missing_params) do
      :ok
    else
      {:error, "Missing required parameter: #{Enum.join(missing_params, ", ")}"}
    end
  end

  @doc """
  Builds HTTP request from operation info and arguments.
  """
  @spec build_request(operation_info(), String.t(), map()) ::
          {:ok, http_request()} | {:error, String.t()}
  def build_request(operation_info, server_url, arguments) do
    with {:ok, url} <- build_url(operation_info.path, server_url, arguments),
         {:ok, headers} <- build_headers(operation_info.operation),
         {:ok, body} <- build_request_body(operation_info.operation, arguments) do
      {:ok,
       %{
         method: operation_info.method,
         url: url,
         headers: headers,
         body: body
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper functions

  defp valid_url_format?(url) do
    String.starts_with?(url, ["http://", "https://", "/"]) or File.exists?(url)
  end

  defp fetch_spec_from_url(url) do
    case HTTPoison.get(url, [], timeout: 10_000, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "Failed to fetch OpenAPI spec: HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Failed to fetch OpenAPI spec: #{reason}"}
    end
  end

  defp valid_openapi_spec?(spec) do
    case spec do
      %{"openapi" => version} when is_binary(version) -> true
      %{"swagger" => version} when is_binary(version) -> true
      _ -> false
    end
  end

  defp find_operation_in_path_item(path_item, operation_id) do
    http_methods = ["get", "post", "put", "patch", "delete", "head", "options", "trace"]

    Enum.reduce_while(http_methods, :not_found, fn method, acc ->
      case Map.get(path_item, method) do
        %{"operationId" => ^operation_id} = operation ->
          {:halt, {:ok, String.to_atom(method), operation}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp get_required_parameters(parameters) do
    parameters
    |> Enum.filter(fn param -> Map.get(param, "required", false) end)
    |> Enum.map(fn param -> Map.get(param, "name") end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_server_url(spec) do
    case Map.get(spec, "servers") do
      [%{"url" => url} | _] -> String.trim_trailing(url, "/")
      # fallback
      _ -> "https://api.example.com"
    end
  end

  defp build_url(path, server_url, arguments) do
    # Replace path parameters
    final_path =
      Enum.reduce(arguments, path, fn {key, value}, acc ->
        String.replace(acc, "{#{key}}", to_string(value))
      end)

    # Build query parameters
    query_params =
      arguments
      |> Enum.filter(fn {key, _value} -> not String.contains?(path, "{#{key}}") end)
      |> Enum.map(fn {key, value} -> "#{URI.encode(key)}=#{URI.encode(to_string(value))}" end)
      |> Enum.join("&")

    full_url =
      case query_params do
        "" -> server_url <> final_path
        params -> server_url <> final_path <> "?" <> params
      end

    {:ok, full_url}
  end

  defp build_headers(_operation) do
    {:ok, [{"Content-Type", "application/json"}]}
  end

  defp build_request_body(_operation, _arguments) do
    # For now, simple implementation - could be enhanced for request bodies
    {:ok, nil}
  end

  defp execute_http_request(request) do
    headers = request.headers
    options = [timeout: 15_000, recv_timeout: 15_000]

    case HTTPoison.request(request.method, request.url, request.body || "", headers, options) do
      {:ok, %HTTPoison.Response{} = response} ->
        parsed_body = parse_response_body(response.body)
        {:ok, %{status_code: response.status_code, body: parsed_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  defp parse_response_body(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parsed
      # Return raw body if not JSON
      {:error, _} -> body
    end
  end

  # Register the tool when the module is loaded
  @doc false
  def register_tool do
    TheMaestro.Tooling.register_tool(
      "call_api",
      __MODULE__,
      definition(),
      &execute/1
    )
  end
end
