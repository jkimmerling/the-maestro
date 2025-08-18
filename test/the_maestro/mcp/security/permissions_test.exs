defmodule TheMaestro.MCP.Security.PermissionsTest do
  use ExUnit.Case, async: true
  
  alias TheMaestro.MCP.Security.Permissions
  alias TheMaestro.MCP.Security.Permissions.PermissionCheck
  
  describe "new/1" do
    test "creates new permission set with defaults" do
      permissions = Permissions.new()
      
      assert is_nil(permissions.user_id)
      assert is_nil(permissions.server_id)
      assert is_nil(permissions.tool_name)
      assert permissions.file_system.read == []
      assert permissions.network.allowed_protocols == ["http", "https"]
      assert permissions.resources.max_cpu_percent == 50
    end
    
    test "creates permission set with custom options" do
      opts = [
        user_id: "test_user",
        server_id: "test_server",
        permissions: %{
          file_system: %{read: ["/tmp"]},
          resources: %{max_cpu_percent: 80}
        }
      ]
      
      permissions = Permissions.new(opts)
      
      assert permissions.user_id == "test_user"
      assert permissions.server_id == "test_server"
      assert "/tmp" in permissions.file_system.read
      assert permissions.resources.max_cpu_percent == 80
    end
  end
  
  describe "default_permissions/1" do
    test "creates restricted permissions" do
      permissions = Permissions.default_permissions(:restricted)
      
      assert permissions.file_system.read == ["/tmp", "/var/tmp"]
      assert permissions.file_system.write == ["/tmp"]
      assert permissions.file_system.execute == []
      assert permissions.resources.max_cpu_percent == 25
      assert "rm" in permissions.system.blocked_commands
    end
    
    test "creates standard permissions" do
      permissions = Permissions.default_permissions(:standard)
      
      assert "/tmp" in permissions.file_system.read
      assert length(permissions.network.outbound) > 1
      assert permissions.resources.max_cpu_percent == 50
      assert "ls" in permissions.system.commands
    end
    
    test "creates admin permissions" do
      permissions = Permissions.default_permissions(:admin)
      
      assert permissions.file_system.read == ["*"]
      assert permissions.network.outbound == ["*"]
      assert permissions.system.commands == ["*"]
      assert permissions.resources.max_cpu_percent == 90
    end
  end
  
  describe "check_file_access/3" do
    setup do
      permissions = Permissions.new(permissions: %{
        file_system: %{
          read: ["/allowed/path", "/tmp/*"],
          write: ["/tmp", "/home/user/workspace"],
          execute: ["/usr/bin"]
        }
      })
      
      {:ok, permissions: permissions}
    end
    
    test "allows access to explicitly allowed paths", %{permissions: permissions} do
      result = Permissions.check_file_access(permissions, "/allowed/path/file.txt", :read)
      
      assert result.allowed == true
      assert result.permission_type == :file_system
      assert result.applied_rule == "/allowed/path"
    end
    
    test "allows access to wildcard paths", %{permissions: permissions} do
      result = Permissions.check_file_access(permissions, "/tmp/subdir/file.txt", :read)
      
      assert result.allowed == true
      assert result.applied_rule == "/tmp/*"
    end
    
    test "denies access to path traversal attempts", %{permissions: permissions} do
      result = Permissions.check_file_access(permissions, "/allowed/../etc/passwd", :read)
      
      assert result.allowed == false
      assert result.reason == "Path traversal attempt detected"
    end
    
    test "denies access to non-allowed paths", %{permissions: permissions} do
      result = Permissions.check_file_access(permissions, "/etc/passwd", :read)
      
      assert result.allowed == false
      assert result.reason == "Path not in allowed list"
    end
    
    test "handles wildcard permission", %{permissions: permissions} do
      admin_permissions = Permissions.default_permissions(:admin)
      result = Permissions.check_file_access(admin_permissions, "/etc/passwd", :read)
      
      assert result.allowed == true
      assert result.applied_rule == "*"
    end
  end
  
  describe "check_network_access/3" do
    setup do
      permissions = Permissions.new(permissions: %{
        network: %{
          outbound: ["https://api.example.com", "http://localhost:*"],
          blocked_domains: ["malicious.com", "*.dangerous.net"],
          allowed_protocols: ["http", "https"]
        }
      })
      
      {:ok, permissions: permissions}
    end
    
    test "allows access to whitelisted endpoints", %{permissions: permissions} do
      result = Permissions.check_network_access(permissions, "https://api.example.com/data", :outbound)
      
      assert result.allowed == true
      assert result.applied_rule == "https://api.example.com"
    end
    
    test "allows access to wildcard patterns", %{permissions: permissions} do
      result = Permissions.check_network_access(permissions, "http://localhost:3000/api", :outbound)
      
      assert result.allowed == true
      assert result.applied_rule == "http://localhost:*"
    end
    
    test "blocks access to blacklisted domains", %{permissions: permissions} do
      result = Permissions.check_network_access(permissions, "https://malicious.com/api", :outbound)
      
      assert result.allowed == false
      assert result.reason == "Domain is blocked"
    end
    
    test "blocks access to blocked wildcard domains", %{permissions: permissions} do
      result = Permissions.check_network_access(permissions, "https://evil.dangerous.net", :outbound)
      
      assert result.allowed == false
      assert result.reason == "Domain is blocked"
    end
    
    test "blocks disallowed protocols", %{permissions: permissions} do
      result = Permissions.check_network_access(permissions, "ftp://example.com/file", :outbound)
      
      assert result.allowed == false
      assert result.reason == "Protocol not allowed"
    end
    
    test "denies non-whitelisted endpoints", %{permissions: permissions} do
      result = Permissions.check_network_access(permissions, "https://random.com", :outbound)
      
      assert result.allowed == false
      assert result.reason == "Endpoint not in allowed list"
    end
  end
  
  describe "check_command_permission/2" do
    setup do
      permissions = Permissions.new(permissions: %{
        system: %{
          commands: ["ls", "cat", "grep*"],
          blocked_commands: ["rm -rf", "dd", "sudo"]
        }
      })
      
      {:ok, permissions: permissions}
    end
    
    test "allows whitelisted commands", %{permissions: permissions} do
      result = Permissions.check_command_permission(permissions, "ls -la")
      
      assert result.allowed == true
      assert result.applied_rule == "ls"
    end
    
    test "allows wildcard command patterns", %{permissions: permissions} do
      result = Permissions.check_command_permission(permissions, "grep -r pattern")
      
      assert result.allowed == true
      assert result.applied_rule == "grep*"
    end
    
    test "blocks explicitly blocked commands", %{permissions: permissions} do
      result = Permissions.check_command_permission(permissions, "rm -rf /")
      
      assert result.allowed == false
      assert result.reason == "Command is explicitly blocked"
    end
    
    test "blocks non-whitelisted commands", %{permissions: permissions} do
      result = Permissions.check_command_permission(permissions, "unknown_command")
      
      assert result.allowed == false
      assert result.reason == "Command not in allowed list"
    end
    
    test "handles wildcard permission for admin", %{permissions: _permissions} do
      admin_permissions = Permissions.default_permissions(:admin)
      result = Permissions.check_command_permission(admin_permissions, "any_command")
      
      assert result.allowed == true
      assert result.applied_rule == "*"
    end
  end
  
  describe "check_env_var_permission/2" do
    setup do
      permissions = Permissions.new(permissions: %{
        system: %{
          environment_vars: ["USER", "HOME", "PUBLIC_*", "API_*"]
        }
      })
      
      {:ok, permissions: permissions}
    end
    
    test "allows explicitly allowed environment variables", %{permissions: permissions} do
      result = Permissions.check_env_var_permission(permissions, "USER")
      
      assert result.allowed == true
      assert result.applied_rule == "USER"
    end
    
    test "allows pattern-matched environment variables", %{permissions: permissions} do
      result = Permissions.check_env_var_permission(permissions, "PUBLIC_KEY")
      
      assert result.allowed == true
      assert result.applied_rule == "PUBLIC_*"
    end
    
    test "allows API pattern variables", %{permissions: permissions} do
      result = Permissions.check_env_var_permission(permissions, "API_SECRET")
      
      assert result.allowed == true
      assert result.applied_rule == "API_*"
    end
    
    test "denies non-allowed environment variables", %{permissions: permissions} do
      result = Permissions.check_env_var_permission(permissions, "SECRET_KEY")
      
      assert result.allowed == false
      assert result.reason == "Environment variable not in allowed list"
    end
  end
  
  describe "check_resource_limits/2" do
    setup do
      permissions = Permissions.new(permissions: %{
        resources: %{
          max_cpu_percent: 50,
          max_memory_mb: 512,
          max_execution_seconds: 60,
          max_file_size_mb: 100
        }
      })
      
      {:ok, permissions: permissions}
    end
    
    test "returns no violations for usage within limits", %{permissions: permissions} do
      usage = %{
        cpu_percent: 30,
        memory_mb: 256,
        execution_seconds: 45,
        file_size_mb: 50
      }
      
      violations = Permissions.check_resource_limits(permissions, usage)
      
      assert length(violations) == 0
    end
    
    test "detects CPU usage violation", %{permissions: permissions} do
      usage = %{cpu_percent: 75}
      
      violations = Permissions.check_resource_limits(permissions, usage)
      
      assert length(violations) == 1
      violation = hd(violations)
      assert violation.allowed == false
      assert violation.resource == "cpu_usage"
      assert String.contains?(violation.reason, "exceeds limit")
    end
    
    test "detects memory usage violation", %{permissions: permissions} do
      usage = %{memory_mb: 1024}
      
      violations = Permissions.check_resource_limits(permissions, usage)
      
      assert length(violations) == 1
      violation = hd(violations)
      assert violation.resource == "memory_usage"
    end
    
    test "detects multiple resource violations", %{permissions: permissions} do
      usage = %{
        cpu_percent: 75,
        memory_mb: 1024,
        execution_seconds: 120
      }
      
      violations = Permissions.check_resource_limits(permissions, usage)
      
      assert length(violations) == 3
      resources = violations |> Enum.map(& &1.resource) |> Enum.sort()
      assert resources == ["cpu_usage", "execution_time", "memory_usage"]
    end
  end
  
  describe "merge_permissions/2" do
    test "merges file system permissions" do
      base = Permissions.new(permissions: %{
        file_system: %{read: ["/tmp"], write: ["/tmp"]}
      })
      
      additional = %{
        file_system: %{read: ["/home"], execute: ["/usr/bin"]}
      }
      
      merged = Permissions.merge_permissions(base, additional)
      
      assert "/tmp" in merged.file_system.read
      assert "/home" in merged.file_system.read
      assert "/tmp" in merged.file_system.write
      assert "/usr/bin" in merged.file_system.execute
    end
    
    test "merges network permissions" do
      base = Permissions.new(permissions: %{
        network: %{outbound: ["http://localhost:*"]}
      })
      
      additional = %{
        network: %{outbound: ["https://api.example.com"], inbound: ["*:8080"]}
      }
      
      merged = Permissions.merge_permissions(base, additional)
      
      assert "http://localhost:*" in merged.network.outbound
      assert "https://api.example.com" in merged.network.outbound
      assert "*:8080" in merged.network.inbound
    end
    
    test "merges resource limits" do
      base = Permissions.new(permissions: %{
        resources: %{max_cpu_percent: 30, max_memory_mb: 256}
      })
      
      additional = %{
        resources: %{max_cpu_percent: 80, max_file_size_mb: 200}
      }
      
      merged = Permissions.merge_permissions(base, additional)
      
      assert merged.resources.max_cpu_percent == 80  # Overridden
      assert merged.resources.max_memory_mb == 256   # Preserved
      assert merged.resources.max_file_size_mb == 200  # Added
    end
  end
  
  describe "validate_permissions/1" do
    test "validates correct permission structure" do
      permissions = Permissions.new(permissions: %{
        file_system: %{read: ["/tmp"], write: ["/tmp"], execute: []},
        network: %{outbound: [], inbound: [], blocked_domains: [], allowed_protocols: ["http"]},
        system: %{environment_vars: [], commands: [], blocked_commands: []},
        resources: %{max_cpu_percent: 50, max_memory_mb: 512, max_execution_seconds: 60, max_file_size_mb: 100}
      })
      
      assert {:ok, ^permissions} = Permissions.validate_permissions(permissions)
    end
    
    test "reports validation errors for invalid structure" do
      permissions = %Permissions{
        file_system: %{read: "invalid", write: [], execute: []},
        network: %{outbound: "invalid", inbound: [], blocked_domains: [], allowed_protocols: []},
        system: %{environment_vars: [], commands: [], blocked_commands: []},
        resources: %{max_cpu_percent: "invalid", max_memory_mb: 512, max_execution_seconds: 60, max_file_size_mb: 100}
      }
      
      assert {:error, errors} = Permissions.validate_permissions(permissions)
      
      assert length(errors) >= 3
      assert Enum.any?(errors, &String.contains?(&1, "file_system.read must be a list"))
      assert Enum.any?(errors, &String.contains?(&1, "network.outbound must be a list"))
      assert Enum.any?(errors, &String.contains?(&1, "resources.max_cpu_percent must be an integer"))
    end
  end
end