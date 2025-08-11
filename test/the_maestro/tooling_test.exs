defmodule TheMaestro.ToolingTest do
  use ExUnit.Case, async: true
  doctest TheMaestro.Tooling

  alias TheMaestro.Tooling

  # Test tool definition and executor
  @test_tool_definition %{
    "name" => "test_registry_tool",
    "description" => "Test tool for registry",
    "parameters" => %{
      "type" => "object",
      "properties" => %{
        "input" => %{"type" => "string", "description" => "Test input"}
      },
      "required" => ["input"]
    }
  }
  
  # Helper to create the test tool executor
  defp test_tool_executor do
    fn %{"input" => input} ->
      {:ok, %{"output" => "processed: #{input}"}}
    end
  end

  # Helper to register the test tool
  defp setup_test_tool do
    Tooling.register_tool("test_registry_tool", __MODULE__, @test_tool_definition, test_tool_executor())
  end

  describe "tool registry functionality" do
    test "registers tools with proper format" do
      assert :ok = setup_test_tool()
    end

    test "get_tool_definitions/0 returns list of definitions" do
      setup_test_tool()
      definitions = Tooling.get_tool_definitions()
      
      assert is_list(definitions)
      # Should include the tool we registered
      tool_names = Enum.map(definitions, & &1["name"])
      assert "test_registry_tool" in tool_names
    end

    test "execute_tool/2 runs registered tools" do
      setup_test_tool()
      # Should be able to execute the tool we registered
      result = Tooling.execute_tool("test_registry_tool", %{"input" => "hello"})
      
      assert {:ok, %{"output" => "processed: hello"}} = result
    end

    test "execute_tool/2 handles unknown tools" do
      result = Tooling.execute_tool("nonexistent_tool", %{})
      
      assert {:error, "Tool 'nonexistent_tool' not found"} = result
    end

    test "execute_tool/2 validates arguments" do
      setup_test_tool()
      # Missing required parameter
      result = Tooling.execute_tool("test_registry_tool", %{})
      
      assert {:error, reason} = result
      assert String.contains?(reason, "Missing required parameters")
    end

    test "tool_exists?/1 checks tool registration" do
      setup_test_tool()
      assert Tooling.tool_exists?("test_registry_tool") == true
      assert Tooling.tool_exists?("nonexistent_tool") == false
    end

    test "list_tools/0 returns all registered tools" do
      setup_test_tool()
      tools = Tooling.list_tools()
      
      assert is_map(tools)
      assert Map.has_key?(tools, "test_registry_tool")
    end
  end

  describe "tool execution safety" do
    test "handles tool execution exceptions" do
      # Register a tool that throws
      executor = fn _args -> raise "tool exception" end
      definition = %{
        "name" => "exception_tool",
        "description" => "Tool that throws",
        "parameters" => %{"type" => "object", "properties" => %{}, "required" => []}
      }
      
      Tooling.register_tool("exception_tool", __MODULE__, definition, executor)
      
      result = Tooling.execute_tool("exception_tool", %{})
      assert {:error, reason} = result
      assert String.contains?(reason, "Tool execution failed")
    end

    test "handles tool timeouts" do
      # Register a slow tool
      executor = fn _args -> 
        Process.sleep(100) 
        {:ok, %{"result" => "slow"}}
      end
      
      definition = %{
        "name" => "slow_tool",
        "description" => "Slow tool",
        "parameters" => %{"type" => "object", "properties" => %{}, "required" => []}
      }
      
      Tooling.register_tool("slow_tool", __MODULE__, definition, executor)
      
      # Should still complete (100ms is reasonable)
      result = Tooling.execute_tool("slow_tool", %{})
      assert {:ok, %{"result" => "slow"}} = result
    end
  end

  describe "concurrent tool operations" do
    test "handles concurrent tool executions" do
      setup_test_tool()
      
      tasks = for i <- 1..10 do
        Task.async(fn ->
          Tooling.execute_tool("test_registry_tool", %{"input" => "test#{i}"})
        end)
      end
      
      results = Task.await_many(tasks)
      
      # All should succeed
      assert Enum.all?(results, fn 
        {:ok, _} -> true
        _ -> false
      end)
    end

    test "registry is thread-safe" do
      tasks = for _i <- 1..20 do
        Task.async(fn ->
          Tooling.get_tool_definitions()
        end)
      end
      
      results = Task.await_many(tasks)
      first_result = hd(results)
      
      # All results should be identical
      assert Enum.all?(results, fn result -> result == first_result end)
    end
  end
end