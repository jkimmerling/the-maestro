defmodule TheMaestro.MCP.Security.ConfirmationEngineTest do
  use ExUnit.Case, async: true

  alias TheMaestro.MCP.Security.{ConfirmationEngine, TrustManager}
  alias TheMaestro.MCP.Security.ConfirmationEngine.{ConfirmationRequest, ConfirmationResult}

  setup do
    # Handle case where TrustManager is already started
    trust_pid =
      case TrustManager.start_link(name: TrustManager) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    %{trust_manager: trust_pid}
  end

  describe "evaluate_confirmation_requirement/3" do
    test "requires confirmation for high-risk operations" do
      tool = %{name: "execute_command", server_id: "shell_server"}
      params = %{"command" => "rm -rf /"}
      context = %{user_id: "user123", server_id: "shell_server"}

      request = ConfirmationEngine.evaluate_confirmation_requirement(tool, params, context)

      assert %ConfirmationRequest{
               requires_confirmation: true,
               risk_assessment: %{risk_level: :critical}
             } = request

      assert String.contains?(request.reason, "Risk level: critical")
    end

    test "does not require confirmation for low-risk trusted operations", %{trust_manager: trust_pid} do
      tool = %{name: "read_file", server_id: "filesystem_server"}
      params = %{"path" => "/tmp/safe.txt"}
      context = %{user_id: "user123", server_id: "filesystem_server"}

      # First trust the server and whitelist the tool
      GenServer.call(trust_pid, {:grant_server_trust, "filesystem_server", :trusted, "user123"})
      GenServer.call(trust_pid, {:whitelist_tool, "filesystem_server", "read_file", "user123"})

      request = ConfirmationEngine.evaluate_confirmation_requirement(tool, params, context)

      assert %ConfirmationRequest{
               requires_confirmation: false,
               risk_assessment: %{risk_level: :low}
             } = request
    end

    test "requires confirmation for untrusted servers even with low risk" do
      tool = %{name: "read_file", server_id: "untrusted_server"}
      params = %{"path" => "/tmp/safe.txt"}
      context = %{user_id: "user123", server_id: "untrusted_server"}

      request = ConfirmationEngine.evaluate_confirmation_requirement(tool, params, context)

      assert %ConfirmationRequest{
               requires_confirmation: true
             } = request

      assert String.contains?(request.reason, "Trust verification required")
    end
  end

  describe "process_confirmation_choice/3" do
    test "execute_once allows execution without changing trust" do
      request = build_test_request()
      context = %{user_id: "user123", session_id: "sess1", interface: :web}

      result = ConfirmationEngine.process_confirmation_choice(request, :execute_once, context)

      assert %ConfirmationResult{
               decision: :allow,
               choice: :execute_once,
               trust_updated: false,
               audit_logged: true
             } = result
    end

    test "always_allow_tool whitelists tool and allows execution", %{trust_manager: trust_pid} do
      request = build_test_request()
      context = %{user_id: "user123", session_id: "sess1", interface: :web}

      result =
        ConfirmationEngine.process_confirmation_choice(request, :always_allow_tool, context)

      assert %ConfirmationResult{
               decision: :allow,
               choice: :always_allow_tool,
               trust_updated: true,
               audit_logged: true
             } = result

      # Verify tool was whitelisted
      trust = GenServer.call(trust_pid, {:get_server_trust, "test_server"})
      assert "test_tool" in trust.whitelist_tools
    end

    test "always_trust_server trusts server and allows execution", %{trust_manager: trust_pid} do
      request = build_test_request()
      context = %{user_id: "user123", session_id: "sess1", interface: :web}

      result =
        ConfirmationEngine.process_confirmation_choice(request, :always_trust_server, context)

      assert %ConfirmationResult{
               decision: :allow,
               choice: :always_trust_server,
               trust_updated: true,
               audit_logged: true
             } = result

      # Verify server was trusted
      trust_level = GenServer.call(trust_pid, {:server_trust_level, "test_server"})
      assert trust_level == :trusted
    end

    test "block_tool blacklists tool and denies execution", %{trust_manager: trust_pid} do
      request = build_test_request()
      context = %{user_id: "user123", session_id: "sess1", interface: :web}

      result = ConfirmationEngine.process_confirmation_choice(request, :block_tool, context)

      assert %ConfirmationResult{
               decision: :deny,
               choice: :block_tool,
               trust_updated: true,
               audit_logged: true
             } = result

      # Verify tool was blacklisted
      trust = GenServer.call(trust_pid, {:get_server_trust, "test_server"})
      assert "test_tool" in trust.blacklist_tools
    end

    test "cancel denies execution without changing trust" do
      request = build_test_request()
      context = %{user_id: "user123", session_id: "sess1", interface: :web}

      result = ConfirmationEngine.process_confirmation_choice(request, :cancel, context)

      assert %ConfirmationResult{
               decision: :deny,
               choice: :cancel,
               trust_updated: false,
               audit_logged: true
             } = result
    end
  end

  describe "handle_headless_security/2" do
    test "blocks critical risk operations by default" do
      request = %ConfirmationRequest{
        tool: %{name: "execute_command", server_id: "shell"},
        parameters: %{"command" => "rm -rf /"},
        risk_assessment: %{risk_level: :critical}
      }

      result = ConfirmationEngine.handle_headless_security(request)

      assert %ConfirmationResult{
               decision: :deny,
               audit_logged: true
             } = result

      assert String.contains?(result.message, "Critical risk")
    end

    test "allows low risk operations" do
      request = %ConfirmationRequest{
        tool: %{name: "read_file", server_id: "fs"},
        parameters: %{"path" => "/tmp/safe.txt"},
        risk_assessment: %{risk_level: :low}
      }

      result = ConfirmationEngine.handle_headless_security(request)

      assert %ConfirmationResult{
               decision: :allow,
               audit_logged: true
             } = result
    end

    test "respects auto_block_high_risk policy setting" do
      request = %ConfirmationRequest{
        risk_assessment: %{risk_level: :high}
      }

      # With auto_block_high_risk enabled (default)
      result1 =
        ConfirmationEngine.handle_headless_security(request, %{auto_block_high_risk: true})

      assert result1.decision == :deny

      # With auto_block_high_risk disabled
      result2 =
        ConfirmationEngine.handle_headless_security(request, %{auto_block_high_risk: false})

      assert result2.decision == :allow
    end
  end

  ## Helper Functions

  defp build_test_request do
    %ConfirmationRequest{
      tool: %{name: "test_tool", server_id: "test_server"},
      parameters: %{"param" => "value"},
      context: %{user_id: "user123"},
      risk_assessment: %{risk_level: :medium, factors: []},
      requires_confirmation: true,
      reason: "Test confirmation"
    }
  end

end
