#!/usr/bin/env elixir

# Epic 3 Story 3.4 Demo: OpenAPI Specification Tool
# This script demonstrates the OpenAPI tool functionality

IO.puts("Epic 3 Story 3.4 Demo: OpenAPI Specification Tool")
IO.puts("=" |> String.duplicate(60))

# Mix.install([
#   {:the_maestro, path: "../.."}
# ])

# Start the application and dependencies
{:ok, _} = Application.ensure_all_started(:the_maestro)

# Import required modules
alias TheMaestro.Tooling.Tools.OpenAPI
alias TheMaestro.Tooling

# Register the OpenAPI tool
OpenAPI.register_tool()

IO.puts("\n1. Testing OpenAPI Spec Parsing")
IO.puts("-" |> String.duplicate(40))

# Create a simple test OpenAPI spec
test_spec = %{
  "openapi" => "3.0.0",
  "info" => %{
    "title" => "HTTPBin API",
    "version" => "1.0.0"
  },
  "servers" => [
    %{"url" => "https://httpbin.org"}
  ],
  "paths" => %{
    "/get" => %{
      "get" => %{
        "operationId" => "testGet",
        "parameters" => [
          %{
            "name" => "param1", 
            "in" => "query", 
            "required" => false,
            "schema" => %{"type" => "string"}
          }
        ],
        "responses" => %{
          "200" => %{"description" => "Success response"}
        }
      }
    },
    "/status/{code}" => %{
      "get" => %{
        "operationId" => "getStatus",
        "parameters" => [
          %{
            "name" => "code",
            "in" => "path",
            "required" => true,
            "schema" => %{"type" => "integer"}
          }
        ],
        "responses" => %{
          "200" => %{"description" => "Returns given HTTP Status code"}
        }
      }
    }
  }
}

# Write spec to temporary file
spec_file = Path.join(System.tmp_dir(), "demo_openapi_spec.json")
File.write!(spec_file, Jason.encode!(test_spec))

IO.puts("✓ Created test OpenAPI spec at: #{spec_file}")

IO.puts("\n2. Testing Tool Registration")
IO.puts("-" |> String.duplicate(40))

tools = Tooling.list_tools()
if Map.has_key?(tools, "call_api") do
  IO.puts("✓ OpenAPI tool 'call_api' is registered")
else
  IO.puts("✗ OpenAPI tool 'call_api' not found")
  System.halt(1)
end

tool_definitions = Tooling.get_tool_definitions()
openapi_def = Enum.find(tool_definitions, &(&1["name"] == "call_api"))

if openapi_def do
  IO.puts("✓ Tool definition found")
  IO.puts("  Name: #{openapi_def["name"]}")
  IO.puts("  Description: #{String.slice(openapi_def["description"], 0, 50)}...")
else
  IO.puts("✗ OpenAPI tool definition not found")
  System.halt(1)
end

IO.puts("\n3. Testing Simple GET Request")
IO.puts("-" |> String.duplicate(40))

args1 = %{
  "spec_url" => spec_file,
  "operation_id" => "testGet",
  "arguments" => %{"param1" => "demo_value"}
}

case Tooling.execute_tool("call_api", args1) do
  {:ok, result} ->
    IO.puts("✓ GET request successful")
    IO.puts("  Status Code: #{result["status_code"]}")
    IO.puts("  URL: #{result["url"]}")
    IO.puts("  Method: #{result["method"]}")
    
    # Try to parse the response and show some details
    case result["response"] do
      %{"args" => args} ->
        IO.puts("  Query Params Received: #{inspect(args)}")
      response when is_binary(response) ->
        IO.puts("  Response (text): #{String.slice(response, 0, 100)}...")
      _ ->
        IO.puts("  Response: #{inspect(result["response"])}")
    end
    
  {:error, reason} ->
    IO.puts("✗ GET request failed: #{reason}")
    System.halt(1)
end

IO.puts("\n4. Testing Path Parameters")
IO.puts("-" |> String.duplicate(40))

args2 = %{
  "spec_url" => spec_file,
  "operation_id" => "getStatus",
  "arguments" => %{"code" => "200"}
}

case Tooling.execute_tool("call_api", args2) do
  {:ok, result} ->
    IO.puts("✓ Path parameter request successful")
    IO.puts("  Status Code: #{result["status_code"]}")
    IO.puts("  URL: #{result["url"]}")
    IO.puts("  Method: #{result["method"]}")
    
  {:error, reason} ->
    IO.puts("✗ Path parameter request failed: #{reason}")
    System.halt(1)
end

IO.puts("\n5. Testing Error Handling")
IO.puts("-" |> String.duplicate(40))

# Test with non-existent operation
args3 = %{
  "spec_url" => spec_file,
  "operation_id" => "nonExistentOp",
  "arguments" => %{}
}

case Tooling.execute_tool("call_api", args3) do
  {:error, reason} ->
    IO.puts("✓ Error handling works: #{reason}")
  {:ok, _} ->
    IO.puts("✗ Expected error but got success")
    System.halt(1)
end

# Test with missing required parameters
args4 = %{
  "spec_url" => spec_file,
  "operation_id" => "getStatus",
  "arguments" => %{}  # Missing required 'code' parameter
}

case Tooling.execute_tool("call_api", args4) do
  {:error, reason} ->
    IO.puts("✓ Missing parameter validation works: #{reason}")
  {:ok, _} ->
    IO.puts("✗ Expected parameter validation error but got success")
    System.halt(1)
end

IO.puts("\n6. Testing Real World API (JSONPlaceholder)")
IO.puts("-" |> String.duplicate(40))

# Try with a real API spec from JSONPlaceholder
jsonplaceholder_spec = %{
  "openapi" => "3.0.0",
  "info" => %{
    "title" => "JSONPlaceholder API",
    "version" => "1.0.0"
  },
  "servers" => [
    %{"url" => "https://jsonplaceholder.typicode.com"}
  ],
  "paths" => %{
    "/posts/{id}" => %{
      "get" => %{
        "operationId" => "getPost",
        "parameters" => [
          %{
            "name" => "id",
            "in" => "path",
            "required" => true,
            "schema" => %{"type" => "integer"}
          }
        ],
        "responses" => %{
          "200" => %{"description" => "Post retrieved successfully"}
        }
      }
    }
  }
}

# Write JSONPlaceholder spec to file
jsonplaceholder_file = Path.join(System.tmp_dir(), "jsonplaceholder_spec.json")
File.write!(jsonplaceholder_file, Jason.encode!(jsonplaceholder_spec))

args5 = %{
  "spec_url" => jsonplaceholder_file,
  "operation_id" => "getPost",
  "arguments" => %{"id" => "1"}
}

case Tooling.execute_tool("call_api", args5) do
  {:ok, result} ->
    IO.puts("✓ Real API request successful")
    IO.puts("  Status Code: #{result["status_code"]}")
    IO.puts("  URL: #{result["url"]}")
    
    # Show post details if available
    case result["response"] do
      %{"title" => title, "body" => body} ->
        IO.puts("  Post Title: #{title}")
        IO.puts("  Post Body: #{String.slice(body, 0, 50)}...")
      _ ->
        IO.puts("  Response: #{inspect(result["response"])}")
    end
    
  {:error, reason} ->
    IO.puts("⚠ Real API request failed (this might be expected): #{reason}")
end

# Cleanup temporary files
File.rm(spec_file)
File.rm(jsonplaceholder_file)

IO.puts("\n" <> "=" |> String.duplicate(60))
IO.puts("Epic 3 Story 3.4 Demo Complete!")
IO.puts("✓ OpenAPI Specification Tool successfully implemented")
IO.puts("✓ Can parse OpenAPI specs from files and URLs")
IO.puts("✓ Can find operations by operationId")
IO.puts("✓ Can handle path and query parameters")
IO.puts("✓ Can make HTTP requests based on spec")
IO.puts("✓ Proper error handling and validation")
IO.puts("=" |> String.duplicate(60))