# MCP Security & Confirmation Framework Tutorial

## Overview

This tutorial covers the comprehensive MCP (Model Context Protocol) Security & Confirmation Framework implemented in Epic 6, Story 6.4. The framework provides robust security for MCP tool execution with multi-level trust management, risk assessment, confirmation flows, and audit logging.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core Security Components](#core-security-components)
3. [Quick Start Guide](#quick-start-guide)
4. [Trust Management](#trust-management)
5. [Policy Management](#policy-management)
6. [Access Control & Permissions](#access-control--permissions)
7. [Anomaly Detection](#anomaly-detection)
8. [Risk Assessment](#risk-assessment)
9. [Parameter Sanitization](#parameter-sanitization)
10. [Confirmation Flows](#confirmation-flows)
11. [UI/TUI Integration](#ui-tui-integration)
12. [Audit Logging](#audit-logging)
13. [Advanced Configuration](#advanced-configuration)
14. [Testing](#testing)
15. [Troubleshooting](#troubleshooting)

## Architecture Overview

The MCP Security Framework follows a layered approach to secure tool execution:

```
┌─────────────────────────────────────────────────────────────┐
│                    SecureExecutor                           │
│  (Main integration point - wraps all security features)    │
├─────────────────────────────────────────────────────────────┤
│  Parameter      │  Risk          │  Trust         │ Audit   │
│  Sanitizer      │  Assessor      │  Manager       │ Logger  │
├─────────────────────────────────────────────────────────────┤
│               Confirmation Engine                           │
│         (Orchestrates security decision flow)              │
├─────────────────────────────────────────────────────────────┤
│          UI Components    │    TUI Components               │
│     (Web confirmation)    │  (Terminal confirmation)       │
└─────────────────────────────────────────────────────────────┘
```

### Security Flow

1. **Parameter Sanitization**: Clean and validate input parameters
2. **Risk Assessment**: Evaluate security risks of the operation
3. **Trust Evaluation**: Check server and tool trust levels
4. **Confirmation Flow**: Present user confirmation if required
5. **Execution**: Execute tool if authorized
6. **Audit Logging**: Log security events and decisions

## Core Security Components

### 1. SecureExecutor

The main entry point for secure MCP tool execution:

```elixir
# Basic usage
context = %{
  server_id: "filesystem_server",
  user_id: "user123",
  session_id: "sess_456",
  interface: :web
}

{:ok, result} = TheMaestro.MCP.Security.SecureExecutor.execute_secure(
  "read_file", 
  %{"path" => "/tmp/file.txt"}, 
  context
)
```

### 2. PolicyEngine

Centralized security policy management and enforcement:

```elixir
# Get effective security policy for context
context = %{user_id: "user123", server_id: "filesystem_server"}
{:ok, effective_policy} = TheMaestro.MCP.Security.PolicyEngine.get_effective_policy(context)

# Update security policies
policy_data = %{
  name: "User Security Policy",
  level: :user,
  settings: %{require_confirmation_threshold: :low},
  conditions: %{user_id: "user123"}
}
:ok = TheMaestro.MCP.Security.PolicyEngine.update_policy("user_policy", policy_data)

# Activate emergency mode
:ok = TheMaestro.MCP.Security.PolicyEngine.activate_emergency_mode("Security incident", "admin")
```

### 3. Permissions

Comprehensive access control and permissions system:

```elixir
# Create permissions with specific access rules
permissions = TheMaestro.MCP.Security.Permissions.new([
  user_id: "user123",
  permissions: %{
    file_system: %{
      read: ["/tmp", "/home/user"],
      write: ["/tmp"],
      execute: ["/usr/bin"]
    },
    network: %{
      outbound: ["https://api.example.com", "http://localhost:*"],
      blocked_domains: ["malicious.com"]
    }
  }
])

# Check file access permission
result = TheMaestro.MCP.Security.Permissions.check_file_access(
  permissions, "/tmp/file.txt", :read
)
# Returns %PermissionCheck{allowed: true, reason: "Path matches allowed prefix"}

# Check network access permission
result = TheMaestro.MCP.Security.Permissions.check_network_access(
  permissions, "https://api.example.com/data", :outbound
)
# Returns %PermissionCheck{allowed: true, applied_rule: "https://api.example.com"}
```

### 4. AnomalyDetector

Real-time suspicious activity detection:

```elixir
# Record security events for analysis
event = %{
  event_type: :tool_execution,
  user_id: "user123",
  tool_name: "read_file",
  parameters: %{path: "../../../etc/passwd"},  # Suspicious path traversal
  timestamp: DateTime.utc_now()
}
:ok = TheMaestro.MCP.Security.AnomalyDetector.record_event(event)

# Get active anomalies
anomalies = TheMaestro.MCP.Security.AnomalyDetector.get_active_anomalies()
# Returns list of detected anomalies with severity levels

# Update anomaly status during investigation
:ok = TheMaestro.MCP.Security.AnomalyDetector.update_anomaly_status(
  anomaly_id, :investigating, "security_analyst"
)

# Configure detection thresholds
:ok = TheMaestro.MCP.Security.AnomalyDetector.configure_thresholds(%{
  max_tools_per_minute: 15,
  injection_pattern_threshold: 0.9
})
```

### 5. TrustManager

Manages server and tool trust relationships:

```elixir
# Grant server trust
TheMaestro.MCP.Security.TrustManager.grant_server_trust(
  "filesystem_server", 
  :trusted, 
  "user123"
)

# Whitelist specific tool
TheMaestro.MCP.Security.TrustManager.whitelist_tool(
  "filesystem_server", 
  "read_file", 
  "user123"
)
```

### 6. ParameterSanitizer

Cleans and validates tool parameters:

```elixir
# Sanitize parameters
{:ok, sanitized_params, warnings} = 
  TheMaestro.MCP.Security.ParameterSanitizer.sanitize_parameters(
    %{"path" => "../../../etc/passwd"},  # Dangerous path
    "read_file"
  )
# Returns sanitized path and warnings about path traversal
```

### 7. RiskAssessor

Evaluates security risks:

```elixir
# Assess risk
risk_assessment = TheMaestro.MCP.Security.RiskAssessor.assess_risk(
  "execute_command",
  %{"command" => "rm -rf /"},
  %{server_id: "shell_server"}
)
# Returns %RiskAssessment{risk_level: :high, reasons: [...]}
```

## Quick Start Guide

### Step 1: Basic Secure Execution

Replace direct MCP tool calls with secure execution:

```elixir
# Old way (insecure)
result = TheMaestro.MCP.Tools.Executor.execute(tool_name, params, context)

# New way (secure)
result = TheMaestro.MCP.Security.SecureExecutor.execute_secure(tool_name, params, context)
```

### Step 2: Configure Trust for Development

For development, set up basic trust:

```elixir
# Trust your development servers
TrustManager.grant_server_trust("local_filesystem", :trusted, "dev_user")
TrustManager.grant_server_trust("local_shell", :sandboxed, "dev_user")

# Whitelist safe tools
TrustManager.whitelist_tool("local_filesystem", "read_file", "dev_user")
TrustManager.whitelist_tool("local_filesystem", "list_directory", "dev_user")
```

### Step 3: Handle Results

```elixir
case SecureExecutor.execute_secure(tool_name, params, context) do
  {:ok, %SecureExecutionResult{
    execution_result: result,
    security_decision: :allowed,
    risk_level: risk_level,
    confirmation_required: confirmed?,
    sanitization_warnings: warnings
  }} ->
    # Tool executed successfully
    handle_success(result, warnings)
    
  {:error, %SecureExecutionError{
    type: :security_denied,
    security_reason: reason,
    risk_level: risk_level
  }} ->
    # Security policy blocked execution
    handle_security_denial(reason, risk_level)
    
  {:error, %SecureExecutionError{
    type: :sanitization_blocked,
    security_reason: reason
  }} ->
    # Parameter sanitization blocked execution
    handle_sanitization_error(reason)
end
```

## Trust Management

### Trust Levels

The framework supports three server trust levels:

1. **`:trusted`** - Server is fully trusted, minimal confirmation required
2. **`:untrusted`** - Server requires confirmation for all operations (default)
3. **`:sandboxed`** - Server has restricted access, safe operations allowed

### Tool-Level Trust

Individual tools can have specific trust settings:

- **`:always_allow`** - Never require confirmation for this tool
- **`:confirm_once`** - Require confirmation once per session
- **`:confirm_always`** - Always require confirmation
- **`:blocked`** - Never allow this tool to execute

### Managing Trust

```elixir
# Server trust management
TrustManager.grant_server_trust("my_server", :trusted, "user123")
TrustManager.revoke_server_trust("my_server", "user123")

# Tool trust management
TrustManager.whitelist_tool("my_server", "safe_tool", "user123")
TrustManager.blacklist_tool("my_server", "dangerous_tool", "user123")

# Check trust status
trust_level = TrustManager.server_trust_level("my_server")
requires_confirmation? = TrustManager.requires_confirmation?(tool, params, context)
```

## Policy Management

The Policy Engine provides centralized security policy management with hierarchical precedence and dynamic evaluation.

### Policy Types and Precedence

Policies are evaluated in order of precedence (highest to lowest):
1. **Emergency policies** - Active during security incidents
2. **User-specific policies** - Individual user overrides  
3. **Tool-specific policies** - Tool-level security rules
4. **Server-specific policies** - Server-level configurations
5. **Time-based policies** - Scheduled policy changes
6. **Global default policies** - System-wide defaults

### Creating and Managing Policies

```elixir
# Start the policy engine
{:ok, _pid} = TheMaestro.MCP.Security.PolicyEngine.start_link([])

# Create user-specific policy
user_policy = %{
  name: "Power User Policy",
  level: :user,
  settings: %{
    require_confirmation_threshold: :high,
    max_concurrent_executions: 15,
    auto_block_high_risk: false
  },
  conditions: %{
    user_id: "power_user_123",
    user_roles: ["developer", "admin"]
  },
  priority: 90
}

PolicyEngine.update_policy("power_user_policy", user_policy)

# Create server-specific policy
server_policy = %{
  name: "Internal Tools Policy",
  level: :server,
  settings: %{
    require_confirmation_threshold: :low,
    trusted_by_default: true
  },
  conditions: %{
    server_id: "internal_tools"
  },
  priority: 50
}

PolicyEngine.update_policy("internal_tools_policy", server_policy)

# Create time-based policy (work hours only)
work_hours_policy = %{
  name: "Work Hours Relaxed Policy",
  level: :time_based,
  settings: %{
    require_confirmation_threshold: :medium
  },
  conditions: %{
    time_range: %{start_hour: 9, end_hour: 17}
  },
  priority: 30
}

PolicyEngine.update_policy("work_hours", work_hours_policy)
```

### Emergency Mode Management

```elixir
# Activate emergency lockdown
PolicyEngine.activate_emergency_mode("Potential security breach detected", "security_team")

# Check if emergency mode is active
emergency_active = PolicyEngine.emergency_mode_active?()

# Deactivate emergency mode
PolicyEngine.deactivate_emergency_mode("security_team")
```

### Policy Evaluation

```elixir
# Get effective policy for a specific context
context = %{
  user_id: "power_user_123",
  server_id: "internal_tools", 
  tool_name: "read_file",
  session_id: "sess_456",
  user_roles: ["developer", "admin"]
}

{:ok, effective_policy} = PolicyEngine.get_effective_policy(context)

# The effective policy merges all applicable policies based on precedence
# effective_policy contains:
# %{
#   require_confirmation_threshold: :high,  # From user policy (highest precedence)
#   max_concurrent_executions: 15,          # From user policy
#   trusted_by_default: true,               # From server policy
#   evaluation_timestamp: ~U[...],
#   evaluated_for: %{user_id: "power_user_123", ...}
# }
```

## Access Control & Permissions

The Permissions system provides fine-grained access controls for files, network, system commands, and resource usage.

### Permission Levels

The system supports three predefined security levels:

- **`:restricted`** - Minimal permissions, limited to safe operations
- **`:standard`** - Balanced permissions for typical users  
- **`:admin`** - Full access with minimal restrictions

### Creating Custom Permissions

```elixir
# Create custom permissions for a development environment
dev_permissions = Permissions.new([
  user_id: "developer_123",
  server_id: "dev_server",
  permissions: %{
    file_system: %{
      read: ["/home/developer", "/opt/project", "/tmp"],
      write: ["/home/developer/workspace", "/tmp", "/var/log/app"],
      execute: ["/usr/bin", "/usr/local/bin", "/home/developer/.local/bin"]
    },
    network: %{
      outbound: [
        "https://github.com",
        "https://api.github.com", 
        "https://*.npmjs.org",
        "http://localhost:*",
        "https://registry-1.docker.io"
      ],
      blocked_domains: ["malicious.com", "*.phishing.net"],
      allowed_protocols: ["http", "https", "ssh"]
    },
    system: %{
      environment_vars: ["HOME", "PATH", "USER", "LANG", "NODE_*", "NPM_*"],
      commands: ["git", "npm", "node", "docker", "curl", "wget"],
      blocked_commands: ["rm -rf", "dd", "mkfs", "fdisk"]
    },
    resources: %{
      max_cpu_percent: 75,
      max_memory_mb: 2048, 
      max_execution_seconds: 300,
      max_file_size_mb: 500
    }
  }
])

# Validate the permission configuration
{:ok, validated_permissions} = Permissions.validate_permissions(dev_permissions)
```

### Permission Checking Examples

```elixir
# Check file access permissions
file_check = Permissions.check_file_access(dev_permissions, "/home/developer/project.js", :read)
# Returns: %PermissionCheck{allowed: true, applied_rule: "/home/developer"}

path_traversal_check = Permissions.check_file_access(dev_permissions, "../../../etc/passwd", :read)  
# Returns: %PermissionCheck{allowed: false, reason: "Path traversal attempt detected"}

# Check network access permissions
api_check = Permissions.check_network_access(dev_permissions, "https://api.github.com/repos", :outbound)
# Returns: %PermissionCheck{allowed: true, applied_rule: "https://api.github.com"}

blocked_check = Permissions.check_network_access(dev_permissions, "https://malicious.com", :outbound)
# Returns: %PermissionCheck{allowed: false, reason: "Domain is blocked"}

# Check command permissions
git_check = Permissions.check_command_permission(dev_permissions, "git clone https://github.com/...")
# Returns: %PermissionCheck{allowed: true, applied_rule: "git"}

dangerous_check = Permissions.check_command_permission(dev_permissions, "rm -rf /")
# Returns: %PermissionCheck{allowed: false, reason: "Command is explicitly blocked"}

# Check resource limits
resource_usage = %{
  cpu_percent: 85,          # Exceeds 75% limit
  memory_mb: 1024,          # Within 2048MB limit  
  execution_seconds: 45,    # Within 300s limit
  file_size_mb: 50          # Within 500MB limit
}

violations = Permissions.check_resource_limits(dev_permissions, resource_usage)
# Returns: [%PermissionCheck{allowed: false, resource: "cpu_usage", reason: "CPU usage 85% exceeds limit of 75%"}]
```

### Merging Permissions

```elixir
# Start with base permissions
base_permissions = Permissions.default_permissions(:standard)

# Add project-specific permissions
project_permissions = %{
  file_system: %{
    read: ["/opt/special_project"], 
    execute: ["/opt/special_project/bin"]
  },
  network: %{
    outbound: ["https://special-api.company.com"]
  }
}

# Merge permissions (base + additional)
merged_permissions = Permissions.merge_permissions(base_permissions, project_permissions)

# The merged permissions will contain both base and additional permissions
# with lists combined and duplicates removed
```

## Anomaly Detection

The Anomaly Detection system provides real-time monitoring for suspicious patterns and behaviors.

### Anomaly Types Detected

- **Usage Patterns**: Excessive tool usage, unusual tool combinations
- **Parameter Patterns**: Injection attempts, path traversal, malicious payloads
- **Temporal Patterns**: Off-hours access, burst activity
- **Access Patterns**: Sensitive file access, suspicious network requests
- **Resource Patterns**: Excessive CPU/memory usage, resource exhaustion
- **Behavioral Patterns**: Deviation from user's normal behavior

### Setting Up Anomaly Detection

```elixir
# Start the anomaly detector
{:ok, _pid} = TheMaestro.MCP.Security.AnomalyDetector.start_link([])

# Configure detection thresholds
custom_thresholds = %{
  max_tools_per_minute: 15,              # Allow up to 15 tool uses per minute
  max_failed_confirmations_per_hour: 5,   # Alert after 5 failed confirmations
  injection_pattern_threshold: 0.8,       # Threshold for injection detection
  burst_activity_threshold: 3.0,          # 3x normal activity triggers alert
  off_hours_score_threshold: 0.7,         # Off-hours activity threshold
  user_behavior_deviation_threshold: 2.0  # 2 standard deviations from baseline
}

AnomalyDetector.configure_thresholds(custom_thresholds)
```

### Recording and Analyzing Events

```elixir
# Security events are automatically recorded by the SecureExecutor
# But you can also record custom events

custom_event = %{
  event_type: :custom_security_event,
  user_id: "user123",
  server_id: "api_server",
  tool_name: "sensitive_operation",
  parameters: %{action: "data_export", volume: "large"},
  resource_usage: %{cpu_percent: 45, memory_mb: 512},
  timestamp: DateTime.utc_now()
}

AnomalyDetector.record_event(custom_event)
```

### Managing Detected Anomalies

```elixir
# Get all active anomalies
all_anomalies = AnomalyDetector.get_active_anomalies()

# Filter anomalies by criteria
high_severity = AnomalyDetector.get_active_anomalies(severity: :high)
user_anomalies = AnomalyDetector.get_active_anomalies(user_id: "user123")
injection_attempts = AnomalyDetector.get_active_anomalies(type: :parameter_pattern)

# Update anomaly status during investigation
if length(high_severity) > 0 do
  anomaly = hd(high_severity)
  
  # Mark as under investigation
  AnomalyDetector.update_anomaly_status(anomaly.id, :investigating, "security_analyst")
  
  # After investigation, mark as resolved or false positive
  AnomalyDetector.update_anomaly_status(anomaly.id, :false_positive, "security_analyst")
end
```

### Analyzing User Baselines

```elixir
# Get user behavior baseline (automatically built over time)
{:ok, baseline} = AnomalyDetector.get_user_baseline("user123")

# Baseline contains:
# %{
#   common_tools: ["read_file", "list_directory", "search"],
#   avg_events_per_minute: 2.5,
#   avg_cpu_usage: 25.0,
#   avg_memory_usage: 128.0,
#   normal_hours_activity: 0.85  # 85% of activity during normal hours
# }
```

### Real-time Context Analysis

```elixir
# Analyze current context for related anomalies
context = %{
  user_id: "user123",
  server_id: "filesystem_server",
  tool_name: "read_file"
}

{:ok, related_anomalies} = AnomalyDetector.analyze_context(context)

# Returns anomalies related to this specific context
if length(related_anomalies) > 0 do
  Logger.warn("Active anomalies detected for current context", 
    count: length(related_anomalies),
    severity_levels: Enum.map(related_anomalies, & &1.severity)
  )
end
```

### Detection Statistics and Monitoring

```elixir
# Get detection statistics
stats = AnomalyDetector.get_statistics()

# Returns:
# %{
#   events_processed: 1543,
#   anomalies_detected: 23,
#   false_positives: 5,
#   confirmed_threats: 3,
#   active_anomalies: 2,
#   baselines_tracked: 45,
#   recent_events: 100
# }

# Use these statistics to tune detection thresholds and evaluate effectiveness
false_positive_rate = stats.false_positives / stats.anomalies_detected
detection_accuracy = stats.confirmed_threats / stats.anomalies_detected
```

## Risk Assessment

### Risk Levels

- **`:low`** - Safe operations with minimal risk
- **`:medium`** - Operations that may have side effects
- **`:high`** - Potentially dangerous operations
- **`:critical`** - Extremely dangerous operations

### Risk Factors

The risk assessor considers:

- **Command Injection**: Dangerous shell commands
- **Path Traversal**: File access outside allowed directories
- **Network Access**: External network connections
- **File Operations**: File system modifications
- **Privilege Escalation**: Commands that might escalate privileges
- **Data Sensitivity**: Access to sensitive files or data

### Custom Risk Assessment

```elixir
# Define custom risk patterns
defmodule MyRiskAssessor do
  def assess_custom_risk(tool_name, params, context) do
    case tool_name do
      "database_query" -> 
        if String.contains?(params["query"], ["DROP", "DELETE"]) do
          %RiskAssessment{risk_level: :high, reasons: ["Destructive database operation"]}
        else
          %RiskAssessment{risk_level: :low, reasons: []}
        end
      _ -> 
        RiskAssessor.assess_risk(tool_name, params, context)
    end
  end
end
```

## Parameter Sanitization

### Automatic Sanitization

The sanitizer automatically handles:

- **Path Parameters**: Prevents directory traversal attacks
- **Command Parameters**: Prevents command injection
- **URL Parameters**: Validates and sanitizes URLs
- **String Parameters**: Detects script injection patterns

### Sanitization Options

```elixir
# Strict mode (more restrictive)
context = %{strict_mode: true, block_on_suspicion: true}

# Permissive mode (warnings only)
context = %{strict_mode: false, block_on_suspicion: false}
```

### Custom Sanitization

```elixir
# Custom sanitization rules
defmodule MyParameterSanitizer do
  def sanitize_custom_params(params, tool_name) do
    case tool_name do
      "api_request" ->
        # Custom API parameter validation
        validate_api_params(params)
      _ ->
        ParameterSanitizer.sanitize_parameters(params, tool_name)
    end
  end
end
```

## Confirmation Flows

### Interactive Confirmation (Web UI)

For web interfaces, use the LiveView component:

```elixir
# In your LiveView
def handle_info({:mcp_tool_execution_request, tool_name, params, confirmation_request}, socket) do
  socket = assign(socket, 
    show_security_dialog: true,
    tool_name: tool_name,
    parameters: params,
    confirmation_request: confirmation_request,
    context: %{server_id: "my_server", user_id: "user123"}
  )
  
  {:noreply, socket}
end

def handle_info({:security_confirmation_result, confirmation_result}, socket) do
  # Process the confirmation result
  {:noreply, assign(socket, show_security_dialog: false)}
end
```

```heex
<!-- In your template -->
<%= if @show_security_dialog do %>
  <.live_component
    module={TheMaestroWeb.Live.Components.SecurityConfirmationDialog}
    id="security-dialog"
    tool_name={@tool_name}
    parameters={@parameters}
    context={@context}
    confirmation_request={@confirmation_request}
  />
<% end %>
```

### Terminal Confirmation (TUI)

For terminal interfaces:

```elixir
# Present TUI confirmation
case TheMaestro.TUI.SecurityConfirmation.prompt_confirmation(
  tool_name, 
  params, 
  confirmation_request, 
  context, 
  warnings
) do
  {:ok, confirmation_result} -> 
    # User confirmed, proceed with execution
  {:error, :cancelled} -> 
    # User cancelled, abort execution
end
```

### Headless Execution

For automated scenarios without user interaction:

```elixir
# Execute with security policies but no user confirmation
{:ok, result} = SecureExecutor.execute_headless(
  tool_name, 
  params, 
  context, 
  %{auto_block_high_risk: true}
)
```

## UI/TUI Integration

### Web UI Component Features

The security confirmation dialog includes:

- **Risk Assessment Display**: Visual risk indicators and explanations
- **Parameter Preview**: Formatted parameter display with syntax highlighting
- **Trust Management**: Options to adjust server/tool trust
- **Sanitization Warnings**: Clear display of security concerns
- **Responsive Design**: Works on desktop and mobile

### TUI Component Features

The terminal interface provides:

- **Color-coded Risk Levels**: Green (low), yellow (medium), red (high/critical)
- **ASCII Art Indicators**: Unicode symbols for better visual feedback  
- **Parameter Formatting**: Pretty-printed JSON parameter display
- **Keyboard Navigation**: Number-based menu selection
- **Warning Display**: Clear formatting for sanitization warnings

### Customizing UI Components

```elixir
# Custom risk display in LiveView
defp custom_risk_badge(assigns) do
  ~H"""
  <div class={"risk-badge risk-#{@risk_level}"}>
    <.icon name={risk_icon(@risk_level)} />
    <span>{String.upcase(to_string(@risk_level))} RISK</span>
  </div>
  """
end

# Custom TUI risk display
defp display_custom_risk(risk_level) do
  case risk_level do
    :low -> IO.puts([IO.ANSI.green(), "🛡️  LOW RISK - Proceed with confidence"])
    :high -> IO.puts([IO.ANSI.red(), "🚨 HIGH RISK - Review carefully"])
    _ -> display_default_risk(risk_level)
  end
end
```

## Security Policies

### Configuration-Based Policies

```elixir
# In config/config.exs
config :the_maestro, :mcp_security,
  default_server_trust: :untrusted,
  require_confirmation_threshold: :medium,
  auto_block_high_risk: true,
  session_trust_timeout: 3600,
  max_concurrent_executions: 10,
  allowed_file_extensions: [".txt", ".json", ".md"],
  blocked_commands: ["rm", "dd", "mkfs", "fdisk"]
```

### Dynamic Policy Updates

```elixir
# Update policies at runtime
TheMaestro.MCP.Security.PolicyEngine.update_policy(%{
  auto_block_high_risk: false,
  require_confirmation_threshold: :low
})

# Per-user policy overrides
TheMaestro.MCP.Security.PolicyEngine.set_user_policy("power_user", %{
  require_confirmation_threshold: :high,
  trusted_servers: ["internal_tools"]
})
```

## Audit Logging

### Security Event Types

- **`:tool_execution`** - Tool was executed successfully
- **`:trust_granted`** - Trust was granted to server/tool
- **`:trust_revoked`** - Trust was revoked from server/tool  
- **`:access_denied`** - Tool execution was blocked
- **`:confirmation_required`** - User confirmation was requested
- **`:policy_violation`** - Security policy was violated

### Logging Configuration

```elixir
# Configure audit destinations
config :the_maestro, :audit_logging,
  destinations: [:logger, :file, :database],
  log_file: "/var/log/maestro/security.log",
  log_level: :info,
  include_parameters: false,  # Set to true for debugging
  retention_days: 90
```

### Accessing Audit Logs

```elixir
# Query audit logs
events = TheMaestro.MCP.Security.AuditLogger.get_events(%{
  user_id: "user123",
  event_type: :tool_execution,
  date_range: {Date.add(Date.utc_today(), -7), Date.utc_today()}
})

# Generate audit reports
report = TheMaestro.MCP.Security.AuditLogger.generate_report(:daily)
```

## Advanced Configuration

### Custom Security Handlers

```elixir
defmodule MySecurityHandler do
  @behaviour TheMaestro.MCP.Security.SecurityHandler
  
  def handle_confirmation_request(request, context) do
    # Custom confirmation logic
    case context.user_role do
      :admin -> {:allow, :admin_override}
      :user -> present_custom_confirmation(request)
    end
  end
  
  def handle_trust_decision(server_id, tool_name, context) do
    # Custom trust logic
    if internal_server?(server_id) do
      :trusted
    else
      :confirm_required
    end
  end
end
```

### Integration with External Systems

```elixir
# LDAP/Active Directory integration
defmodule ADSecurityIntegration do
  def get_user_permissions(user_id) do
    case LDAP.get_user_groups(user_id) do
      {:ok, groups} when "mcp_power_users" in groups ->
        %{trust_level: :high, confirmation_threshold: :high}
      {:ok, groups} when "mcp_users" in groups ->
        %{trust_level: :medium, confirmation_threshold: :medium}
      _ ->
        %{trust_level: :low, confirmation_threshold: :low}
    end
  end
end

# Vault integration for secrets
defmodule VaultSecurityIntegration do
  def get_server_trust_config(server_id) do
    case Vault.read("secret/mcp/servers/#{server_id}") do
      {:ok, %{trust_level: level}} -> level
      _ -> :untrusted
    end
  end
end
```

## Testing

### Unit Tests

The framework includes comprehensive test coverage:

```bash
# Run all security tests
mix test test/the_maestro/mcp/security/

# Run specific component tests
mix test test/the_maestro/mcp/security/trust_manager_test.exs
mix test test/the_maestro/mcp/security/risk_assessor_test.exs
mix test test/the_maestro/mcp/security/parameter_sanitizer_test.exs
mix test test/the_maestro/mcp/security/secure_executor_test.exs
```

### Integration Testing

Test the complete security flow:

```elixir
defmodule MySecurityIntegrationTest do
  use ExUnit.Case
  
  test "complete security flow for file operations" do
    # Set up context
    context = %{server_id: "test_server", user_id: "test_user"}
    
    # Execute secure operation
    result = SecureExecutor.execute_secure(
      "read_file", 
      %{"path" => "/tmp/test.txt"}, 
      context
    )
    
    # Verify security decisions
    assert {:ok, %SecureExecutionResult{
      security_decision: :allowed,
      audit_logged: true
    }} = result
  end
end
```

### Mock Security Context

For testing, use the provided security mocks:

```elixir
defmodule MyTest do
  use ExUnit.Case
  
  setup do
    # Mock security context for testing
    TheMaestro.MCP.Security.TestHelpers.setup_security_context(%{
      trusted_servers: ["test_server"],
      whitelisted_tools: ["safe_tool"],
      confirmation_handler: &mock_confirmation/2
    })
  end
  
  defp mock_confirmation(_request, _context) do
    %ConfirmationResult{
      decision: :allow,
      choice: :execute_once,
      message: "Mock confirmation",
      trust_updated: false,
      audit_logged: true
    }
  end
end
```

## Troubleshooting

### Common Issues

#### 1. Tool Execution Blocked Unexpectedly

**Problem**: Tool execution is blocked even for trusted servers.

**Solutions**:
- Check server trust status: `TrustManager.server_trust_level("server_id")`
- Verify tool whitelist: `TrustManager.get_server_trust("server_id")`
- Review risk assessment: Enable detailed logging to see risk factors
- Check security policies: Ensure `auto_block_high_risk` is not overly restrictive

#### 2. Confirmation Dialog Not Appearing

**Problem**: Security confirmation dialog doesn't show in web UI.

**Solutions**:
- Verify LiveView integration: Check that component is properly included
- Check context interface: Ensure `interface: :web` is set in context
- Review confirmation requirements: Tool might be whitelisted or trusted
- Check JavaScript: Ensure LiveView JavaScript is loaded

#### 3. Parameter Sanitization Too Strict

**Problem**: Valid parameters are being blocked by sanitization.

**Solutions**:
- Use `block_on_suspicion: false` in context for development
- Add custom sanitization rules for your specific use case
- Review parameter names: Sanitizer uses parameter names to determine validation
- Check allowed patterns: Add your patterns to the allowed lists

#### 4. Audit Logs Not Recording

**Problem**: Security events are not being logged.

**Solutions**:
- Check audit configuration: Verify destinations are properly configured
- Review log permissions: Ensure write permissions for log files
- Check database connection: If using database logging, verify connection
- Enable debug logging: Set log level to debug to see all events

### Debug Mode

Enable detailed security debugging:

```elixir
# In config/dev.exs
config :logger, level: :debug

config :the_maestro, :mcp_security,
  debug_mode: true,
  log_all_decisions: true,
  include_stack_traces: true
```

### Security Event Monitoring

Monitor security events in real-time:

```elixir
# Set up security event monitoring
TheMaestro.MCP.Security.EventMonitor.subscribe(self())

# Handle events
def handle_info({:security_event, event}, state) do
  case event.event_type do
    :access_denied -> handle_security_violation(event)
    :policy_violation -> escalate_security_incident(event)
    _ -> log_security_event(event)
  end
  
  {:noreply, state}
end
```

## Best Practices

### 1. Security Configuration

- **Start Restrictive**: Begin with `default_server_trust: :untrusted`
- **Gradual Trust**: Add trust incrementally as you verify server security
- **Regular Audits**: Review trust decisions and audit logs regularly
- **Policy Updates**: Keep security policies updated as threats evolve

### 2. User Experience

- **Clear Messaging**: Provide clear explanations for security decisions
- **Progressive Trust**: Allow users to build trust over time
- **Quick Actions**: Provide shortcuts for power users and safe operations
- **Educational**: Help users understand security implications

### 3. Development Workflow

- **Test Security**: Include security testing in your development process
- **Mock Safely**: Use security mocks that still enforce reasonable constraints
- **Document Decisions**: Document why certain tools/servers are trusted
- **Monitor Production**: Set up proper monitoring and alerting for security events

### 4. Incident Response

- **Audit Trail**: Maintain detailed audit logs for forensic analysis
- **Quick Response**: Have procedures for quickly revoking trust
- **User Communication**: Communicate security issues clearly to users
- **Continuous Improvement**: Learn from security incidents to improve policies

## Conclusion

The MCP Security & Confirmation Framework provides a comprehensive, layered approach to securing MCP tool execution. By implementing proper trust management, risk assessment, parameter sanitization, and confirmation flows, you can ensure that MCP tools are executed safely while maintaining a good user experience.

For additional help or questions about the security framework, refer to the test files in `test/the_maestro/mcp/security/` for comprehensive examples of all features.