defmodule TheMaestro.Tooling.Tools.OpenAPITest do
  use ExUnit.Case, async: true
  alias TheMaestro.Tooling.Tools.OpenAPI

  describe "definition/0" do
    test "returns the correct tool definition" do
      definition = OpenAPI.definition()

      assert definition["name"] == "call_api"
      assert definition["description"] =~ "OpenAPI specification"
      assert definition["parameters"]["type"] == "object"
      assert definition["parameters"]["required"] == ["spec_url", "operation_id", "arguments"]
    end
  end

  describe "validate_arguments/1" do
    test "validates valid arguments" do
      args = %{
        "spec_url" => "https://api.example.com/openapi.json",
        "operation_id" => "getUser",
        "arguments" => %{"id" => "123"}
      }

      assert :ok == OpenAPI.validate_arguments(args)
    end

    test "rejects missing required parameters" do
      args = %{"spec_url" => "https://api.example.com/openapi.json"}

      assert {:error, _reason} = OpenAPI.validate_arguments(args)
    end

    test "rejects empty spec_url" do
      args = %{
        "spec_url" => "",
        "operation_id" => "getUser",
        "arguments" => %{}
      }

      assert {:error, reason} = OpenAPI.validate_arguments(args)
      assert reason =~ "spec_url cannot be empty"
    end

    test "rejects empty operation_id" do
      args = %{
        "spec_url" => "https://api.example.com/openapi.json",
        "operation_id" => "",
        "arguments" => %{}
      }

      assert {:error, reason} = OpenAPI.validate_arguments(args)
      assert reason =~ "operation_id cannot be empty"
    end
  end

  describe "execute/1" do
    test "returns error for invalid URL" do
      args = %{
        "spec_url" => "not-a-url",
        "operation_id" => "getUser",
        "arguments" => %{}
      }

      assert {:error, reason} = OpenAPI.execute(args)
      assert reason =~ "Invalid spec_url format"
    end

    test "returns error for non-existent spec URL" do
      args = %{
        "spec_url" => "https://non-existent-api.example.com/openapi.json",
        "operation_id" => "getUser",
        "arguments" => %{}
      }

      assert {:error, reason} = OpenAPI.execute(args)
      assert reason =~ "Failed to fetch OpenAPI spec"
    end
  end

  # Mock OpenAPI spec for integration tests
  @mock_openapi_spec %{
    "openapi" => "3.0.0",
    "info" => %{
      "title" => "Test API",
      "version" => "1.0.0"
    },
    "servers" => [
      %{"url" => "https://api.example.com"}
    ],
    "paths" => %{
      "/users/{id}" => %{
        "get" => %{
          "operationId" => "getUser",
          "parameters" => [
            %{
              "name" => "id",
              "in" => "path",
              "required" => true,
              "schema" => %{"type" => "string"}
            }
          ],
          "responses" => %{
            "200" => %{
              "description" => "User found",
              "content" => %{
                "application/json" => %{
                  "schema" => %{
                    "type" => "object",
                    "properties" => %{
                      "id" => %{"type" => "string"},
                      "name" => %{"type" => "string"}
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  describe "parse_openapi_spec/1" do
    test "parses valid OpenAPI spec" do
      json_spec = Jason.encode!(@mock_openapi_spec)

      assert {:ok, parsed} = OpenAPI.parse_openapi_spec(json_spec)
      assert parsed["openapi"] == "3.0.0"
      assert parsed["info"]["title"] == "Test API"
    end

    test "returns error for invalid JSON" do
      assert {:error, reason} = OpenAPI.parse_openapi_spec("invalid json")
      assert reason =~ "Invalid JSON"
    end

    test "returns error for missing OpenAPI version" do
      invalid_spec = %{"info" => %{"title" => "Test"}}
      json_spec = Jason.encode!(invalid_spec)

      assert {:error, reason} = OpenAPI.parse_openapi_spec(json_spec)
      assert reason =~ "Invalid OpenAPI spec"
    end
  end

  describe "find_operation/2" do
    test "finds operation by operationId" do
      assert {:ok, operation_info} = OpenAPI.find_operation(@mock_openapi_spec, "getUser")
      assert operation_info.method == :get
      assert operation_info.path == "/users/{id}"
      assert operation_info.operation["operationId"] == "getUser"
    end

    test "returns error for non-existent operation" do
      assert {:error, reason} = OpenAPI.find_operation(@mock_openapi_spec, "nonExistentOp")
      assert reason =~ "Operation 'nonExistentOp' not found"
    end
  end

  describe "validate_operation_arguments/2" do
    setup do
      {:ok, operation_info} = OpenAPI.find_operation(@mock_openapi_spec, "getUser")
      {:ok, operation_info: operation_info}
    end

    test "validates required path parameters", %{operation_info: operation_info} do
      args = %{"id" => "123"}
      assert :ok == OpenAPI.validate_operation_arguments(operation_info, args)
    end

    test "returns error for missing required parameters", %{operation_info: operation_info} do
      args = %{}
      assert {:error, reason} = OpenAPI.validate_operation_arguments(operation_info, args)
      assert reason =~ "Missing required parameter: id"
    end
  end

  describe "build_request/3" do
    setup do
      {:ok, operation_info} = OpenAPI.find_operation(@mock_openapi_spec, "getUser")
      server_url = "https://api.example.com"
      args = %{"id" => "123"}
      {:ok, operation_info: operation_info, server_url: server_url, args: args}
    end

    test "builds correct HTTP request", %{
      operation_info: operation_info,
      server_url: server_url,
      args: args
    } do
      assert {:ok, request} = OpenAPI.build_request(operation_info, server_url, args)
      assert request.method == :get
      assert request.url == "https://api.example.com/users/123"
      assert request.headers == [{"Content-Type", "application/json"}]
    end
  end
end
