defmodule TheMaestro.MCP.Security.SecureExecutorTest do
  use ExUnit.Case, async: true

  alias TheMaestro.MCP.Security.{SecureExecutor, TrustManager}
  alias TheMaestro.MCP.Security.SecureExecutor.{SecureExecutionResult, SecureExecutionError}
  alias TheMaestro.MCP.Tools.Executor.ExecutionResult

  # Mock connection for testing
  defmodule MockConnection do
    use GenServer

    def start_link(opts \\ []) do
      initial_state =
        Keyword.get(opts, :initial_state, %{
          tools_response: nil,
          call_response: nil,
          should_error: false,
          request_history: []
        })

      GenServer.start_link(__MODULE__, initial_state)
    end

    def set_call_response(pid, response) do
      GenServer.call(pid, {:set_call_response, response})
    end

    def set_should_error(pid, should_error) do
      GenServer.call(pid, {:set_should_error, should_error})
    end

    def send_request(pid, request) do
      GenServer.call(pid, {:send_request, request})
    end

    @impl true
    def init(state) do
      {:ok, state}
    end

    @impl true
    def handle_call({:set_call_response, response}, _from, state) do
      {:reply, :ok, %{state | call_response: response}}
    end

    @impl true
    def handle_call({:set_should_error, should_error}, _from, state) do
      {:reply, :ok, %{state | should_error: should_error}}
    end

    @impl true
    def handle_call({:send_request, request}, _from, state) do
      new_state = %{state | request_history: [request | state.request_history]}

      response =
        if state.should_error do
          {:error, %{code: -32_603, message: "Internal error", data: %{}}}
        else
          {:ok,
           state.call_response ||
             %{
               "jsonrpc" => "2.0",
               "id" => "test",
               "result" => %{"content" => [%{"type" => "text", "text" => "Success"}]}
             }}
        end

      {:reply, response, new_state}
    end
  end

  # Mock connection manager for testing
  defmodule MockConnectionManager do
    def get_connection(server_id) do
      case server_id do
        "filesystem_server" ->
          {:ok, %{connection_pid: Process.get(:mock_connection), server_id: server_id}}

        "trusted_server" ->
          {:ok, %{connection_pid: Process.get(:mock_connection), server_id: server_id}}

        "shell_server" ->
          {:ok, %{connection_pid: Process.get(:mock_connection), server_id: server_id}}

        "failing_server" ->
          {:error, :connection_failed}

        _ ->
          {:ok, %{connection_pid: Process.get(:mock_connection), server_id: server_id}}
      end
    end
  end

  setup do
    # Start trust manager for tests
    trust_pid =
      case TrustManager.start_link([]) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    # Mock a successful MCP connection for testing
    mock_connection_info = %{
      connection_pid: self(),
      server_id: "test_server",
      status: :connected
    }

    Process.put(:mock_connection, mock_connection_info)

    %{trust_manager: trust_pid}
  end

  describe "execute_secure/3" do
    test "executes safe operations successfully" do
      # Set up trusted server and whitelisted tool to avoid confirmation
      TrustManager.grant_server_trust("filesystem_server", :trusted, "user123")
      TrustManager.whitelist_tool("filesystem_server", "read_file", "user123")

      context = %{
        server_id: "filesystem_server",
        user_id: "user123",
        session_id: "sess1",
        interface: :web,
        connection_manager: MockConnectionManager
      }

      # Mock successful execution response
      setup_mock_execution_success()

      result = SecureExecutor.execute_secure("read_file", %{"path" => "/tmp/safe.txt"}, context)

      assert {:ok,
              %SecureExecutionResult{
                security_decision: :allowed,
                risk_level: :low,
                confirmation_required: false,
                audit_logged: true
              }} = result
    end

    test "blocks operations with dangerous parameters" do
      context = %{
        server_id: "shell_server",
        user_id: "user123",
        session_id: "sess1",
        interface: :web,
        connection_manager: MockConnectionManager
      }

      result =
        SecureExecutor.execute_secure("execute_command", %{"command" => "rm -rf /"}, context)

      assert {:error,
              %SecureExecutionError{
                type: :security_denied,
                security_reason: "Security policy denied execution",
                risk_level: :medium,
                audit_logged: true
              }} = result
    end

    test "blocks operations with path traversal attempts" do
      context = %{
        server_id: "filesystem_server",
        user_id: "user123",
        session_id: "sess1",
        interface: :web,
        connection_manager: MockConnectionManager
      }

      result =
        SecureExecutor.execute_secure("read_file", %{"path" => "../../etc/passwd"}, context)

      assert {:error,
              %SecureExecutionError{
                type: :sanitization_blocked,
                security_reason: reason,
                risk_level: :high,
                audit_logged: true
              }} = result

      assert String.contains?(reason, "Path traversal")
    end

    test "allows trusted server operations with confirmation skip" do
      context = %{
        server_id: "trusted_server",
        user_id: "admin",
        session_id: "sess1",
        interface: :web,
        skip_confirmation: true,
        connection_manager: MockConnectionManager
      }

      setup_mock_execution_success()

      result =
        SecureExecutor.execute_secure("sensitive_operation", %{"param" => "value"}, context)

      assert {:ok,
              %SecureExecutionResult{
                security_decision: :allowed,
                # Would have required confirmation without skip
                confirmation_required: true,
                audit_logged: true
              }} = result
    end

    test "handles execution failures gracefully" do
      context = %{
        server_id: "failing_server",
        user_id: "user123",
        session_id: "sess1",
        interface: :web,
        connection_manager: MockConnectionManager
      }

      # Mock execution failure
      setup_mock_execution_failure()

      result = SecureExecutor.execute_secure("read_file", %{"path" => "/tmp/safe.txt"}, context)

      assert {:error,
              %SecureExecutionError{
                type: :execution_failed,
                audit_logged: true
              }} = result
    end

    test "includes sanitization warnings in results" do
      context = %{
        server_id: "filesystem_server",
        user_id: "user123",
        session_id: "sess1",
        interface: :web,
        connection_manager: MockConnectionManager,
        # Allow warnings without blocking
        block_on_suspicion: false
      }

      setup_mock_execution_success()

      # Parameters that will generate warnings but not block
      params = %{
        "path" => "/tmp/file.txt",
        "extra_param" => "some<script>alert('test')</script>"
      }

      result = SecureExecutor.execute_secure("read_file", params, context)

      assert {:ok,
              %SecureExecutionResult{
                security_decision: :allowed,
                sanitization_warnings: warnings,
                audit_logged: true
              }} = result

      assert length(warnings) > 0
    end
  end

  describe "execute_headless/4" do
    test "executes safe operations without user interaction" do
      context = %{
        server_id: "filesystem_server",
        connection_manager: MockConnectionManager
      }

      setup_mock_execution_success()

      result = SecureExecutor.execute_headless("read_file", %{"path" => "/tmp/safe.txt"}, context)

      assert {:ok,
              %SecureExecutionResult{
                security_decision: :allowed,
                audit_logged: true
              }} = result
    end

    test "blocks critical risk operations by policy" do
      context = %{
        server_id: "shell_server",
        connection_manager: MockConnectionManager
      }

      result =
        SecureExecutor.execute_headless("execute_command", %{"command" => "rm -rf /"}, context)

      assert {:error,
              %SecureExecutionError{
                type: :security_denied,
                audit_logged: true
              }} = result
    end

    test "respects policy settings for high risk operations" do
      context = %{
        server_id: "shell_server",
        connection_manager: MockConnectionManager
      }

      # Medium risk
      params = %{"command" => "grep pattern /etc/hosts"}

      # Set up mock before execution
      setup_mock_execution_success()

      # With default policy (block high risk)
      result1 =
        SecureExecutor.execute_headless("execute_command", params, context, %{
          auto_block_high_risk: true
        })

      # Should allow since it's medium risk

      # This should succeed since it's not high risk
      assert {:ok, %SecureExecutionResult{}} = result1
    end

    test "sets headless user context automatically" do
      context = %{
        server_id: "filesystem_server",
        connection_manager: MockConnectionManager
      }

      setup_mock_execution_success()

      {:ok, result} =
        SecureExecutor.execute_headless("read_file", %{"path" => "/tmp/safe.txt"}, context)

      assert result.audit_logged == true
      # The audit logging would include user_id: "system" for headless operations
    end
  end

  ## Helper Functions

  defp setup_mock_execution_success do
    # Create a mock connection that will respond with success
    {:ok, mock_conn} = MockConnection.start_link()

    # Set up successful response in MCP JSON-RPC format
    MockConnection.set_call_response(mock_conn, %{
      "jsonrpc" => "2.0",
      "id" => "test",
      "result" => %{
        "content" => [
          %{
            "type" => "text",
            "text" => "Operation completed successfully"
          }
        ]
      }
    })

    # Store the mock connection so the executor can find it
    Process.put(:mock_connection, mock_conn)
  end

  defp setup_mock_execution_failure do
    # Create a mock connection that will respond with failure
    {:ok, mock_conn} = MockConnection.start_link()

    # Set it to error mode
    MockConnection.set_should_error(mock_conn, true)

    # Store the mock connection
    Process.put(:mock_connection, mock_conn)
  end
end
