defmodule TheMaestro.MCP.DiscoveryTest do
  use ExUnit.Case, async: false

  alias TheMaestro.MCP.Discovery

  describe "discover_servers/1" do
    test "loads servers from valid mcp_settings.json configuration" do
      config_path = create_test_config(%{
        "mcpServers" => %{
          "fileSystem" => %{
            "command" => "python",
            "args" => ["-m", "filesystem_mcp"],
            "env" => %{"ALLOWED_DIRS" => "/tmp,/workspace"},
            "trust" => false
          },
          "weatherAPI" => %{
            "url" => "https://weather.example.com/sse",
            "headers" => %{"Authorization" => "Bearer token"},
            "trust" => true
          }
        }
      })

      assert {:ok, servers} = Discovery.discover_servers(config_path)
      assert length(servers) == 2
      assert Enum.any?(servers, fn server -> server.id == "fileSystem" end)
      assert Enum.any?(servers, fn server -> server.id == "weatherAPI" end)
    end

    test "returns error for non-existent config file" do
      assert {:error, :file_not_found} = Discovery.discover_servers("/non/existent/path.json")
    end

    test "returns error for invalid JSON format" do
      config_path = create_invalid_json_file()
      assert {:error, {:invalid_json, _}} = Discovery.discover_servers(config_path)
    end

    test "returns empty list for empty mcpServers configuration" do
      config_path = create_test_config(%{"mcpServers" => %{}})
      assert {:ok, []} = Discovery.discover_servers(config_path)
    end
  end

  describe "validate_server_config/1" do
    test "validates stdio server configuration" do
      config = %{
        "id" => "testServer",
        "command" => "python",
        "args" => ["-m", "test_server"],
        "env" => %{"TEST" => "value"},
        "trust" => false
      }

      assert {:ok, validated} = Discovery.validate_server_config(config)
      assert validated.transport == :stdio
      assert validated.id == "testServer"
      assert validated.command == "python"
      assert validated.args == ["-m", "test_server"]
      assert validated.env == %{"TEST" => "value"}
      assert validated.trust == false
    end

    test "validates SSE server configuration" do
      config = %{
        "id" => "sseServer",
        "url" => "https://example.com/sse",
        "headers" => %{"Authorization" => "Bearer token"},
        "trust" => true
      }

      assert {:ok, validated} = Discovery.validate_server_config(config)
      assert validated.transport == :sse
      assert validated.id == "sseServer"
      assert validated.url == "https://example.com/sse"
      assert validated.headers == %{"Authorization" => "Bearer token"}
      assert validated.trust == true
    end

    test "validates HTTP server configuration" do
      config = %{
        "id" => "httpServer",
        "url" => "https://example.com/mcp",
        "method" => "POST",
        "headers" => %{"Content-Type" => "application/json"},
        "trust" => false
      }

      assert {:ok, validated} = Discovery.validate_server_config(config)
      assert validated.transport == :http
      assert validated.id == "httpServer"
      assert validated.url == "https://example.com/mcp"
      assert validated.method == "POST"
    end

    test "returns error for missing required fields" do
      config = %{"command" => "python"}
      assert {:error, validation_errors} = Discovery.validate_server_config(config)
      assert :missing_id in validation_errors
    end

    test "returns error for invalid transport type" do
      config = %{
        "id" => "invalid",
        "invalidField" => "value"
      }
      assert {:error, validation_errors} = Discovery.validate_server_config(config)
      assert :unknown_transport in validation_errors
    end

    test "supports environment variable interpolation" do
      # Set test environment variables FIRST
      System.put_env("TEST_API_KEY", "secret123")
      System.put_env("TEST_DB_URL", "postgres://localhost/test")

      # Verify they're set
      assert System.get_env("TEST_API_KEY") == "secret123"
      assert System.get_env("TEST_DB_URL") == "postgres://localhost/test"

      config = %{
        "id" => "envServer",
        "command" => "python",
        "args" => ["-m", "test"],
        "env" => %{
          "API_KEY" => "$TEST_API_KEY",
          "DATABASE_URL" => "${TEST_DB_URL}"
        }
      }

      assert {:ok, validated} = Discovery.validate_server_config(config)
      assert validated.env["API_KEY"] == "secret123"
      assert validated.env["DATABASE_URL"] == "postgres://localhost/test"

      # Clean up
      System.delete_env("TEST_API_KEY")
      System.delete_env("TEST_DB_URL")
    end
  end

  describe "start_server_connection/1" do
    test "starts connection for valid stdio server" do
      server_config = %{
        id: "testServer",
        transport: :stdio,
        command: "echo",
        args: ["test"],
        env: %{},
        trust: false
      }

      assert {:ok, connection_pid} = Discovery.start_server_connection(server_config)
      assert is_pid(connection_pid)
      assert Process.alive?(connection_pid)
    end

    test "returns error for invalid server configuration" do
      invalid_config = %{
        id: "invalid",
        transport: :stdio,
        command: "/non/existent/command"
      }

      assert {:error, _reason} = Discovery.start_server_connection(invalid_config)
    end
  end

  # Helper functions for test setup
  defp create_test_config(config) do
    file_path = "/tmp/test_mcp_config_#{:rand.uniform(10000)}.json"
    File.write!(file_path, Jason.encode!(config))
    
    # Register cleanup
    on_exit(fn ->
      if File.exists?(file_path), do: File.rm!(file_path)
    end)
    
    file_path
  end

  defp create_invalid_json_file do
    file_path = "/tmp/invalid_json_#{:rand.uniform(10000)}.json"
    File.write!(file_path, "{invalid json content")
    
    # Register cleanup
    on_exit(fn ->
      if File.exists?(file_path), do: File.rm!(file_path)
    end)
    
    file_path
  end
end