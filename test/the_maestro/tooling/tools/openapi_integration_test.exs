defmodule TheMaestro.Tooling.Tools.OpenAPIIntegrationTest do
  use ExUnit.Case, async: false
  alias TheMaestro.Tooling
  alias TheMaestro.Tooling.Tools.OpenAPI

  @moduletag :integration

  @test_spec_url "https://petstore3.swagger.io/api/v3/openapi.json"

  setup do
    # Ensure the tooling registry is started and tools are registered
    Tooling.start_link()
    OpenAPI.register_tool()
    :ok
  end

  describe "OpenAPI tool integration" do
    test "can fetch and parse real OpenAPI spec" do
      # Test fetching a real OpenAPI spec
      assert {:ok, content} = OpenAPI.fetch_openapi_spec(@test_spec_url)
      assert is_binary(content)
      assert String.contains?(content, "openapi")

      # Test parsing the spec
      assert {:ok, parsed_spec} = OpenAPI.parse_openapi_spec(content)
      assert is_map(parsed_spec)
      assert Map.has_key?(parsed_spec, "openapi")
      assert Map.has_key?(parsed_spec, "paths")
    end

    test "can find operations in real spec" do
      # Use a simple test spec that we control
      test_spec = %{
        "openapi" => "3.0.0",
        "info" => %{"title" => "Test API", "version" => "1.0.0"},
        "servers" => [%{"url" => "https://api.example.com"}],
        "paths" => %{
          "/pets" => %{
            "get" => %{
              "operationId" => "listPets",
              "responses" => %{"200" => %{"description" => "Success"}}
            }
          }
        }
      }

      assert {:ok, operation_info} = OpenAPI.find_operation(test_spec, "listPets")
      assert operation_info.method == :get
      assert operation_info.path == "/pets"
    end

    test "tool registration works correctly" do
      tools = Tooling.list_tools()
      assert Map.has_key?(tools, "call_api")
      assert tools["call_api"] == TheMaestro.Tooling.Tools.OpenAPI
    end

    test "execute through tooling system with mock spec" do
      # Create a test spec file temporarily
      spec_content =
        Jason.encode!(%{
          "openapi" => "3.0.0",
          "info" => %{"title" => "Test API", "version" => "1.0.0"},
          "servers" => [%{"url" => "https://httpbin.org"}],
          "paths" => %{
            "/get" => %{
              "get" => %{
                "operationId" => "httpbinGet",
                "responses" => %{"200" => %{"description" => "Success"}}
              }
            }
          }
        })

      temp_file = Path.join(System.tmp_dir(), "test_openapi_spec.json")
      File.write!(temp_file, spec_content)

      try do
        args = %{
          "spec_url" => temp_file,
          "operation_id" => "httpbinGet",
          "arguments" => %{}
        }

        # Execute through the tooling system
        assert {:ok, result} = Tooling.execute_tool("call_api", args)
        assert is_map(result)
        assert Map.has_key?(result, "status_code")
        assert Map.has_key?(result, "response")
        assert Map.has_key?(result, "operation_id")
        assert result["operation_id"] == "httpbinGet"
      after
        File.rm(temp_file)
      end
    end

    test "handles invalid operation gracefully" do
      spec_content =
        Jason.encode!(%{
          "openapi" => "3.0.0",
          "info" => %{"title" => "Test API", "version" => "1.0.0"},
          "servers" => [%{"url" => "https://api.example.com"}],
          "paths" => %{
            "/test" => %{
              "get" => %{
                "operationId" => "testOp",
                "responses" => %{"200" => %{"description" => "Success"}}
              }
            }
          }
        })

      temp_file = Path.join(System.tmp_dir(), "test_openapi_spec2.json")
      File.write!(temp_file, spec_content)

      try do
        args = %{
          "spec_url" => temp_file,
          "operation_id" => "nonExistentOp",
          "arguments" => %{}
        }

        assert {:error, reason} = Tooling.execute_tool("call_api", args)
        assert reason =~ "Operation 'nonExistentOp' not found"
      after
        File.rm(temp_file)
      end
    end
  end
end
