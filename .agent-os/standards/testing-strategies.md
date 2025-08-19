# Testing Strategies for TheMaestro Project

This document outlines comprehensive testing strategies focused on industry best practices and avoiding anti-patterns that lead to brittle, time-consuming tests.

## TDD (Test-Driven Development) Specification

### Core TDD Principles

Test-Driven Development follows the **Red-Green-Refactor** cycle:

1. **Red**: Write a failing test that describes desired behavior
2. **Green**: Write minimal code to make the test pass  
3. **Refactor**: Improve code quality while keeping tests green

### TDD Best Practices for TheMaestro

#### 1. Start with Behavior, Not Implementation

Focus on what the code should do, not how it does it.

```elixir
# ✅ GOOD - Tests behavior
defmodule TheMaestro.MCP.ToolRegistryTest do
  use ExUnit.Case, async: true
  
  describe "registering a new tool" do
    test "makes tool available for execution" do
      registry = ToolRegistry.new()
      
      tool_spec = %{
        name: "calculate_sum",
        description: "Adds two numbers",
        input_schema: %{type: "object", properties: %{a: %{type: "number"}, b: %{type: "number"}}}
      }
      
      # Red: This should fail initially
      {:ok, updated_registry} = ToolRegistry.register_tool(registry, tool_spec)
      
      assert {:ok, tool} = ToolRegistry.get_tool(updated_registry, "calculate_sum")
      assert tool.name == "calculate_sum"
    end
  end
end
```

#### 2. Use Test Data Builders for Complex Structures

Create reusable builders to avoid duplication and make tests more maintainable.

```elixir
# ✅ GOOD - Reusable test data builders
defmodule TheMaestro.TestDataBuilders do
  def build_mcp_connection(attrs \\ %{}) do
    %TheMaestro.MCP.Connection{
      transport: spawn(fn -> :ok end),
      state: :connected,
      server_info: %{name: "test_server", version: "1.0.0"},
      capabilities: %{tools: %{listChanged: true}},
      tools: []
    }
    |> Map.merge(attrs)
  end
  
  def build_policy(attrs \\ %{}) do
    %{
      name: "Test Policy",
      level: :user,
      settings: %{require_confirmation_threshold: :medium},
      conditions: %{user_id: "test_user"},
      priority: 50
    }
    |> Map.merge(attrs)
  end
  
  def build_security_request(attrs \\ %{}) do
    %TheMaestro.MCP.Security.ConfirmationRequest{
      operation: "read_file",
      risk_level: :low,
      tool_name: "filesystem",
      parameters: %{"path" => "/tmp/test_file.txt"},
      user_id: "test_user",
      server_id: "test_server"
    }
    |> struct!(attrs)
  end
end
```

#### 3. TDD for Error Handling

Write tests for error conditions first to drive proper error handling implementation.

```elixir
# ✅ GOOD - TDD approach to error handling
describe "policy validation" do
  test "rejects policy with invalid trust level" do
    # Red: Define the expected error behavior first
    invalid_policy = build_policy(%{
      settings: %{default_server_trust: :invalid_trust_level}
    })
    
    # This should fail initially, driving implementation
    assert {:error, reason} = PolicyEngine.validate_policy(invalid_policy)
    assert reason =~ "Invalid trust level: :invalid_trust_level"
    assert reason =~ "Must be one of: :trusted, :untrusted, :provisional"
  end
  
  test "rejects policy with malformed conditions" do
    invalid_policy = build_policy(%{
      conditions: %{user_id: nil, invalid_field: "bad_value"}
    })
    
    assert {:error, errors} = PolicyEngine.validate_policy(invalid_policy)
    assert "user_id cannot be nil" in errors
    assert "unknown condition field: invalid_field" in errors
  end
end
```

#### 4. TDD for Complex Business Logic

Break complex logic into testable units and drive implementation through tests.

```elixir
# ✅ GOOD - TDD for risk assessment logic
describe "risk assessment calculation" do
  test "classifies file system writes to system directories as high risk" do
    # Red: This will fail until we implement the logic
    request = %{
      tool_name: "filesystem",
      operation: "write",
      parameters: %{"path" => "/etc/passwd", "content" => "malicious content"}
    }
    
    assert RiskAssessor.assess_risk(request) == :high
  end
  
  test "classifies shell commands with dangerous flags as critical risk" do
    dangerous_commands = [
      "rm -rf /",
      "sudo dd if=/dev/zero of=/dev/sda",
      "chmod -R 777 /",
      "> /dev/sda"
    ]
    
    for command <- dangerous_commands do
      request = %{
        tool_name: "shell",
        operation: "execute", 
        parameters: %{"command" => command}
      }
      
      assert RiskAssessor.assess_risk(request) == :critical,
        "Command '#{command}' should be classified as critical risk"
    end
  end
end
```

### TDD Anti-Patterns to Avoid

#### ❌ DON'T: Write Tests After Code
This leads to tests that just verify what code already does rather than driving design.

#### ❌ DON'T: Test Implementation Details
```elixir
# BAD - Testing internal state
test "connection stores transport pid in state" do
  connection = Connection.new(self(), :connected)
  assert connection.transport == self()  # Implementation detail
end

# GOOD - Test behavior
test "connection can communicate with transport" do
  connection = Connection.new(self(), :connected)
  assert Connection.send_message(connection, %{method: "ping"}) == :ok
end
```

#### ❌ DON'T: Skip the Red Step
Always ensure your test fails first - this validates that the test is actually testing something.

---

## Regular Test Specification - Industry Best Practices

### Test Structure and Organization

#### 1. Use the Arrange-Act-Assert (AAA) Pattern

Structure tests clearly with distinct setup, execution, and verification phases.

```elixir
# ✅ GOOD - Clear AAA structure
test "security confirmation engine approves low-risk operations automatically" do
  # Arrange
  engine = start_supervised!({ConfirmationEngine, []})
  low_risk_request = %ConfirmationRequest{
    operation: "read_file",
    risk_level: :low,
    tool_name: "filesystem",
    parameters: %{"path" => "/tmp/safe_file.txt"}
  }
  
  # Act
  {:ok, result} = ConfirmationEngine.request_confirmation(engine, low_risk_request)
  
  # Assert
  assert result.approved == true
  assert result.reason == "Auto-approved: low risk operation"
  assert result.confidence_score >= 0.8
end
```

#### 2. Isolation and Independence

Each test should run independently without relying on other tests.

```elixir
# ✅ GOOD - Each test is independent
defmodule TheMaestro.MCP.ConnectionManagerTest do
  use ExUnit.Case, async: true
  
  # Fresh setup for each test
  setup do
    {:ok, manager} = start_supervised(ConnectionManager)
    %{manager: manager}
  end
  
  test "establishing connection to new server", %{manager: manager} do
    server_config = %{transport: :stdio, command: ["python", "test_server.py"]}
    
    assert {:ok, connection_id} = ConnectionManager.connect(manager, "test_server", server_config)
    assert {:ok, :connected} = ConnectionManager.get_connection_status(manager, connection_id)
  end
  
  test "handling connection failure", %{manager: manager} do
    invalid_config = %{transport: :stdio, command: ["nonexistent_command"]}
    
    assert {:error, reason} = ConnectionManager.connect(manager, "invalid_server", invalid_config)
    assert reason =~ "Failed to start server process"
  end
  
  test "cleaning up connections on shutdown", %{manager: manager} do
    server_config = %{transport: :stdio, command: ["python", "test_server.py"]}
    {:ok, connection_id} = ConnectionManager.connect(manager, "test_server", server_config)
    
    # Graceful shutdown should clean up connections
    :ok = ConnectionManager.shutdown(manager)
    
    # Connection should be terminated
    assert {:error, :not_found} = ConnectionManager.get_connection_status(manager, connection_id)
  end
end
```

#### 3. Effective Use of ExUnit Features

Leverage ExUnit's built-in capabilities for better test organization and execution.

```elixir
# ✅ GOOD - Leverage ExUnit's capabilities
defmodule TheMaestro.MCP.Security.RiskAssessmentTest do
  use ExUnit.Case, async: true
  use ExUnitProperties  # For property-based testing
  
  alias TheMaestro.MCP.Security.RiskAssessor
  
  # Parameterized tests for similar scenarios
  @high_risk_operations [
    %{tool: "shell", operation: "execute", params: %{"command" => "rm -rf /"}},
    %{tool: "filesystem", operation: "write", params: %{"path" => "/etc/passwd"}},
    %{tool: "network", operation: "connect", params: %{"host" => "malicious.site"}}
  ]
  
  for %{tool: tool, operation: operation, params: params} <- @high_risk_operations do
    test "identifies #{operation} on #{tool} as high risk" do
      request = %{
        tool_name: unquote(tool),
        operation: unquote(operation),
        parameters: unquote(Macro.escape(params))
      }
      
      risk_level = RiskAssessor.assess_risk(request)
      assert risk_level == :high
    end
  end
  
  # Property-based test for edge cases
  property "risk assessment always returns valid risk level" do
    check all tool_name <- string(:alphanumeric, min_length: 1),
              operation <- member_of(["read", "write", "execute", "connect"]),
              params <- map_of(string(:alphanumeric), term()) do
                
      request = %{tool_name: tool_name, operation: operation, parameters: params}
      risk_level = RiskAssessor.assess_risk(request)
      
      assert risk_level in [:low, :medium, :high, :critical]
    end
  end
  
  # Grouped setup with tags
  @tag :integration
  test "risk assessment integrates with policy engine" do
    # Integration test logic here
  end
end
```

### Testing Async and Concurrent Systems

```elixir
# ✅ GOOD - Testing concurrent operations
defmodule TheMaestro.MCP.Tools.ExecutorTest do
  use ExUnit.Case, async: false  # async: false for process-based tests
  
  describe "concurrent tool execution" do
    test "handles multiple simultaneous tool calls safely" do
      executor = start_supervised!(ToolExecutor)
      
      # Execute multiple operations concurrently
      tasks = Enum.map(1..5, fn i ->
        Task.async(fn ->
          ToolExecutor.execute(executor, "echo", %{"message" => "test#{i}"})
        end)
      end)
      
      results = Task.await_many(tasks, 5000)
      
      # All should succeed
      assert Enum.all?(results, fn 
        {:ok, _result} -> true
        _ -> false
      end)
      
      # Results should be properly isolated
      messages = Enum.map(results, fn {:ok, result} -> result.output end)
      assert length(Enum.uniq(messages)) == 5
    end
    
    test "respects concurrent execution limits" do
      executor = start_supervised!({ToolExecutor, max_concurrent: 2})
      
      # Start 5 long-running operations
      tasks = Enum.map(1..5, fn i ->
        Task.async(fn ->
          ToolExecutor.execute(executor, "sleep", %{"duration" => 1000, "id" => i})
        end)
      end)
      
      # Give some time for operations to start
      :timer.sleep(100)
      
      # Check that only 2 are running concurrently
      status = ToolExecutor.get_status(executor)
      assert status.active_executions == 2
      assert status.queued_executions == 3
      
      # Clean up
      Enum.each(tasks, &Task.shutdown/1)
    end
  end
  
  describe "error handling in concurrent scenarios" do
    test "one failing execution doesn't affect others" do
      executor = start_supervised!(ToolExecutor)
      
      # Mix successful and failing operations
      tasks = [
        Task.async(fn -> ToolExecutor.execute(executor, "echo", %{"message" => "success1"}) end),
        Task.async(fn -> ToolExecutor.execute(executor, "invalid_tool", %{}) end),
        Task.async(fn -> ToolExecutor.execute(executor, "echo", %{"message" => "success2"}) end)
      ]
      
      results = Task.await_many(tasks, 5000)
      
      # Should have 2 successes and 1 failure
      successes = Enum.count(results, fn {:ok, _} -> true; _ -> false end)
      failures = Enum.count(results, fn {:error, _} -> true; _ -> false end)
      
      assert successes == 2
      assert failures == 1
    end
  end
end
```

### Testing Phoenix LiveView Components

```elixir
# ✅ GOOD - Testing LiveView interactions
defmodule TheMaestroWeb.Live.Components.SecurityConfirmationDialogTest do
  use TheMaestroWeb.ConnCase, async: true
  
  import Phoenix.LiveViewTest
  
  alias TheMaestroWeb.Live.Components.SecurityConfirmationDialog
  alias TheMaestro.MCP.Security.ConfirmationRequest
  
  describe "security confirmation dialog" do
    test "displays risk information and operation details" do
      request = %ConfirmationRequest{
        operation: "execute_shell_command",
        risk_level: :high,
        tool_name: "shell",
        parameters: %{"command" => "sudo rm /important_file"},
        risk_factors: ["system_file_access", "destructive_operation"]
      }
      
      rendered = render_component(SecurityConfirmationDialog, request: request)
      
      assert rendered =~ "High Risk Operation"
      assert rendered =~ "execute_shell_command"
      assert rendered =~ "sudo rm /important_file"
      assert rendered =~ "system_file_access"
      assert rendered =~ "destructive_operation"
    end
    
    test "handles approval action" do
      request = %ConfirmationRequest{
        operation: "read_file",
        risk_level: :medium,
        tool_name: "filesystem",
        parameters: %{"path" => "/etc/config"}
      }
      
      {:ok, view, _html} = live_isolated(build_conn(), SecurityConfirmationDialog, 
        session: %{"request" => request})
      
      # Approve the request
      result = view |> element("[data-testid=approve-button]") |> render_click()
      
      assert_receive {:confirmation_result, %{approved: true, reason: reason}}
      assert reason =~ "User approved"
    end
  end
end
```

### Testing Anti-Patterns to Avoid

#### ❌ DON'T: Create Overly Complex Test Setup

```elixir
# BAD - Brittle, complex setup
setup do
  {:ok, db} = start_supervised(Database)
  {:ok, cache} = start_supervised(Cache) 
  {:ok, auth} = start_supervised({AuthService, [db: db, cache: cache]})
  {:ok, policy} = start_supervised({PolicyEngine, [auth: auth]})
  {:ok, mcp} = start_supervised({MCPServer, [policy: policy, auth: auth, db: db]})
  
  # Create test users
  {:ok, user1} = AuthService.create_user(auth, %{username: "test1", role: "admin"})
  {:ok, user2} = AuthService.create_user(auth, %{username: "test2", role: "user"})
  
  # Setup policies
  PolicyEngine.create_policy(policy, "test_policy", %{...})
  
  # 50 more lines of setup...
  
  %{everything: %{db: db, cache: cache, auth: auth, policy: policy, mcp: mcp, users: [user1, user2]}}
end

# GOOD - Minimal, focused setup
setup do
  %{policy_engine: start_supervised!(PolicyEngine)}
end

# Use setup_all for expensive operations that can be shared
setup_all do
  %{shared_data: load_test_data()}
end
```

#### ❌ DON'T: Test Multiple Things in One Test

```elixir
# BAD - Tests too much at once
test "complete mcp workflow" do
  # 1. Tests connection establishment
  {:ok, connection} = MCPClient.connect("test_server")
  assert connection.state == :connected
  
  # 2. Tests authentication  
  {:ok, session} = MCPClient.authenticate(connection, "user", "pass")
  assert session.authenticated == true
  
  # 3. Tests tool discovery
  {:ok, tools} = MCPClient.list_tools(session)
  assert length(tools) > 0
  
  # 4. Tests tool execution
  {:ok, result} = MCPClient.execute_tool(session, "echo", %{"message" => "test"})
  assert result.output == "test"
  
  # 5. Tests cleanup
  :ok = MCPClient.disconnect(connection)
  
  # If this fails, you don't know which part broke!
end

# GOOD - Focused, single responsibility tests
describe "mcp connection lifecycle" do
  test "establishes connection successfully" do
    assert {:ok, connection} = MCPClient.connect("test_server")
    assert connection.state == :connected
  end
  
  test "authenticates with valid credentials" do
    {:ok, connection} = MCPClient.connect("test_server")
    assert {:ok, session} = MCPClient.authenticate(connection, "user", "pass")
    assert session.authenticated == true
  end
  
  test "discovers available tools after authentication" do
    {:ok, connection} = MCPClient.connect("test_server")
    {:ok, session} = MCPClient.authenticate(connection, "user", "pass")
    
    assert {:ok, tools} = MCPClient.list_tools(session)
    assert is_list(tools)
    assert length(tools) > 0
  end
end
```

#### ❌ DON'T: Use Sleep for Timing

```elixir
# BAD - Brittle timing
test "async operation completes" do
  start_async_operation()
  :timer.sleep(1000)  # Brittle - might be too short or too long
  assert operation_completed?()
end

# GOOD - Use proper synchronization
test "async operation completes" do
  {:ok, task} = start_async_operation()
  assert {:ok, result} = Task.await(task, 5000)
  assert result.status == :completed
end

# GOOD - Use test helpers for polling
test "background process updates state" do
  start_background_process()
  
  assert_eventually(fn -> 
    state = get_process_state()
    state.status == :completed
  end, timeout: 5000)
end
```

#### ❌ DON'T: Ignore Test Performance

```elixir
# BAD - Slow, resource-intensive test
test "processes large dataset" do
  large_dataset = Enum.map(1..100_000, fn i -> create_complex_record(i) end)
  # This test will be slow and may time out
  results = DataProcessor.process_all(large_dataset)
  assert length(results) == 100_000
end

# GOOD - Test with representative sample
test "processes dataset correctly" do
  sample_dataset = [
    create_complex_record(1),
    create_edge_case_record(),
    create_normal_record()
  ]
  
  results = DataProcessor.process_all(sample_dataset)
  assert length(results) == 3
  assert Enum.all?(results, &valid_result?/1)
end

# For performance testing, use separate tagged tests
@tag :performance
@tag timeout: 60_000  
test "handles large datasets within performance bounds" do
  # Performance-specific test with appropriate timeout
end
```

### Test Helpers and Utilities

Create reusable helpers to reduce duplication and improve test maintainability.

```elixir
# ✅ GOOD - Shared test utilities
defmodule TheMaestro.TestHelpers do
  @doc """
  Waits for a condition to be true within a timeout period.
  More reliable than :timer.sleep/1 for async operations.
  """
  def wait_for_condition(condition_fn, timeout \\ 5000) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_for_condition_loop(condition_fn, end_time)
  end
  
  defp wait_for_condition_loop(condition_fn, end_time) do
    if condition_fn.() do
      :ok
    else
      if System.monotonic_time(:millisecond) < end_time do
        :timer.sleep(50)
        wait_for_condition_loop(condition_fn, end_time)
      else
        {:error, :timeout}
      end
    end
  end
  
  @doc """
  Assert that a condition becomes true within a timeout.
  Useful for async operations and state changes.
  """
  defmacro assert_eventually(assertion, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    
    quote do
      :ok = TheMaestro.TestHelpers.wait_for_condition(fn -> 
        try do
          unquote(assertion)
          true
        rescue
          ExUnit.AssertionError -> false
        end
      end, unquote(timeout))
    end
  end
  
  @doc """
  Creates a temporary MCP server for testing.
  Automatically cleans up after test completion.
  """
  def create_test_mcp_server(opts \\ []) do
    port = Keyword.get(opts, :port, find_free_port())
    tools = Keyword.get(opts, :tools, default_test_tools())
    
    {:ok, server} = TestMCPServer.start_link(port: port, tools: tools)
    
    # Register cleanup
    on_exit(fn -> 
      TestMCPServer.stop(server)
    end)
    
    %{server: server, port: port, base_url: "http://localhost:#{port}"}
  end
  
  defp find_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
  
  defp default_test_tools do
    [
      %{name: "echo", description: "Echo input", schema: %{type: "object"}},
      %{name: "add", description: "Add numbers", schema: %{type: "object"}}
    ]
  end
end
```

### Test Organization Best Practices

#### Directory Structure
```
test/
├── support/
│   ├── conn_case.ex          # Phoenix connection test helpers
│   ├── data_case.ex          # Database test helpers  
│   ├── test_helpers.ex       # General test utilities
│   └── test_data_builders.ex # Data builders for complex structures
├── the_maestro/
│   ├── mcp/                  # MCP-related tests
│   ├── security/             # Security feature tests
│   ├── providers/            # LLM provider tests
│   └── tooling/              # Tool execution tests
└── the_maestro_web/          # Phoenix web tests
```

#### Test Tags and Configuration

```elixir
# Use tags to categorize tests
@tag :unit          # Fast, isolated unit tests
@tag :integration   # Integration tests with external dependencies
@tag :performance   # Performance benchmarks
@tag :slow          # Tests that take >1 second
@tag :external      # Tests requiring external services

# In test configuration
config :ex_unit,
  exclude: [:performance, :external],  # Exclude slow tests by default
  timeout: 30_000                      # Global timeout
```

## Summary

These testing strategies focus on:

- **Behavior over Implementation**: Tests should verify what the code does, not how it does it
- **Maintainable Structure**: Clear, focused tests that are easy to understand and modify
- **Proper Isolation**: Each test runs independently without side effects
- **Realistic Data**: Use builders and factories instead of hardcoded values  
- **Clear Failure Messages**: Tests should clearly indicate what went wrong
- **Performance Awareness**: Tests should run quickly and reliably

Following these practices will result in a test suite that:
- Provides confidence in code correctness
- Serves as living documentation
- Enables safe refactoring
- Runs quickly and reliably
- Is easy to maintain and extend

The key is to focus on testing behaviors and outcomes rather than implementation details, use proper setup and teardown, and write tests that clearly express intent and expected behavior.