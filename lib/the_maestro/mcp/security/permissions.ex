defmodule TheMaestro.MCP.Security.Permissions do
  @moduledoc """
  Access control and permissions system for MCP tool execution security.
  
  Provides comprehensive permission management for:
  - File system access controls
  - Network access restrictions  
  - System command permissions
  - Environment variable access
  - Resource limitation enforcement
  
  ## Permission Types
  
  - **File System**: Read, write, execute permissions for specific paths
  - **Network**: Outbound/inbound connection restrictions
  - **System**: Command execution and environment variable access
  - **Resource**: CPU, memory, and execution time limits
  
  ## Permission Inheritance
  
  Permissions are evaluated in order of precedence:
  1. User-specific permissions (highest priority)
  2. Server-specific permissions
  3. Tool-specific permissions  
  4. Global default permissions (lowest priority)
  """
  
  require Logger
  
  @type permission_level :: :allow | :deny | :restrict
  @type resource_limit :: %{
    max_cpu_percent: non_neg_integer(),
    max_memory_mb: non_neg_integer(), 
    max_execution_seconds: non_neg_integer(),
    max_file_size_mb: non_neg_integer()
  }
  
  @type t :: %__MODULE__{
    file_system: %{
      read: [String.t()],
      write: [String.t()],
      execute: [String.t()]
    },
    network: %{
      outbound: [String.t()],
      inbound: [String.t()],
      blocked_domains: [String.t()],
      allowed_protocols: [String.t()]
    },
    system: %{
      environment_vars: [String.t()],
      commands: [String.t()],
      blocked_commands: [String.t()]
    },
    resources: resource_limit(),
    user_id: String.t() | nil,
    server_id: String.t() | nil,
    tool_name: String.t() | nil,
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
  
  defstruct [
    file_system: %{read: [], write: [], execute: []},
    network: %{outbound: [], inbound: [], blocked_domains: [], allowed_protocols: ["http", "https"]},
    system: %{environment_vars: [], commands: [], blocked_commands: []},
    resources: %{max_cpu_percent: 50, max_memory_mb: 512, max_execution_seconds: 60, max_file_size_mb: 100},
    user_id: nil,
    server_id: nil, 
    tool_name: nil,
    created_at: nil,
    updated_at: nil
  ]
  
  defmodule PermissionCheck do
    @moduledoc """
    Result of a permission check operation.
    """
    @type t :: %__MODULE__{
      allowed: boolean(),
      permission_type: atom(),
      resource: String.t(),
      reason: String.t(),
      applied_rule: String.t() | nil
    }
    
    defstruct [
      :allowed,
      :permission_type,
      :resource,
      :reason,
      :applied_rule
    ]
  end
  
  @doc """
  Creates a new permission set.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    now = DateTime.utc_now()
    
    %__MODULE__{
      user_id: Keyword.get(opts, :user_id),
      server_id: Keyword.get(opts, :server_id),
      tool_name: Keyword.get(opts, :tool_name),
      created_at: now,
      updated_at: now
    }
    |> merge_permissions(Keyword.get(opts, :permissions, %{}))
  end
  
  @doc """
  Creates default permissions for different security levels.
  """
  @spec default_permissions(atom()) :: t()
  def default_permissions(security_level) do
    case security_level do
      :restricted ->
        %__MODULE__{
          file_system: %{
            read: ["/tmp", "/var/tmp"],
            write: ["/tmp"],
            execute: []
          },
          network: %{
            outbound: ["http://localhost:*"],
            inbound: [],
            blocked_domains: ["*"],
            allowed_protocols: ["http"]
          },
          system: %{
            environment_vars: ["USER", "HOME"],
            commands: [],
            blocked_commands: ["rm", "dd", "mkfs", "fdisk", "sudo", "su"]
          },
          resources: %{
            max_cpu_percent: 25,
            max_memory_mb: 256,
            max_execution_seconds: 30,
            max_file_size_mb: 10
          }
        }
        
      :standard ->
        %__MODULE__{
          file_system: %{
            read: ["/tmp", "/home/#{System.get_env("USER", "user")}", "/opt/app"],
            write: ["/tmp", "/home/#{System.get_env("USER", "user")}/workspace"],
            execute: ["/usr/bin", "/usr/local/bin"]
          },
          network: %{
            outbound: ["https://*.example.com", "http://localhost:*", "https://api.github.com"],
            inbound: [],
            blocked_domains: [],
            allowed_protocols: ["http", "https"]
          },
          system: %{
            environment_vars: ["USER", "HOME", "PATH", "PUBLIC_*"],
            commands: ["ls", "cat", "grep", "find", "curl"],
            blocked_commands: ["rm -rf", "dd", "mkfs", "fdisk", "sudo", "su", "chmod 777"]
          },
          resources: %{
            max_cpu_percent: 50,
            max_memory_mb: 512,
            max_execution_seconds: 60,
            max_file_size_mb: 100
          }
        }
        
      :admin ->
        %__MODULE__{
          file_system: %{
            read: ["*"],
            write: ["/tmp", "/home", "/opt", "/var/log"],
            execute: ["*"]
          },
          network: %{
            outbound: ["*"],
            inbound: ["*"],
            blocked_domains: [],
            allowed_protocols: ["*"]
          },
          system: %{
            environment_vars: ["*"],
            commands: ["*"],
            blocked_commands: []
          },
          resources: %{
            max_cpu_percent: 90,
            max_memory_mb: 4096,
            max_execution_seconds: 300,
            max_file_size_mb: 1024
          }
        }
    end
    |> Map.merge(%{created_at: DateTime.utc_now(), updated_at: DateTime.utc_now()})
  end
  
  @doc """
  Checks file system access permission.
  """
  @spec check_file_access(t(), String.t(), :read | :write | :execute) :: PermissionCheck.t()
  def check_file_access(%__MODULE__{} = permissions, file_path, access_type) do
    allowed_paths = get_in(permissions.file_system, [access_type]) || []
    
    cond do
      # Check for wildcard permission
      "*" in allowed_paths ->
        %PermissionCheck{
          allowed: true,
          permission_type: :file_system,
          resource: file_path,
          reason: "Wildcard permission granted",
          applied_rule: "*"
        }
        
      # Check for path traversal prevention
      path_contains_traversal?(file_path) ->
        %PermissionCheck{
          allowed: false,
          permission_type: :file_system,
          resource: file_path,
          reason: "Path traversal attempt detected",
          applied_rule: "security_policy"
        }
        
      # Check allowed path prefixes
      path_allowed?(file_path, allowed_paths) ->
        matching_path = Enum.find(allowed_paths, &String.starts_with?(file_path, &1))
        %PermissionCheck{
          allowed: true,
          permission_type: :file_system,
          resource: file_path,
          reason: "Path matches allowed prefix",
          applied_rule: matching_path
        }
        
      # Default deny
      true ->
        %PermissionCheck{
          allowed: false,
          permission_type: :file_system,
          resource: file_path,
          reason: "Path not in allowed list",
          applied_rule: "default_deny"
        }
    end
  end
  
  @doc """
  Checks network access permission.
  """
  @spec check_network_access(t(), String.t(), :outbound | :inbound) :: PermissionCheck.t()
  def check_network_access(%__MODULE__{} = permissions, endpoint, direction) do
    allowed_endpoints = get_in(permissions.network, [direction]) || []
    blocked_domains = permissions.network.blocked_domains || []
    
    cond do
      # Check blocked domains first
      domain_blocked?(endpoint, blocked_domains) ->
        %PermissionCheck{
          allowed: false,
          permission_type: :network,
          resource: endpoint,
          reason: "Domain is blocked",
          applied_rule: "blocked_domains"
        }
        
      # Check for wildcard permission
      "*" in allowed_endpoints ->
        %PermissionCheck{
          allowed: true,
          permission_type: :network,
          resource: endpoint,
          reason: "Wildcard network permission granted",
          applied_rule: "*"
        }
        
      # Check protocol restrictions
      not protocol_allowed?(endpoint, permissions.network.allowed_protocols) ->
        %PermissionCheck{
          allowed: false,
          permission_type: :network,
          resource: endpoint,
          reason: "Protocol not allowed",
          applied_rule: "protocol_restriction"
        }
        
      # Check allowed endpoints
      endpoint_allowed?(endpoint, allowed_endpoints) ->
        matching_pattern = Enum.find(allowed_endpoints, &endpoint_matches_pattern?(endpoint, &1))
        %PermissionCheck{
          allowed: true,
          permission_type: :network,
          resource: endpoint,
          reason: "Endpoint matches allowed pattern",
          applied_rule: matching_pattern
        }
        
      # Default deny
      true ->
        %PermissionCheck{
          allowed: false,
          permission_type: :network,
          resource: endpoint,
          reason: "Endpoint not in allowed list",
          applied_rule: "default_deny"
        }
    end
  end
  
  @doc """
  Checks system command execution permission.
  """
  @spec check_command_permission(t(), String.t()) :: PermissionCheck.t()
  def check_command_permission(%__MODULE__{} = permissions, command) do
    allowed_commands = permissions.system.commands || []
    blocked_commands = permissions.system.blocked_commands || []
    
    cond do
      # Check blocked commands first
      command_blocked?(command, blocked_commands) ->
        %PermissionCheck{
          allowed: false,
          permission_type: :system,
          resource: command,
          reason: "Command is explicitly blocked",
          applied_rule: "blocked_commands"
        }
        
      # Check for wildcard permission
      "*" in allowed_commands ->
        %PermissionCheck{
          allowed: true,
          permission_type: :system,
          resource: command,
          reason: "Wildcard command permission granted",
          applied_rule: "*"
        }
        
      # Check allowed commands
      command_allowed?(command, allowed_commands) ->
        matching_command = Enum.find(allowed_commands, &command_matches_pattern?(command, &1))
        %PermissionCheck{
          allowed: true,
          permission_type: :system,
          resource: command,
          reason: "Command matches allowed pattern",
          applied_rule: matching_command
        }
        
      # Default deny
      true ->
        %PermissionCheck{
          allowed: false,
          permission_type: :system,
          resource: command,
          reason: "Command not in allowed list",
          applied_rule: "default_deny"
        }
    end
  end
  
  @doc """
  Checks environment variable access permission.
  """
  @spec check_env_var_permission(t(), String.t()) :: PermissionCheck.t()
  def check_env_var_permission(%__MODULE__{} = permissions, env_var) do
    allowed_vars = permissions.system.environment_vars || []
    
    cond do
      # Check for wildcard permission
      "*" in allowed_vars ->
        %PermissionCheck{
          allowed: true,
          permission_type: :system,
          resource: env_var,
          reason: "Wildcard environment variable access granted",
          applied_rule: "*"
        }
        
      # Check pattern matching (e.g., "PUBLIC_*")
      env_var_allowed?(env_var, allowed_vars) ->
        matching_pattern = Enum.find(allowed_vars, &env_var_matches_pattern?(env_var, &1))
        %PermissionCheck{
          allowed: true,
          permission_type: :system,
          resource: env_var,
          reason: "Environment variable matches allowed pattern",
          applied_rule: matching_pattern
        }
        
      # Default deny
      true ->
        %PermissionCheck{
          allowed: false,
          permission_type: :system,
          resource: env_var,
          reason: "Environment variable not in allowed list",
          applied_rule: "default_deny"
        }
    end
  end
  
  @doc """
  Checks resource usage against limits.
  """
  @spec check_resource_limits(t(), map()) :: [PermissionCheck.t()]
  def check_resource_limits(%__MODULE__{} = permissions, usage) do
    limits = permissions.resources
    
    [
      check_cpu_limit(usage, limits),
      check_memory_limit(usage, limits),
      check_execution_time_limit(usage, limits),
      check_file_size_limit(usage, limits)
    ]
    |> Enum.reject(&is_nil/1)
  end
  
  @doc """
  Merges additional permissions into existing permission set.
  """
  @spec merge_permissions(t(), map()) :: t()
  def merge_permissions(%__MODULE__{} = permissions, additional_perms) do
    now = DateTime.utc_now()
    
    %{permissions | updated_at: now}
    |> merge_file_system_permissions(Map.get(additional_perms, :file_system, %{}))
    |> merge_network_permissions(Map.get(additional_perms, :network, %{}))
    |> merge_system_permissions(Map.get(additional_perms, :system, %{}))
    |> merge_resource_limits(Map.get(additional_perms, :resources, %{}))
  end
  
  @doc """
  Validates permission configuration for consistency.
  """
  @spec validate_permissions(t()) :: {:ok, t()} | {:error, [String.t()]}
  def validate_permissions(%__MODULE__{} = permissions) do
    errors = []
    
    errors = validate_file_system_permissions(permissions.file_system, errors)
    errors = validate_network_permissions(permissions.network, errors)
    errors = validate_system_permissions(permissions.system, errors)
    errors = validate_resource_limits(permissions.resources, errors)
    
    case errors do
      [] -> {:ok, permissions}
      errors -> {:error, errors}
    end
  end
  
  ## Private Functions
  
  defp path_contains_traversal?(path) do
    String.contains?(path, ["../", "..\\", "%2e%2e%2f", "%2e%2e%5c"])
  end
  
  defp path_allowed?(path, allowed_paths) do
    Enum.any?(allowed_paths, fn allowed_path ->
      cond do
        allowed_path == "*" -> true
        String.ends_with?(allowed_path, "*") ->
          prefix = String.trim_trailing(allowed_path, "*")
          String.starts_with?(path, prefix)
        true ->
          String.starts_with?(path, allowed_path)
      end
    end)
  end
  
  defp domain_blocked?(endpoint, blocked_domains) do
    case URI.parse(endpoint) do
      %URI{host: host} when is_binary(host) ->
        Enum.any?(blocked_domains, fn blocked ->
          cond do
            blocked == "*" -> true
            String.starts_with?(blocked, "*.") ->
              domain_suffix = String.trim_leading(blocked, "*.")
              String.ends_with?(host, domain_suffix)
            true ->
              host == blocked
          end
        end)
      _ -> false
    end
  end
  
  defp protocol_allowed?(endpoint, allowed_protocols) do
    case URI.parse(endpoint) do
      %URI{scheme: scheme} when is_binary(scheme) ->
        "*" in allowed_protocols or String.downcase(scheme) in allowed_protocols
      _ -> false
    end
  end
  
  defp endpoint_allowed?(endpoint, allowed_endpoints) do
    Enum.any?(allowed_endpoints, &endpoint_matches_pattern?(endpoint, &1))
  end
  
  defp endpoint_matches_pattern?(endpoint, pattern) do
    cond do
      pattern == "*" -> true
      String.contains?(pattern, "*") ->
        regex_pattern = 
          pattern
          |> Regex.escape()
          |> String.replace("\\*", ".*")
        Regex.match?(~r/^#{regex_pattern}$/, endpoint)
      true -> endpoint == pattern
    end
  end
  
  defp command_blocked?(command, blocked_commands) do
    Enum.any?(blocked_commands, fn blocked ->
      String.contains?(String.downcase(command), String.downcase(blocked))
    end)
  end
  
  defp command_allowed?(command, allowed_commands) do
    Enum.any?(allowed_commands, &command_matches_pattern?(command, &1))
  end
  
  defp command_matches_pattern?(command, pattern) do
    cond do
      pattern == "*" -> true
      String.contains?(pattern, "*") ->
        regex_pattern = 
          pattern
          |> Regex.escape()
          |> String.replace("\\*", ".*")
        Regex.match?(~r/^#{regex_pattern}$/i, command)
      true -> String.downcase(command) == String.downcase(pattern)
    end
  end
  
  defp env_var_allowed?(env_var, allowed_vars) do
    Enum.any?(allowed_vars, &env_var_matches_pattern?(env_var, &1))
  end
  
  defp env_var_matches_pattern?(env_var, pattern) do
    cond do
      pattern == "*" -> true
      String.ends_with?(pattern, "*") ->
        prefix = String.trim_trailing(pattern, "*")
        String.starts_with?(env_var, prefix)
      true -> env_var == pattern
    end
  end
  
  defp check_cpu_limit(usage, limits) do
    cpu_usage = Map.get(usage, :cpu_percent, 0)
    max_cpu = limits.max_cpu_percent
    
    if cpu_usage > max_cpu do
      %PermissionCheck{
        allowed: false,
        permission_type: :resource,
        resource: "cpu_usage",
        reason: "CPU usage #{cpu_usage}% exceeds limit of #{max_cpu}%",
        applied_rule: "resource_limits"
      }
    end
  end
  
  defp check_memory_limit(usage, limits) do
    memory_usage = Map.get(usage, :memory_mb, 0)
    max_memory = limits.max_memory_mb
    
    if memory_usage > max_memory do
      %PermissionCheck{
        allowed: false,
        permission_type: :resource,
        resource: "memory_usage",
        reason: "Memory usage #{memory_usage}MB exceeds limit of #{max_memory}MB",
        applied_rule: "resource_limits"
      }
    end
  end
  
  defp check_execution_time_limit(usage, limits) do
    execution_time = Map.get(usage, :execution_seconds, 0)
    max_time = limits.max_execution_seconds
    
    if execution_time > max_time do
      %PermissionCheck{
        allowed: false,
        permission_type: :resource,
        resource: "execution_time",
        reason: "Execution time #{execution_time}s exceeds limit of #{max_time}s",
        applied_rule: "resource_limits"
      }
    end
  end
  
  defp check_file_size_limit(usage, limits) do
    file_size = Map.get(usage, :file_size_mb, 0)
    max_size = limits.max_file_size_mb
    
    if file_size > max_size do
      %PermissionCheck{
        allowed: false,
        permission_type: :resource,
        resource: "file_size",
        reason: "File size #{file_size}MB exceeds limit of #{max_size}MB",
        applied_rule: "resource_limits"
      }
    end
  end
  
  defp merge_file_system_permissions(permissions, additional) do
    current_fs = permissions.file_system
    new_fs = %{
      read: merge_permission_lists(current_fs.read, Map.get(additional, :read, [])),
      write: merge_permission_lists(current_fs.write, Map.get(additional, :write, [])),
      execute: merge_permission_lists(current_fs.execute, Map.get(additional, :execute, []))
    }
    %{permissions | file_system: new_fs}
  end
  
  defp merge_network_permissions(permissions, additional) do
    current_net = permissions.network
    new_net = %{
      outbound: merge_permission_lists(current_net.outbound, Map.get(additional, :outbound, [])),
      inbound: merge_permission_lists(current_net.inbound, Map.get(additional, :inbound, [])),
      blocked_domains: merge_permission_lists(current_net.blocked_domains, Map.get(additional, :blocked_domains, [])),
      allowed_protocols: merge_permission_lists(current_net.allowed_protocols, Map.get(additional, :allowed_protocols, []))
    }
    %{permissions | network: new_net}
  end
  
  defp merge_system_permissions(permissions, additional) do
    current_sys = permissions.system
    new_sys = %{
      environment_vars: merge_permission_lists(current_sys.environment_vars, Map.get(additional, :environment_vars, [])),
      commands: merge_permission_lists(current_sys.commands, Map.get(additional, :commands, [])),
      blocked_commands: merge_permission_lists(current_sys.blocked_commands, Map.get(additional, :blocked_commands, []))
    }
    %{permissions | system: new_sys}
  end
  
  defp merge_resource_limits(permissions, additional) do
    current_resources = permissions.resources
    new_resources = Map.merge(current_resources, additional)
    %{permissions | resources: new_resources}
  end
  
  defp merge_permission_lists(current, additional) do
    (current ++ additional)
    |> Enum.uniq()
    |> Enum.sort()
  end
  
  defp validate_file_system_permissions(fs_perms, errors) do
    errors = if not is_list(fs_perms.read), do: ["file_system.read must be a list" | errors], else: errors
    errors = if not is_list(fs_perms.write), do: ["file_system.write must be a list" | errors], else: errors
    errors = if not is_list(fs_perms.execute), do: ["file_system.execute must be a list" | errors], else: errors
    errors
  end
  
  defp validate_network_permissions(net_perms, errors) do
    errors = if not is_list(net_perms.outbound), do: ["network.outbound must be a list" | errors], else: errors  
    errors = if not is_list(net_perms.inbound), do: ["network.inbound must be a list" | errors], else: errors
    errors = if not is_list(net_perms.blocked_domains), do: ["network.blocked_domains must be a list" | errors], else: errors
    errors = if not is_list(net_perms.allowed_protocols), do: ["network.allowed_protocols must be a list" | errors], else: errors
    errors
  end
  
  defp validate_system_permissions(sys_perms, errors) do
    errors = if not is_list(sys_perms.environment_vars), do: ["system.environment_vars must be a list" | errors], else: errors
    errors = if not is_list(sys_perms.commands), do: ["system.commands must be a list" | errors], else: errors
    errors = if not is_list(sys_perms.blocked_commands), do: ["system.blocked_commands must be a list" | errors], else: errors
    errors
  end
  
  defp validate_resource_limits(resources, errors) do
    errors = if not is_integer(resources.max_cpu_percent), do: ["resources.max_cpu_percent must be an integer" | errors], else: errors
    errors = if not is_integer(resources.max_memory_mb), do: ["resources.max_memory_mb must be an integer" | errors], else: errors
    errors = if not is_integer(resources.max_execution_seconds), do: ["resources.max_execution_seconds must be an integer" | errors], else: errors
    errors = if not is_integer(resources.max_file_size_mb), do: ["resources.max_file_size_mb must be an integer" | errors], else: errors
    errors
  end
end