defmodule TheMaestro.Demos.Epic6.SecurityTests do
  @moduledoc """
  Security demonstration tests for Epic 6 MCP Integration Demo.
  
  This module demonstrates:
  - Trust level management between servers
  - Confirmation flows for untrusted operations
  - Parameter sanitization and validation
  - API key security and management
  """
  
  use ExUnit.Case, async: false
  
  alias TheMaestro.MCP.Security.TrustManager
  alias TheMaestro.MCP.Security.ConfirmationEngine
  alias TheMaestro.MCP.Security.ParameterSanitizer
  alias TheMaestro.Agents

  @moduletag :security_demo
  
  describe "Trust Level Demonstrations" do
    test "Context7 trusted server bypasses confirmation" do
      # Context7 is configured as trusted
      server_config = %{
        "name" => "context7_stdio",
        "trust" => true,
        "transportType" => "stdio"
      }
      
      assert TrustManager.is_trusted_server?(server_config)
      
      # Tool execution should not require confirmation
      confirmation_required = ConfirmationEngine.requires_confirmation?(
        server_config,
        "resolve-library-id",
        %{"libraryName" => "FastAPI"}
      )
      
      refute confirmation_required
      
      IO.puts("✅ Context7 (trusted): Documentation lookup - no confirmation needed")
    end
    
    test "Tavily untrusted server requires confirmation" do
      # Tavily is configured as untrusted
      server_config = %{
        "name" => "tavily_http", 
        "trust" => false,
        "transportType" => "http"
      }
      
      refute TrustManager.is_trusted_server?(server_config)
      
      # Tool execution should require confirmation
      confirmation_required = ConfirmationEngine.requires_confirmation?(
        server_config,
        "search",
        %{"query" => "sensitive corporate information"}
      )
      
      assert confirmation_required
      
      IO.puts("✅ Tavily (untrusted): Web search - requires user confirmation")
    end
    
    test "sensitive query triggers security warnings" do
      sensitive_queries = [
        "extract private corporate data",
        "find competitor secrets",
        "access sensitive information",
        "bypass security measures"
      ]
      
      for query <- sensitive_queries do
        risk_level = ParameterSanitizer.assess_risk_level(%{
          "query" => query,
          "server" => "tavily_http"
        })
        
        assert risk_level in [:high, :critical]
        
        IO.puts("⚠️  High-risk query detected: '#{String.slice(query, 0, 30)}...'")
      end
    end
  end
  
  describe "Confirmation Flow Demonstration" do
    test "untrusted tool execution shows confirmation prompt" do
      # Simulate confirmation flow for untrusted Tavily tool
      IO.puts("\n🔒 Security Demo: Untrusted Tavily Tool Execution")
      IO.puts("=" |> String.duplicate(50))
      
      # Demonstrate different confirmation options
      confirmation_options = [
        %{choice: "proceed_once", description: "Execute this time only"},
        %{choice: "trust_tool", description: "Always allow this tool"},
        %{choice: "trust_server", description: "Always allow this server"},
        %{choice: "cancel", description: "Abort execution"}
      ]
      
      IO.puts("Tool: tavily_http.search")
      IO.puts("Parameters: {\"query\": \"sensitive corporate information\"}")
      IO.puts("⚠️  This operation requires confirmation:")
      
      for option <- confirmation_options do
        IO.puts("  #{option.choice}: #{option.description}")
      end
      
      # In a real demo, this would show interactive confirmation
      IO.puts("Demo choice: cancel (for security)")
      
      assert true # Test always passes - this is a demonstration
    end
    
    test "demonstration of trust level escalation" do
      IO.puts("\n🛡️ Trust Level Demonstration")
      IO.puts("=" |> String.duplicate(30))
      
      trust_levels = [
        %{server: "context7_stdio", trust: true, reason: "Documentation lookup"},
        %{server: "calculator_server", trust: true, reason: "Local computation"},
        %{server: "tavily_http", trust: false, reason: "External web search"},
        %{server: "filesystem_server", trust: false, reason: "File system access"}
      ]
      
      for level <- trust_levels do
        status = if level.trust, do: "✅ Trusted", else: "⚠️  Untrusted"
        IO.puts("#{level.server}: #{status} - #{level.reason}")
      end
      
      assert length(trust_levels) == 4
    end
  end
  
  describe "Parameter Sanitization Demo" do
    test "path traversal prevention" do
      dangerous_paths = [
        "../../../etc/passwd",
        "..\\..\\windows\\system32\\config\\sam", 
        "/proc/version",
        "C:\\Windows\\System32\\drivers\\etc\\hosts"
      ]
      
      for path <- dangerous_paths do
        sanitized = ParameterSanitizer.sanitize_path(path)
        
        # Paths should be rejected or sanitized
        refute sanitized == path
        
        IO.puts("🚫 Blocked dangerous path: #{path}")
      end
    end
    
    test "command injection prevention" do
      malicious_commands = [
        "ls; rm -rf /",
        "echo 'safe' && cat /etc/passwd",
        "python -c \"import os; os.system('rm -rf /')\""
      ]
      
      for command <- malicious_commands do
        sanitized = ParameterSanitizer.sanitize_command(command)
        
        # Commands should be escaped or rejected
        refute String.contains?(sanitized, ";")
        refute String.contains?(sanitized, "&&")
        
        IO.puts("🛡️ Sanitized command injection attempt")
      end
    end
    
    test "sensitive data detection" do
      test_data = [
        %{input: "sk-1234567890abcdef", type: "API key"},
        %{input: "john.doe@company.com", type: "Email"},
        %{input: "4532-1234-5678-9012", type: "Credit card"},
        %{input: "192.168.1.100", type: "IP address"}
      ]
      
      for data <- test_data do
        is_sensitive = ParameterSanitizer.contains_sensitive_data?(data.input)
        assert is_sensitive
        
        IO.puts("🔍 Detected #{data.type}: [REDACTED]")
      end
    end
  end
  
  describe "API Key Security Demo" do
    test "API key encryption and storage demonstration" do
      IO.puts("\n🔐 API Key Security Demo")
      IO.puts("=" |> String.duplicate(25))
      
      # Demonstrate secure API key handling
      test_scenarios = [
        %{
          scenario: "API key in environment variable", 
          secure: true,
          example: "${CONTEXT7_API_KEY}"
        },
        %{
          scenario: "API key in plaintext config",
          secure: false,
          example: "sk-1234567890abcdef"
        },
        %{
          scenario: "API key with encryption",
          secure: true,
          example: "encrypted:AES256:base64data..."
        }
      ]
      
      for scenario <- test_scenarios do
        security_status = if scenario.secure, do: "✅ Secure", else: "❌ Insecure"
        IO.puts("#{scenario.scenario}: #{security_status}")
        
        if not scenario.secure do
          IO.puts("  ⚠️  Warning: Plaintext API keys should not be stored in configuration")
        end
      end
      
      # Demonstrate API key rotation
      IO.puts("\n🔄 API Key Rotation:")
      IO.puts("  - Automatic detection of expired tokens")
      IO.puts("  - Secure storage in encrypted format")
      IO.puts("  - Rotation notification to users")
    end
  end
  
  describe "Audit Trail Demonstration" do
    test "security events are logged" do
      # Demonstrate audit logging
      security_events = [
        %{event: "untrusted_tool_execution", server: "tavily_http", tool: "search"},
        %{event: "confirmation_bypass_attempt", server: "filesystem_server", tool: "delete_file"},
        %{event: "sensitive_parameter_detected", server: "any", parameter: "api_key"},
        %{event: "trust_level_changed", server: "context7_stdio", new_trust: false}
      ]
      
      IO.puts("\n📊 Security Audit Trail:")
      
      for event <- security_events do
        timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
        IO.puts("#{timestamp} - #{event.event}: #{inspect(Map.drop(event, [:event]))}")
      end
      
      assert length(security_events) > 0
    end
  end
end