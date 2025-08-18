defmodule TheMaestro.MCP.Security.SecureExecutor do
  @moduledoc """
  Security-enhanced MCP Tool Executor with comprehensive security framework.

  This module wraps the standard MCP tool executor with security features:
  - Risk assessment and trust evaluation
  - Parameter sanitization and validation
  - User confirmation flows
  - Security audit logging
  - Policy enforcement

  This is the main integration point between the MCP tool execution system
  and the security framework. All tool executions should go through this
  secure executor to ensure security policies are enforced.

  ## Security Flow

  1. **Policy Evaluation**: Get effective security policy for context
  2. **Permission Checking**: Validate access permissions
  3. **Parameter Sanitization**: Clean and validate input parameters
  4. **Risk Assessment**: Evaluate security risks of the operation
  5. **Anomaly Detection**: Check for suspicious patterns
  6. **Trust Evaluation**: Check server and tool trust levels
  7. **Confirmation Flow**: Present user confirmation if required
  8. **Execution**: Execute tool if authorized
  9. **Audit Logging**: Log security events and decisions

  ## Usage

      context = %{
        server_id: "filesystem_server",
        user_id: "user123",
        session_id: "sess_456",
        interface: :web
      }
      
      {:ok, result} = SecureExecutor.execute_secure("read_file", %{"path" => "/tmp/file"}, context)
  """

  require Logger

  alias TheMaestro.MCP.Tools.Executor

  alias TheMaestro.MCP.Security.{
    ParameterSanitizer,
    ConfirmationEngine,
    AuditLogger,
    Permissions,
    PolicyEngine,
    AnomalyDetector
  }

  alias TheMaestro.MCP.Security.ParameterSanitizer.SanitizationResult
  alias TheMaestro.MCP.Security.ConfirmationEngine.{ConfirmationRequest, ConfirmationResult}

  defmodule SecureExecutionResult do
    @moduledoc """
    Result of secure tool execution including security metadata.
    """
    @type t :: %__MODULE__{
            execution_result: Executor.ExecutionResult.t() | nil,
            security_decision: :allowed | :denied | :cancelled,
            risk_level: atom(),
            confirmation_required: boolean(),
            user_choice: atom() | nil,
            sanitization_warnings: [String.t()],
            permission_violations: [String.t()],
            anomalies_detected: [map()],
            policy_applied: String.t() | nil,
            audit_logged: boolean()
          }

    defstruct [
      :execution_result,
      :security_decision,
      :risk_level,
      :confirmation_required,
      :user_choice,
      sanitization_warnings: [],
      permission_violations: [],
      anomalies_detected: [],
      policy_applied: nil,
      audit_logged: false
    ]
  end

  defmodule SecureExecutionError do
    @moduledoc """
    Error information for failed secure executions.
    """
    @type t :: %__MODULE__{
            type: atom(),
            message: String.t(),
            security_reason: String.t() | nil,
            risk_level: atom() | nil,
            audit_logged: boolean()
          }

    defstruct [
      :type,
      :message,
      :security_reason,
      :risk_level,
      audit_logged: false
    ]
  end

  @doc """
  Executes an MCP tool with comprehensive security checks.

  ## Parameters

  - `tool_name` - Name of the tool to execute
  - `parameters` - Parameters for the tool
  - `context` - Security and execution context

  ## Context Requirements

  - `:server_id` - MCP server identifier
  - `:user_id` - User identifier for security logging
  - `:session_id` - Session identifier
  - `:interface` - Interface type (:web, :tui, :headless)

  ## Options (in context)

  - `:skip_confirmation` - Skip user confirmation (admin override)
  - `:strict_mode` - Enable strict parameter validation
  - `:confirmation_handler` - Custom confirmation handler function
  - `:audit_options` - Custom audit logging options

  ## Returns

  - `{:ok, SecureExecutionResult.t()}` - Successful execution
  - `{:error, SecureExecutionError.t()}` - Failed or blocked execution
  """
  @spec execute_secure(String.t(), map(), map()) ::
          {:ok, SecureExecutionResult.t()} | {:error, SecureExecutionError.t()}
  def execute_secure(tool_name, parameters, context) do
    Logger.info("Secure tool execution requested",
      tool: tool_name,
      server_id: context[:server_id],
      user_id: context[:user_id]
    )

    with {:ok, effective_policy} <- evaluate_policy(context),
         {:ok, permission_checks} <-
           check_permissions(tool_name, parameters, context, effective_policy),
         {:ok, sanitized_params, sanitization_warnings} <-
           sanitize_parameters(tool_name, parameters, context),
         {:ok, anomalies} <- detect_anomalies(tool_name, sanitized_params, context),
         {:ok, confirmation_request} <- evaluate_security(tool_name, sanitized_params, context),
         {:ok, confirmation_result} <- handle_confirmation(confirmation_request, context),
         {:ok, execution_result} <-
           execute_if_authorized(tool_name, sanitized_params, context, confirmation_result) do
      # Create secure execution result
      result = %SecureExecutionResult{
        execution_result: execution_result,
        security_decision: normalize_decision(confirmation_result.decision),
        risk_level: confirmation_request.risk_assessment.risk_level,
        confirmation_required: confirmation_request.requires_confirmation,
        user_choice: confirmation_result.choice,
        sanitization_warnings: sanitization_warnings,
        permission_violations: extract_permission_violations(permission_checks),
        anomalies_detected: anomalies,
        policy_applied: effective_policy[:context_id] || "default",
        audit_logged: true
      }

      # Log successful execution
      AuditLogger.log_tool_execution(
        context[:user_id],
        tool_name,
        context[:server_id],
        sanitized_params,
        confirmation_request.risk_assessment.risk_level,
        :allowed,
        "Execution completed successfully"
      )

      {:ok, result}
    else
      {:error, :sanitization_blocked, reason, warnings} ->
        error = %SecureExecutionError{
          type: :sanitization_blocked,
          message: "Parameter sanitization blocked execution",
          security_reason: reason,
          risk_level: :high,
          audit_logged: true
        }

        # Log sanitization blocking
        AuditLogger.log_access_denied(
          context[:user_id],
          tool_name,
          context[:server_id],
          reason,
          :high,
          %{sanitization_warnings: warnings}
        )

        {:error, error}

      {:error, :security_denied, confirmation_result} ->
        error = %SecureExecutionError{
          type: :security_denied,
          message: confirmation_result.message,
          security_reason: "Security policy denied execution",
          risk_level: :medium,
          audit_logged: true
        }

        # Log security denial
        AuditLogger.log_access_denied(
          context[:user_id],
          tool_name,
          context[:server_id],
          confirmation_result.message,
          :medium,
          %{user_choice: confirmation_result.choice}
        )

        {:error, error}

      {:error, :execution_failed, execution_error} ->
        error = %SecureExecutionError{
          type: :execution_failed,
          message: execution_error.message,
          audit_logged: true
        }

        # Log execution failure
        AuditLogger.log_tool_execution(
          context[:user_id],
          tool_name,
          context[:server_id],
          parameters,
          :medium,
          :denied,
          execution_error.message
        )

        {:error, error}
    end
  end

  @doc """
  Executes a tool in headless mode without user confirmation.

  Uses security policies to make automatic decisions. Suitable for
  batch operations, automated scripts, and system processes.
  """
  @spec execute_headless(String.t(), map(), map(), map()) ::
          {:ok, SecureExecutionResult.t()} | {:error, SecureExecutionError.t()}
  def execute_headless(tool_name, parameters, context, policy_settings \\ %{}) do
    Logger.info("Headless secure tool execution requested",
      tool: tool_name,
      server_id: context[:server_id]
    )

    # Set interface to headless and add system user
    headless_context =
      context
      |> Map.put(:interface, :headless)
      |> Map.put_new(:user_id, "system")
      |> Map.put_new(:session_id, "headless")

    with {:ok, sanitized_params, sanitization_warnings} <-
           sanitize_parameters(tool_name, parameters, headless_context),
         {:ok, confirmation_request} <-
           evaluate_security(tool_name, sanitized_params, headless_context),
         {:ok, confirmation_result} <-
           handle_headless_confirmation(confirmation_request, policy_settings),
         {:ok, execution_result} <-
           execute_if_authorized(
             tool_name,
             sanitized_params,
             headless_context,
             confirmation_result
           ) do
      result = %SecureExecutionResult{
        execution_result: execution_result,
        security_decision: normalize_decision(confirmation_result.decision),
        risk_level: confirmation_request.risk_assessment.risk_level,
        confirmation_required: confirmation_request.requires_confirmation,
        sanitization_warnings: sanitization_warnings,
        audit_logged: true
      }

      {:ok, result}
    else
      {:error, :security_denied, confirmation_result} ->
        error = %SecureExecutionError{
          type: :security_denied,
          message: confirmation_result.message,
          security_reason: "Security policy denied execution",
          risk_level: :medium,
          audit_logged: true
        }

        {:error, error}

      {:error, :sanitization_blocked, reason, warnings} ->
        error = %SecureExecutionError{
          type: :sanitization_blocked,
          message: "Parameter sanitization blocked execution",
          security_reason: reason,
          risk_level: :high,
          audit_logged: true
        }

        {:error, error}

      # Pass through other errors
      error ->
        error
    end
  end

  ## Private Functions

  defp evaluate_policy(context) do
    policy_context = %{
      user_id: Map.get(context, :user_id),
      server_id: Map.get(context, :server_id),
      tool_name: Map.get(context, :tool_name),
      session_id: Map.get(context, :session_id),
      user_roles: Map.get(context, :user_roles, [])
    }

    case PolicyEngine.get_effective_policy(policy_context) do
      {:ok, policy} ->
        {:ok, policy}

      {:error, reason} ->
        Logger.error("Policy evaluation failed", reason: reason, context: policy_context)
        # Fall back to global settings
        {:ok, PolicyEngine.get_global_settings()}
    end
  end

  defp check_permissions(tool_name, parameters, context, effective_policy) do
    # Get or create permissions based on effective policy
    permissions = get_permissions_from_policy(effective_policy, context)

    permission_checks = []

    # Check file system permissions
    permission_checks = permission_checks ++ check_file_permissions(parameters, permissions)

    # Check network permissions  
    permission_checks = permission_checks ++ check_network_permissions(parameters, permissions)

    # Check command permissions
    permission_checks =
      permission_checks ++ check_command_permissions(tool_name, parameters, permissions)

    # Check resource limits (if usage data available)
    usage = Map.get(context, :resource_usage, %{})
    permission_checks = permission_checks ++ Permissions.check_resource_limits(permissions, usage)

    # Fail if any permission check failed
    failed_checks = Enum.filter(permission_checks, &(not &1.allowed))

    if length(failed_checks) > 0 do
      {:error, :permission_denied, failed_checks}
    else
      {:ok, permission_checks}
    end
  end

  defp detect_anomalies(tool_name, parameters, context) do
    # Record the event for anomaly analysis
    event = %{
      event_type: :tool_execution_attempt,
      user_id: Map.get(context, :user_id),
      server_id: Map.get(context, :server_id),
      tool_name: tool_name,
      parameters: parameters,
      resource_usage: Map.get(context, :resource_usage, %{}),
      timestamp: DateTime.utc_now()
    }

    AnomalyDetector.record_event(event)

    # Analyze current context for existing anomalies
    case AnomalyDetector.analyze_context(context) do
      {:ok, anomalies} ->
        # Filter for high-severity anomalies that should block execution
        blocking_anomalies =
          Enum.filter(anomalies, fn anomaly ->
            anomaly.severity in [:high, :critical] and
              anomaly.status == :detected
          end)

        if length(blocking_anomalies) > 0 do
          {:error, :anomaly_detected, blocking_anomalies}
        else
          {:ok, anomalies}
        end

      {:error, reason} ->
        Logger.warn("Anomaly detection failed", reason: reason, context: context)
        # Continue with empty anomaly list if detection fails
        {:ok, []}
    end
  end

  defp get_permissions_from_policy(policy, context) do
    # Extract permission configuration from policy
    permission_config = Map.get(policy, :permissions, %{})
    user_level = determine_user_security_level(context, policy)

    # Start with default permissions for user level
    base_permissions = Permissions.default_permissions(user_level)

    # Merge with policy-specific permissions
    if map_size(permission_config) > 0 do
      Permissions.merge_permissions(base_permissions, permission_config)
    else
      base_permissions
    end
  end

  defp determine_user_security_level(context, policy) do
    user_roles = Map.get(context, :user_roles, [])

    cond do
      "admin" in user_roles or "security_admin" in user_roles -> :admin
      "power_user" in user_roles -> :standard
      PolicyEngine.emergency_mode_active?() -> :restricted
      Map.get(policy, :default_user_level) == :restricted -> :restricted
      true -> :standard
    end
  end

  defp check_file_permissions(parameters, permissions) do
    file_paths = extract_file_paths(parameters)

    Enum.flat_map(file_paths, fn {path, access_type} ->
      [Permissions.check_file_access(permissions, path, access_type)]
    end)
  end

  defp check_network_permissions(parameters, permissions) do
    network_endpoints = extract_network_endpoints(parameters)

    Enum.flat_map(network_endpoints, fn {endpoint, direction} ->
      [Permissions.check_network_access(permissions, endpoint, direction)]
    end)
  end

  defp check_command_permissions(tool_name, parameters, permissions) do
    commands = extract_commands(tool_name, parameters)

    Enum.flat_map(commands, fn command ->
      [Permissions.check_command_permission(permissions, command)]
    end)
  end

  defp extract_file_paths(parameters) do
    paths = []

    # Look for common file path parameter names
    path_params = [
      "path",
      "file",
      "filename",
      "input_file",
      "output_file",
      "source",
      "destination"
    ]

    paths =
      Enum.reduce(path_params, paths, fn param, acc ->
        case Map.get(parameters, param) do
          path when is_binary(path) ->
            # Determine access type based on parameter name
            access_type =
              case param do
                name when name in ["output_file", "destination"] -> :write
                # Default assumption
                "path" -> :read
                _ -> :read
              end

            [{path, access_type} | acc]

          _ ->
            acc
        end
      end)

    paths
  end

  defp extract_network_endpoints(parameters) do
    endpoints = []

    # Look for common network parameter names
    network_params = ["url", "endpoint", "host", "server", "api_endpoint"]

    endpoints =
      Enum.reduce(network_params, endpoints, fn param, acc ->
        case Map.get(parameters, param) do
          endpoint when is_binary(endpoint) ->
            # Assume outbound by default
            [{endpoint, :outbound} | acc]

          _ ->
            acc
        end
      end)

    endpoints
  end

  defp extract_commands(tool_name, parameters) do
    commands = []

    # Include the tool name as a potential command
    commands = [tool_name | commands]

    # Look for explicit command parameters
    command_params = ["command", "cmd", "script", "shell_command"]

    commands =
      Enum.reduce(command_params, commands, fn param, acc ->
        case Map.get(parameters, param) do
          command when is_binary(command) -> [command | acc]
          _ -> acc
        end
      end)

    commands
  end

  defp extract_permission_violations(permission_checks) do
    permission_checks
    |> Enum.filter(&(not &1.allowed))
    |> Enum.map(& &1.reason)
  end

  defp sanitize_parameters(tool_name, parameters, context) do
    options = [
      strict_mode: Map.get(context, :strict_mode, false),
      block_on_suspicion: Map.get(context, :block_on_suspicion, true)
    ]

    case ParameterSanitizer.sanitize_parameters(parameters, tool_name, options) do
      %SanitizationResult{blocked: false, sanitized_params: sanitized, warnings: warnings} ->
        {:ok, sanitized, warnings}

      %SanitizationResult{blocked: true, reason: reason, warnings: warnings} ->
        {:error, :sanitization_blocked, reason, warnings}
    end
  end

  defp evaluate_security(tool_name, parameters, context) do
    tool = %{
      name: tool_name,
      server_id: context[:server_id]
    }

    security_context = %{
      user_id: context[:user_id],
      session_id: context[:session_id],
      server_id: context[:server_id]
    }

    confirmation_request =
      ConfirmationEngine.evaluate_confirmation_requirement(
        tool,
        parameters,
        security_context
      )

    {:ok, confirmation_request}
  end

  defp handle_confirmation(confirmation_request, context) do
    skip_confirmation = Map.get(context, :skip_confirmation, false)
    interface = Map.get(context, :interface, :web)

    cond do
      # Skip confirmation if requested (admin override)
      skip_confirmation ->
        {:ok,
         %ConfirmationResult{
           decision: :allow,
           message: "Confirmation skipped by admin override"
         }}

      # No confirmation required
      not confirmation_request.requires_confirmation ->
        {:ok,
         %ConfirmationResult{
           decision: :allow,
           message: "No confirmation required"
         }}

      # Headless interface uses policy-based decisions
      interface == :headless ->
        handle_headless_confirmation(confirmation_request)

      # Interactive confirmation required
      true ->
        handle_interactive_confirmation(confirmation_request, context)
    end
  end

  defp handle_headless_confirmation(confirmation_request, policy_settings \\ %{}) do
    confirmation_result =
      ConfirmationEngine.handle_headless_security(
        confirmation_request,
        policy_settings
      )

    if confirmation_result.decision == :allow do
      {:ok, confirmation_result}
    else
      {:error, :security_denied, confirmation_result}
    end
  end

  defp handle_interactive_confirmation(confirmation_request, context) do
    # In a full implementation, this would present a UI confirmation dialog
    # For now, we'll simulate based on risk level

    choice = simulate_user_choice(confirmation_request.risk_assessment.risk_level)

    confirmation_context = %{
      user_id: context[:user_id],
      session_id: context[:session_id],
      interface: context[:interface] || :web
    }

    confirmation_result =
      ConfirmationEngine.process_confirmation_choice(
        confirmation_request,
        choice,
        confirmation_context
      )

    if confirmation_result.decision == :allow do
      {:ok, confirmation_result}
    else
      {:error, :security_denied, confirmation_result}
    end
  end

  defp simulate_user_choice(risk_level) do
    # Simulate user behavior for testing
    # In production, this would be replaced by actual UI interaction
    case risk_level do
      :low -> :execute_once
      :medium -> :execute_once
      # Simulate cautious user
      :high -> :cancel
      :critical -> :cancel
    end
  end

  defp execute_if_authorized(tool_name, parameters, context, confirmation_result) do
    case confirmation_result.decision do
      :allow ->
        # Execute using the standard MCP executor
        execution_context = %{
          server_id: context[:server_id],
          connection_manager: Map.get(context, :connection_manager),
          timeout: Map.get(context, :timeout, 30_000)
        }

        case Executor.execute(tool_name, parameters, execution_context) do
          {:ok, result} -> {:ok, result}
          {:error, error} -> {:error, :execution_failed, error}
        end

      :deny ->
        {:error, :security_denied, confirmation_result}
    end
  end

  # Private helper to normalize decision values
  defp normalize_decision(:allow), do: :allowed
  defp normalize_decision(:deny), do: :denied
  defp normalize_decision(other), do: other
end
