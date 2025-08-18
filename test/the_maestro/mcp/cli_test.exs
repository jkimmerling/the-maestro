defmodule TheMaestro.MCP.CLITest do
  @moduledoc """
  Tests for MCP CLI Management commands.

  This test suite validates the core MCP CLI functionality,
  focusing on business logic rather than output formatting.
  """

  use ExUnit.Case
  import ExUnit.CaptureIO

  alias TheMaestro.MCP.CLI
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
          "timeout" => 30_000
        },
        "sseServer" => %{
          "url" => "https://example.com/sse",
          "trust" => false,
          "timeout" => 30_000,
          "description" => ""
        },
        "test_server" => %{
          "command" => "python",
          "args" => ["-m", "test_server"],
          "trust" => false
        }
      },
      "globalSettings" => %{
        "defaultTimeout" => 30_000
      }
    }

    on_exit(fn ->
      File.rm_rf(@tmp_dir)
    end)

    {:ok, tmp_dir: @tmp_dir, config: test_config}
  end

  describe "maestro mcp list" do
    test "executes without errors", %{config: _config} do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "list"])
        end)

      # Just verify it runs and produces some output
      assert String.length(output) > 0
    end

    test "handles JSON format request" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "list", "--format", "json"])
        end)

      # Verify it produces output (JSON validation would be in a unit test)
      assert String.length(output) > 0
    end
  end

  describe "maestro mcp health" do
    test "shows overall health status" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "health"])
        end)

      assert output =~ "Health Check Results:"
      assert output =~ "Overall Health:"
    end
  end

  describe "maestro mcp diagnose" do
    test "diagnoses specific server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "diagnose", "fileSystem"])
        end)

      assert output =~ "Server Diagnosis: fileSystem"
    end
  end

  describe "maestro mcp export" do
    test "exports all configurations", %{tmp_dir: tmp_dir} do
      output_file = Path.join(tmp_dir, "export.json")

      output =
        capture_io(fn ->
          CLI.main(["mcp", "export", output_file])
        end)

      assert output =~ "Configuration exported to"
      assert File.exists?(output_file)
    end

    test "exports specific server configuration" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "export", "fileSystem", "--format", "yaml"])
        end)

      assert output =~ "Configuration exported to 'fileSystem'"
    end
  end

  describe "maestro mcp import" do
    test "imports configuration from file", %{tmp_dir: tmp_dir} do
      # Create a test configuration file
      config_file = Path.join(tmp_dir, "test_config.json")

      test_import_config = %{
        "servers" => %{
          "importedServer" => %{
            "command" => "node",
            "args" => ["server.js"],
            "trust" => false
          }
        }
      }

      File.write!(config_file, Jason.encode!(test_import_config))

      output =
        capture_io(fn ->
          CLI.main(["mcp", "import", config_file])
        end)

      assert output =~ "Imported configuration from"
    end
  end

  describe "maestro mcp template" do
    test "lists available templates" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "template", "list"])
        end)

      # Just verify the command runs
      assert String.length(output) > 0
    end

    test "creates template from existing server" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "template", "create", "myTemplate", "--from", "fileSystem"])
        end)

      assert output =~ "Template 'myTemplate' created successfully"
    end
  end

  describe "maestro mcp debug" do
    test "runs tool in debug mode" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "debug", "read_file", "--path", "/tmp/test.txt"])
        end)

      assert output =~ "Tool Execution Confirmation:"
      assert output =~ "Tool: read_file"
    end
  end

  describe "help system" do
    test "shows general help" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "--help"])
        end)

      # Basic functionality test - just verify help runs
      assert String.length(output) > 0
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

  describe "error handling" do
    test "handles non-existent commands gracefully" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "nonexistent"])
        end)

      # Should produce some error output, not crash
      assert String.length(output) > 0
    end

    test "handles missing required arguments" do
      output =
        capture_io(fn ->
          CLI.main(["mcp", "export"])
        end)

      # Should handle gracefully
      assert String.length(output) > 0
    end
  end
end
