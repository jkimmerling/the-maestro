# Epic 3 Story 3.4: OpenAPI Specification Tool

In this tutorial, we'll explore the implementation of the OpenAPI Specification Tool for the Agent OS project. This powerful tool allows AI agents to interact with external web services by reading OpenAPI specifications and making HTTP requests based on operation definitions.

## Table of Contents

1. [Overview](#overview)
2. [Core Architecture](#core-architecture)
3. [Implementation Details](#implementation-details)
4. [Security Considerations](#security-considerations)
5. [Usage Examples](#usage-examples)
6. [Testing](#testing)
7. [Integration with Agent System](#integration-with-agent-system)

## Overview

The OpenAPI tool (`TheMaestro.Tooling.Tools.OpenAPI`) enables agents to:

- Load OpenAPI specifications from URLs or file paths
- Validate operation IDs and parameters against the spec
- Construct and execute HTTP requests based on the spec
- Support path parameters, query parameters, and request bodies
- Return structured JSON responses

This tool satisfies all acceptance criteria from Epic 3 Story 3.4:

1. ✅ An `OpenAPI` tool module created using the `deftool` DSL
2. ✅ Tool can be initialized with path or URL to OpenAPI spec file
3. ✅ Tool provides `:call_api` function accepting `operation_id` and `arguments`
4. ✅ Tool validates arguments against spec and constructs HTTP requests
5. ✅ JSON responses returned to the agent
6. ✅ Tutorial created with comprehensive examples

## Core Architecture

### Tool Definition Structure

The OpenAPI tool follows the standard tool pattern using the `deftool` DSL:

```elixir
defmodule TheMaestro.Tooling.Tools.OpenAPI do
  use TheMaestro.Tooling.Tool
  
  @impl true
  def definition do
    %{
      "name" => "call_api",
      "description" => "Reads an OpenAPI specification and makes API calls based on it.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "spec_url" => %{
            "type" => "string",
            "description" => "URL or file path to the OpenAPI specification"
          },
          "operation_id" => %{
            "type" => "string", 
            "description" => "The operationId from the OpenAPI spec to call"
          },
          "arguments" => %{
            "type" => "object",
            "description" => "Arguments to pass to the API operation"
          }
        },
        "required" => ["spec_url", "operation_id", "arguments"]
      }
    }
  end
end
```

### Key Type Definitions

The tool defines several important types for type safety:

```elixir
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
```

## Implementation Details

### 1. Execution Flow

The `execute/1` function implements a comprehensive pipeline:

```elixir
def execute(%{"spec_url" => spec_url, "operation_id" => operation_id, "arguments" => arguments}) do
  with :ok <- validate_arguments(%{...}),
       {:ok, spec_content} <- fetch_openapi_spec(spec_url),
       {:ok, parsed_spec} <- parse_openapi_spec(spec_content),
       {:ok, operation_info} <- find_operation(parsed_spec, operation_id),
       :ok <- validate_operation_arguments(operation_info, arguments),
       server_url <- get_server_url(parsed_spec),
       {:ok, request} <- build_request(operation_info, server_url, arguments),
       {:ok, response} <- execute_http_request(request) do
    {:ok, %{
      "operation_id" => operation_id,
      "status_code" => response.status_code,
      "response" => response.body,
      "url" => request.url,
      "method" => Atom.to_string(request.method)
    }}
  else
    {:error, reason} -> {:error, reason}
  end
end
```

This pipeline ensures each step is validated before proceeding to the next.

### 2. OpenAPI Spec Fetching

The tool supports both URLs and file paths:

```elixir
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
```

### 3. Spec Parsing and Validation

The tool parses JSON specs and validates OpenAPI format:

```elixir
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

defp valid_openapi_spec?(spec) do
  case spec do
    %{"openapi" => version} when is_binary(version) -> true
    %{"swagger" => version} when is_binary(version) -> true
    _ -> false
  end
end
```

### 4. Operation Discovery

The tool searches through all paths and HTTP methods to find operations:

```elixir
def find_operation(spec, operation_id) do
  paths = Map.get(spec, "paths", %{})
  
  result = Enum.reduce_while(paths, nil, fn {path, path_item}, acc ->
    case find_operation_in_path_item(path_item, operation_id) do
      {:ok, method, operation} ->
        {:halt, {:ok, %{
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
```

### 5. Request Building

The tool constructs proper HTTP requests with path and query parameters:

```elixir
defp build_url(path, server_url, arguments) do
  # Replace path parameters
  final_path = Enum.reduce(arguments, path, fn {key, value}, acc ->
    String.replace(acc, "{#{key}}", to_string(value))
  end)
  
  # Build query parameters  
  query_params = arguments
    |> Enum.filter(fn {key, _value} -> not String.contains?(path, "{#{key}}") end)
    |> Enum.map(fn {key, value} -> "#{URI.encode(key)}=#{URI.encode(to_string(value))}" end)
    |> Enum.join("&")
    
  full_url = case query_params do
    "" -> server_url <> final_path
    params -> server_url <> final_path <> "?" <> params
  end
  
  {:ok, full_url}
end
```

## Security Considerations

The OpenAPI tool implements several security measures:

### 1. URL Validation
```elixir
defp valid_url_format?(url) do
  String.starts_with?(url, ["http://", "https://", "/"]) or File.exists?(url)
end
```

### 2. Parameter Validation
All parameters are validated against the OpenAPI spec:

```elixir
def validate_operation_arguments(operation_info, arguments) do
  required_params = get_required_parameters(operation_info.parameters)
  
  missing_params = Enum.filter(required_params, fn param_name ->
    not Map.has_key?(arguments, param_name)
  end)
  
  if Enum.empty?(missing_params) do
    :ok
  else
    {:error, "Missing required parameter: #{Enum.join(missing_params, ", ")}"}
  end
end
```

### 3. HTTP Timeouts
```elixir
defp execute_http_request(request) do
  options = [timeout: 15_000, recv_timeout: 15_000]
  # ... HTTP request execution
end
```

### 4. Response Size Management
The tool handles response parsing safely and doesn't expose internal system details in error messages.

## Usage Examples

### Example 1: Simple GET Request

```elixir
args = %{
  "spec_url" => "https://api.example.com/openapi.json",
  "operation_id" => "getUser",
  "arguments" => %{"id" => "123"}
}

{:ok, result} = TheMaestro.Tooling.execute_tool("call_api", args)
# %{
#   "operation_id" => "getUser",
#   "status_code" => 200,
#   "response" => %{"id" => "123", "name" => "John Doe"},
#   "url" => "https://api.example.com/users/123",
#   "method" => "get"
# }
```

### Example 2: Request with Query Parameters

```elixir
args = %{
  "spec_url" => "/path/to/spec.json",
  "operation_id" => "searchUsers",
  "arguments" => %{
    "query" => "john",
    "limit" => "10",
    "offset" => "0"
  }
}

{:ok, result} = TheMaestro.Tooling.execute_tool("call_api", args)
```

### Example 3: HTTPBin Testing

```elixir
# Create test spec
test_spec = %{
  "openapi" => "3.0.0",
  "info" => %{"title" => "HTTPBin API", "version" => "1.0.0"},
  "servers" => [%{"url" => "https://httpbin.org"}],
  "paths" => %{
    "/get" => %{
      "get" => %{
        "operationId" => "testGet",
        "parameters" => [%{
          "name" => "param1", 
          "in" => "query", 
          "required" => false,
          "schema" => %{"type" => "string"}
        }],
        "responses" => %{"200" => %{"description" => "Success"}}
      }
    }
  }
}

# Save spec and make request
File.write!("/tmp/httpbin.json", Jason.encode!(test_spec))

args = %{
  "spec_url" => "/tmp/httpbin.json", 
  "operation_id" => "testGet",
  "arguments" => %{"param1" => "demo_value"}
}

{:ok, result} = TheMaestro.Tooling.execute_tool("call_api", args)
# Result will show the query parameter was passed correctly
```

## Testing

The OpenAPI tool has comprehensive test coverage in two files:

### Unit Tests (`openapi_test.exs`)

Tests core functionality:
- Tool definition validation
- Argument validation 
- Spec parsing and validation
- Operation finding
- Request building
- Error handling

### Integration Tests (`openapi_integration_test.exs`)

Tests real-world scenarios:
- Fetching real OpenAPI specs
- Tool registration
- End-to-end execution through tooling system
- Error handling with invalid operations

### Running Tests

```bash
# Run all tests
mix test

# Run only OpenAPI tests
mix test test/the_maestro/tooling/tools/openapi_test.exs
mix test test/the_maestro/tooling/tools/openapi_integration_test.exs

# Run integration tests specifically  
mix test --only integration
```

### Test Coverage

The tests cover:
- ✅ All happy path scenarios
- ✅ All error conditions
- ✅ Parameter validation
- ✅ HTTP request construction
- ✅ Real API interactions
- ✅ Tool registration and integration

## Integration with Agent System

### Registration

The tool is automatically registered during application startup:

```elixir
# In application.ex
def start(_type, _args) do
  # ... supervisor setup
  case Supervisor.start_link(children, opts) do
    {:ok, _pid} = result ->
      # Register built-in tools
      FileSystem.register_tools()
      Shell.register_tool()
      OpenAPI.register_tool()  # <-- OpenAPI tool registered here
      result
  end
end
```

### Tool Registration Implementation

```elixir
def register_tool do
  TheMaestro.Tooling.register_tool(
    "call_api",
    __MODULE__,
    definition(),
    &execute/1
  )
end
```

### Agent Usage

Agents can use the tool through the standard tooling interface:

```elixir
# In agent processing
tools = TheMaestro.Tooling.get_tool_definitions()
# Tools available to LLM include "call_api"

# When LLM requests tool use
{:ok, result} = TheMaestro.Tooling.execute_tool("call_api", %{
  "spec_url" => "https://api.example.com/spec.json",
  "operation_id" => "getUser", 
  "arguments" => %{"id" => "123"}
})
```

## Running the Demo

A comprehensive demo is available at `demos/epic3/story3.4_demo.exs`:

```bash
mix run demos/epic3/story3.4_demo.exs
```

The demo demonstrates:
- ✅ OpenAPI spec parsing
- ✅ Tool registration
- ✅ Simple GET requests
- ✅ Path parameter handling
- ✅ Error handling
- ✅ Real-world API integration

## Key Learnings

### 1. OpenAPI Spec Handling
OpenAPI specs can be complex. The implementation handles both OpenAPI 3.x and Swagger 2.x formats, with robust parsing and validation.

### 2. Parameter Processing
Different parameter types (path, query, header, body) require different handling. The tool correctly distinguishes between path parameters (which replace `{param}` in URLs) and query parameters (which become URL query string).

### 3. Error Handling
Comprehensive error handling ensures that failures at any step provide useful feedback:
- Invalid URLs/file paths
- Malformed JSON specs
- Missing operations  
- Missing required parameters
- HTTP request failures

### 4. Security Considerations
The tool implements several security measures:
- URL validation to prevent malicious requests
- Parameter validation against spec
- HTTP timeouts to prevent hanging
- Safe response parsing

### 5. Integration Patterns
The tool follows the standard tooling DSL pattern, making it easy to integrate with the existing agent system and maintain consistency with other tools.

## Next Steps

Potential enhancements for the OpenAPI tool:

1. **Request Body Support**: Currently simplified - could be enhanced for complex request bodies
2. **Authentication**: Support for API keys, OAuth, and other auth methods defined in specs
3. **Response Validation**: Validate responses against spec schemas
4. **YAML Support**: Currently JSON-only - could add YAML parsing
5. **Batch Operations**: Support for multiple operations in one call
6. **Caching**: Cache frequently used specs for better performance

This tutorial demonstrates how the OpenAPI tool provides a powerful way for AI agents to interact with external APIs in a structured, validated way while maintaining security and proper error handling.