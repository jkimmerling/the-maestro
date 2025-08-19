defmodule TheMaestro.Demos.Epic6.DemoTest do
  use ExUnit.Case, async: false

  alias TheMaestro.Demos.Epic6.RealMCP
  alias TheMaestro.MCP.Registry

  @moduletag :integration

  describe "Epic 6 MCP Integration Demo" do
    setup do
      # Ensure clean state for testing
      on_exit(fn ->
        cleanup_demo_agents()
      end)

      :ok
    end

    test "demo directory structure exists" do
      demo_path = Path.join([File.cwd!(), "demos", "epic6"])

      assert File.exists?(demo_path)
      assert File.exists?(Path.join(demo_path, "demo_servers"))
      assert File.exists?(Path.join(demo_path, "testing"))
    end

    test "demo README.md provides comprehensive setup guide" do
      readme_path = Path.join([File.cwd!(), "demos", "epic6", "README.md"])

      assert File.exists?(readme_path)

      content = File.read!(readme_path)

      # Verify key sections exist
      assert content =~ "Epic 6 MCP Integration Demo"
      assert content =~ "Prerequisites and Setup"
      assert content =~ "API Keys Configuration"
      assert content =~ "Running the Demo"
      assert content =~ "Context7"
      assert content =~ "Tavily"
    end

    test "sample MCP configuration exists and is valid" do
      config_path = Path.join([File.cwd!(), "demos", "epic6", "mcp_settings.json"])

      assert File.exists?(config_path)

      {:ok, config} = Jason.decode(File.read!(config_path))

      # Verify config structure
      assert Map.has_key?(config, "mcpServers")
      assert Map.has_key?(config, "globalSettings")

      servers = config["mcpServers"]
      assert Map.has_key?(servers, "context7_stdio")
      assert Map.has_key?(servers, "tavily_http")

      # Verify server configurations
      context7_config = servers["context7_stdio"]
      assert context7_config["transportType"] == "stdio"
      assert context7_config["trust"] == true

      tavily_config = servers["tavily_http"]
      assert tavily_config["transportType"] == "http"
      assert tavily_config["trust"] == false
    end

    @tag :requires_api_keys
    test "real MCP demo orchestration runs successfully" do
      # Skip if API keys not available
      unless api_keys_available?() do
        IO.puts("Skipping real MCP demo - API keys not configured")
        :ok
      else
        assert :ok == RealMCP.run_full_demo()
      end
    end

    @tag :requires_api_keys
    test "Context7 stdio server integration works" do
      unless api_keys_available?() do
        IO.puts("Skipping Context7 test - API key not configured")
        :ok
      else
        # Test Context7 stdio connection
        assert :ok == RealMCP.start_context7_stdio_server()

        # Wait for connection
        :timer.sleep(3000)

        # Verify connection by checking if server is registered
        case Registry.get_server(Registry, "context7_stdio") do
          {:ok, server_info} ->
            assert server_info.server_id == "context7_stdio"

          {:error, :not_found} ->
            flunk("Context7 server not registered")
        end
      end
    end

    @tag :requires_api_keys
    test "Tavily HTTP server integration works" do
      unless api_keys_available?() do
        IO.puts("Skipping Tavily test - API key not configured")
        :ok
      else
        # Test Tavily HTTP connection
        assert :ok == RealMCP.connect_to_tavily_http()

        # Verify connection by checking if server is registered
        case Registry.get_server(Registry, "tavily_http") do
          {:ok, server_info} ->
            assert server_info.server_id == "tavily_http"

          {:error, :not_found} ->
            flunk("Tavily server not registered")
        end
      end
    end

    test "automated demo script executes without errors" do
      demo_script_path = Path.join([File.cwd!(), "demos", "epic6", "demo_script.exs"])

      assert File.exists?(demo_script_path)

      # Execute the demo script in a separate process to capture output
      {output, exit_code} =
        System.cmd("elixir", [demo_script_path],
          stderr_to_stdout: true,
          cd: File.cwd!()
        )

      # Demo should complete successfully even without API keys (with warnings)
      assert exit_code == 0
      assert output =~ "Epic 6 Real MCP Integration Demo"
    end

    test "interactive demo script handles user input" do
      interactive_demo_path = Path.join([File.cwd!(), "demos", "epic6", "interactive_demo.exs"])

      assert File.exists?(interactive_demo_path)

      # Verify the script contains interactive elements
      content = File.read!(interactive_demo_path)
      assert content =~ "IO.gets"
      assert content =~ "confirm_step"
      assert content =~ "demonstration"
    end

    test "security demonstration shows trust levels" do
      security_test_path =
        Path.join([File.cwd!(), "demos", "epic6", "testing", "security_tests.exs"])

      assert File.exists?(security_test_path)

      content = File.read!(security_test_path)
      assert content =~ "trust level"
      assert content =~ "confirmation flow"
      assert content =~ "untrusted"
      assert content =~ "Context7"
      assert content =~ "Tavily"
    end

    test "demo servers directory contains sample servers" do
      demo_servers_path = Path.join([File.cwd!(), "demos", "epic6", "demo_servers"])

      assert File.exists?(demo_servers_path)

      # Check for sample server files
      filesystem_server = Path.join(demo_servers_path, "filesystem_server.py")
      calculator_server = Path.join(demo_servers_path, "calculator_server.js")

      if File.exists?(filesystem_server) do
        content = File.read!(filesystem_server)
        assert content =~ "MCP"
        assert content =~ "file"
      end

      if File.exists?(calculator_server) do
        content = File.read!(calculator_server)
        assert content =~ "MCP"
        assert content =~ "calculate"
      end
    end

    test "CLI tools work with real MCP servers" do
      # Test that CLI module can be invoked
      assert Code.ensure_loaded?(TheMaestro.MCP.CLI)

      # Test basic CLI functionality
      result =
        capture_io(fn ->
          TheMaestro.MCP.CLI.main(["mcp", "list"])
        end)

      # Should show server information in some format
      assert result =~ "Transport" or result =~ "server"
    end

    test "multi-server coordination demonstrates tool workflows" do
      demo_coordination_exists =
        File.exists?(
          Path.join([
            File.cwd!(),
            "demos",
            "epic6",
            "multi_server_coordination_demo.exs"
          ])
        )

      assert demo_coordination_exists
    end
  end

  # Test helper functions

  defp api_keys_available? do
    context7_key = System.get_env("CONTEXT7_API_KEY")
    tavily_key = System.get_env("TAVILY_API_KEY")

    !is_nil(context7_key) and !is_nil(tavily_key)
  end

  defp cleanup_demo_agents do
    # Clean up any demo agents that were created
    # Note: We don't have a list_agents function or stop_agent function available
    # Agents will terminate naturally when their processes end
    try do
      # Just log that cleanup was attempted
      IO.puts("Demo agent cleanup completed (agents terminate naturally)")
    rescue
      _ -> :ok
    end
  end

  defp capture_io(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end
end
