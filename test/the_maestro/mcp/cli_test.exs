defmodule TheMaestro.MCP.CLITest do
  @moduledoc """
  Tests for MCP CLI Management commands.

  This test suite validates the comprehensive MCP CLI management system
  including server management, tool management, authentication, monitoring,
  and diagnostic commands.
  """

  use ExUnit.Case
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias TheMaestro.MCP.CLI

  alias TheMaestro.MCP.CLI.Commands.{
    List,
    Add,
    Remove,
    Status,
    Tools,
    Auth,
    Trust,
    Config,
    Diagnostics
  }

  alias TheMaestro.MCP.CLI.Formatters.{TableFormatter, JsonFormatter}

  @tmp_dir Path.join([System.tmp_dir!(), "maestro_cli_test"])

  setup do
    File.mkdir_p!(@tmp_dir)

    # Mock configuration for testing
    test_config = %{
      "mcpServers" => %{
        "fileSystem" => %{
          "command" => "python",
          "args" => ["-m", "filesystem_mcp_server"],
          "trust" => false,
          "status" => :connected
        },
        "weatherAPI" => %{
          "url" => "https://weather-mcp.example.com/sse",
          "trust" => true,
          "status" => :disconnected
        }
      },
      "globalSettings" => %{
        "defaultTimeout" => 30_000,
        "confirmationLevel" => "medium"
      }
    }

    on_exit(fn ->
      File.rm_rf(@tmp_dir)
    end)

    {:ok, tmp_dir: @tmp_dir, config: test_config}
  end

  describe "maestro mcp list" do
    test "lists all configured servers", %{config: config} do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "list"])
        end)

      assert output =~ "fileSystem"
      assert output =~ "weatherAPI"
      assert output =~ "python"
    end

    test "lists servers with status information", %{config: config} do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "list", "--status"])
        end)

      assert output =~ "connected"
      assert output =~ "disconnected"
    end

    test "lists servers with available tools", %{config: config} do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "list", "--tools"])
        end)

      assert output =~ "Tools:"
    end

    test "formats output as JSON when requested" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "list", "--format", "json"])
        end)

      {:ok, json} = Jason.decode(output)
      assert Map.has_key?(json, "servers")
    end
  end

  describe "maestro mcp add" do
    test "adds new STDIO server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "add", "newServer", "--command", "python", "-m", "new_server"])
        end)

      assert output =~ "Successfully added server 'newServer'"
    end

    test "adds new SSE server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "add", "sseServer", "--url", "https://example.com/sse"])
        end)

      assert output =~ "Successfully added server 'sseServer'"
    end

    test "adds new HTTP server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "add", "httpServer", "--http-url", "http://localhost:3000/mcp"])
        end)

      assert output =~ "Successfully added server 'httpServer'"
    end

    test "rejects server with invalid configuration" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "add", "invalidServer"])
        end)

      assert output =~ "Error:"
      assert output =~ "must specify either --command, --url, or --http-url"
    end
  end

  describe "maestro mcp update" do
    test "updates server timeout setting" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "update", "fileSystem", "--timeout", "60_000"])
        end)

      assert output =~ "Successfully updated server 'fileSystem'"
    end

    test "updates server trust setting" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "update", "fileSystem", "--trust", "true"])
        end)

      assert output =~ "trust setting updated"
    end

    test "adds tool to include list" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "update", "fileSystem", "--add-tool", "new_tool"])
        end)

      assert output =~ "Added tool 'new_tool'"
    end

    test "removes tool from server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "update", "fileSystem", "--remove-tool", "old_tool"])
        end)

      assert output =~ "Removed tool 'old_tool'"
    end

    test "returns error for non-existent server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "update", "nonexistent", "--trust", "true"])
        end)

      assert output =~ "Error: Server 'nonexistent' not found"
    end
  end

  describe "maestro mcp remove" do
    test "removes existing server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "remove", "weatherAPI"])
        end)

      assert output =~ "Successfully removed server 'weatherAPI'"
    end

    test "force removes connected server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "remove", "fileSystem", "--force"])
        end)

      assert output =~ "Force removed server 'fileSystem'"
    end

    test "returns error for non-existent server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "remove", "nonexistent"])
        end)

      assert output =~ "Error: Server 'nonexistent' not found"
    end
  end

  describe "maestro mcp status" do
    test "shows overall status of all servers" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "status"])
        end)

      assert output =~ "MCP Server Status Summary"
      assert output =~ "Connected: 1"
      assert output =~ "Disconnected: 1"
    end

    test "shows detailed status for specific server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "status", "fileSystem"])
        end)

      assert output =~ "Server: fileSystem"
      assert output =~ "Status: connected"
      assert output =~ "Transport: stdio"
    end
  end

  describe "maestro mcp test" do
    test "tests connection to specific server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "test", "fileSystem"])
        end)

      assert output =~ "Testing connection to 'fileSystem'"
      assert output =~ "Connection test"
    end

    test "tests all server connections" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "test", "--all"])
        end)

      assert output =~ "Testing all servers"
      assert output =~ "fileSystem:"
      assert output =~ "weatherAPI:"
    end
  end

  describe "maestro mcp health" do
    test "shows overall health status" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "health"])
        end)

      assert output =~ "MCP System Health"
      assert output =~ "Overall Status:"
    end

    test "provides continuous health monitoring" do
      # Test would run for short period and then stop
      pid =
        spawn(fn ->
          CLI.main(["mcp", "health", "--watch"])
        end)

      :timer.sleep(100)
      Process.exit(pid, :kill)
    end
  end

  describe "maestro mcp tools" do
    test "lists all available tools" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "tools"])
        end)

      assert output =~ "Available Tools"
    end

    test "lists tools from specific server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "tools", "--server", "fileSystem"])
        end)

      assert output =~ "Tools from server 'fileSystem'"
    end

    test "shows only available tools" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "tools", "--available"])
        end)

      assert output =~ "Available Tools"
    end

    test "describes specific tool" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "tools", "--describe", "read_file"])
        end)

      assert output =~ "Tool: read_file"
      assert output =~ "Description:"
    end
  end

  describe "maestro mcp run" do
    test "executes tool with parameters" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "run", "read_file", "--path", "/tmp/test.txt"])
        end)

      assert output =~ "Executing tool 'read_file'"
    end

    test "executes tool from specific server" do
      output =
        capture_io(fn ->
          CLI.main([
            "mcp",
            "run",
            "--server",
            "fileSystem",
            "read_file",
            "--path",
            "/tmp/test.txt"
          ])
        end)

      assert output =~ "Executing tool 'read_file' on server 'fileSystem'"
    end
  end

  describe "maestro mcp debug" do
    test "runs tool in debug mode" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "debug", "read_file", "--path", "/tmp/test.txt"])
        end)

      assert output =~ "DEBUG MODE:"
      assert output =~ "Tool parameters:"
    end
  end

  describe "maestro mcp trace" do
    test "runs tool with full execution trace" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "trace", "read_file", "--path", "/tmp/test.txt"])
        end)

      assert output =~ "EXECUTION TRACE:"
      assert output =~ "Step 1:"
    end
  end

  describe "maestro mcp auth" do
    test "lists authentication status for all servers" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "auth", "list"])
        end)

      assert output =~ "Authentication Status"
    end

    test "authenticates with specific server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "auth", "weatherAPI"])
        end)

      assert output =~ "Authenticating with server 'weatherAPI'"
    end

    test "resets authentication for server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "auth", "weatherAPI", "--reset"])
        end)

      assert output =~ "Reset authentication for server 'weatherAPI'"
    end
  end

  describe "maestro mcp apikey" do
    test "sets API key for server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "apikey", "set", "weatherAPI", "test-key-123"])
        end)

      assert output =~ "API key set for server 'weatherAPI'"
    end

    test "tests API key for server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "apikey", "test", "weatherAPI"])
        end)

      assert output =~ "Testing API key for server 'weatherAPI'"
    end

    test "removes API key from server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "apikey", "remove", "weatherAPI"])
        end)

      assert output =~ "API key removed for server 'weatherAPI'"
    end
  end

  describe "maestro mcp trust" do
    test "lists trust settings for all servers" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "trust", "list"])
        end)

      assert output =~ "Trust Settings"
    end

    test "sets server trust level" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "trust", "server", "fileSystem", "--level", "trusted"])
        end)

      assert output =~ "Set trust level for server 'fileSystem' to 'trusted'"
    end

    test "allows specific tool" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "trust", "tool", "fileSystem.read_file", "--allow"])
        end)

      assert output =~ "Allowed tool 'fileSystem.read_file'"
    end

    test "blocks specific tool" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "trust", "tool", "fileSystem.write_file", "--block"])
        end)

      assert output =~ "Blocked tool 'fileSystem.write_file'"
    end

    test "resets trust settings for server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "trust", "reset", "fileSystem"])
        end)

      assert output =~ "Reset trust settings for server 'fileSystem'"
    end
  end

  describe "maestro mcp metrics" do
    test "shows overall performance metrics" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "metrics"])
        end)

      assert output =~ "MCP Performance Metrics"
      assert output =~ "Total Requests:"
    end

    test "shows server-specific metrics" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "metrics", "fileSystem"])
        end)

      assert output =~ "Metrics for server 'fileSystem'"
    end

    test "exports metrics as JSON" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "metrics", "--export", "json"])
        end)

      {:ok, json} = Jason.decode(output)
      assert Map.has_key?(json, "metrics")
    end
  end

  describe "maestro mcp analyze" do
    test "performs general performance analysis" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "analyze"])
        end)

      assert output =~ "Performance Analysis"
    end

    test "identifies slow tools" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "analyze", "--slow-tools"])
        end)

      assert output =~ "Slow Tools Analysis"
    end

    test "analyzes error rates" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "analyze", "--error-rates"])
        end)

      assert output =~ "Error Rate Analysis"
    end
  end

  describe "maestro mcp diagnose" do
    test "performs full system diagnosis" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "diagnose"])
        end)

      assert output =~ "MCP System Diagnosis"
    end

    test "diagnoses specific server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "diagnose", "fileSystem"])
        end)

      assert output =~ "Diagnosis for server 'fileSystem'"
    end
  end

  describe "maestro mcp logs" do
    test "shows logs for specific server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "logs", "fileSystem"])
        end)

      assert output =~ "Logs for server 'fileSystem'"
    end

    test "follows logs in real-time" do
      pid =
        spawn(fn ->
          CLI.main(["mcp", "logs", "--follow"])
        end)

      :timer.sleep(100)
      Process.exit(pid, :kill)
    end
  end

  describe "maestro mcp discover" do
    test "auto-discovers servers in directory" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "discover", "--path", "./mcp-servers"])
        end)

      assert output =~ "Discovering MCP servers"
    end

    test "discovers network services" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "discover", "--network"])
        end)

      assert output =~ "Network discovery"
    end
  end

  describe "maestro mcp template" do
    test "lists available templates" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "template", "list"])
        end)

      assert output =~ "Available Templates"
    end

    test "applies template to create server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "template", "apply", "python-stdio", "myServer"])
        end)

      assert output =~ "Applied template 'python-stdio' to create server 'myServer'"
    end

    test "creates template from existing server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "template", "create", "myTemplate", "--from", "fileSystem"])
        end)

      assert output =~ "Created template 'myTemplate' from server 'fileSystem'"
    end
  end

  describe "maestro mcp export" do
    test "exports all configurations", %{tmp_dir: tmp_dir} do
      output_file = Path.join(tmp_dir, "export.json")

      output =
        capture_io(fn ->
          CLI.main(["mcp", "export", "--output", output_file])
        end)

      assert output =~ "Exported configuration"
      assert File.exists?(output_file)
    end

    test "exports specific server configuration" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "export", "fileSystem", "--format", "yaml"])
        end)

      assert output =~ "command: python"
    end
  end

  describe "maestro mcp import" do
    test "imports configuration from file", %{tmp_dir: tmp_dir} do
      config_file = Path.join(tmp_dir, "import.json")

      config_content = %{
        "mcpServers" => %{
          "imported" => %{
            "command" => "imported-server"
          }
        }
      }

      File.write!(config_file, Jason.encode!(config_content))

      output =
        capture_io(fn ->
          CLI.main(["mcp", "import", config_file])
        end)

      assert output =~ "Imported configuration from"
    end

    test "merges imported configuration with existing" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "import", "--merge", "/path/to/config.json"])
        end)

      assert output =~ "Merged configuration"
    end

    test "validates configuration without importing" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "import", "--validate-only", "/path/to/config.json"])
        end)

      assert output =~ "Configuration validation:"
    end
  end

  describe "interactive setup" do
    test "runs interactive setup wizard" do
      # This would be a more complex test involving input simulation
      # For now, just test that the command is recognized
      output =
        capture_io(fn ->
          # Simulate user input
          send(self(), {:input, "y\n"})
          CLI.main(["mcp", "setup"])
        end)

      assert output =~ "MCP Setup Wizard"
    end

    test "runs interactive server configuration" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "configure", "fileSystem"])
        end)

      assert output =~ "Configuring server 'fileSystem'"
    end
  end

  describe "help system" do
    test "shows general help" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "--help"])
        end)

      assert output =~ "MCP Management Commands"
      assert output =~ "list"
      assert output =~ "add"
      assert output =~ "remove"
    end

    test "shows command-specific help" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "add", "--help"])
        end)

      assert output =~ "Add a new MCP server"
      assert output =~ "--command"
      assert output =~ "--url"
    end
  end

  describe "output formatters" do
    test "TableFormatter formats data as table" do
      data = [
        %{"name" => "server1", "status" => "connected"},
        %{"name" => "server2", "status" => "disconnected"}
      ]

      output = TableFormatter.format(data, ["name", "status"])

      assert output =~ "server1"
      assert output =~ "connected"
      assert output =~ "server2"
    end

    test "JsonFormatter formats data as JSON" do
      data = %{"servers" => [%{"name" => "server1"}]}

      output = JsonFormatter.format(data)
      {:ok, parsed} = Jason.decode(output)

      assert parsed["servers"] |> hd() |> Map.get("name") == "server1"
    end
  end
end
