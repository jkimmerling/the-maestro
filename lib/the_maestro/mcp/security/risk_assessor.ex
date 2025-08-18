defmodule TheMaestro.MCP.Security.RiskAssessor do
  @moduledoc """
  Risk assessment engine for MCP tool execution.

  Analyzes tool execution requests to identify potential security risks
  and assigns appropriate risk levels. The risk assessment considers:

  - Tool type and capabilities
  - Parameter values and patterns
  - File system access patterns
  - Network access requirements
  - Command injection potential
  - Sensitive data exposure
  - System modification potential

  ## Risk Levels

  - `:low` - Safe operations that can proceed without confirmation
  - `:medium` - Operations that may require user awareness
  - `:high` - Potentially dangerous operations requiring confirmation
  - `:critical` - Extremely dangerous operations that should be blocked

  ## Risk Factors

  The assessor identifies specific risk factors that contribute to the
  overall risk level, such as:

  - `:safe_path` - Accessing safe, non-sensitive paths
  - `:sensitive_path` - Accessing system or user-sensitive paths
  - `:destructive_command` - Commands that can destroy data
  - `:network_access` - Operations requiring network access
  - `:command_injection_risk` - Parameters with injection potential
  - `:sensitive_data_detected` - Parameters containing sensitive data
  """

  require Logger
  alias TheMaestro.MCP.Security.RiskAssessment

  @type tool :: map()
  @type parameters :: map()

  # Risk level thresholds
  @low_threshold 0.1
  @medium_threshold 0.3
  @high_threshold 0.6

  # Sensitive path patterns
  @sensitive_paths [
    # Unix system paths
    "/etc/",
    "/root/",
    "/proc/",
    "/sys/",
    "/dev/",
    "/boot/",
    # User sensitive paths
    "/home/",
    "~/.ssh/",
    "~/.aws/",
    "~/.gnupg/",
    # Windows system paths
    "C:\\Windows\\",
    "C:\\Program Files\\",
    "C:\\Users\\",
    # Configuration and credential files
    ".env",
    "config",
    "credentials",
    "private",
    "secret",
    "passwd",
    "shadow",
    "authorized_keys",
    "id_rsa",
    "id_dsa"
  ]

  # Dangerous command patterns
  @dangerous_commands [
    # Deletion commands
    "rm -rf",
    "rmdir",
    "del /s",
    "rd /s",
    # Permission changes
    "chmod 777",
    "chmod 666",
    "chown root",
    # System modification
    "passwd",
    "sudo",
    "su -",
    "systemctl",
    "service",
    # Network tools that can be dangerous
    "wget",
    "curl.*sh",
    "curl.*bash",
    # Archive extraction (can overwrite)
    "tar.*--absolute",
    "unzip.*-o",
    # Fork bomb and system overload
    ":()",
    "while true",
    "for((;;))",
    # Disk operations
    "dd if=",
    "fdisk",
    "mkfs",
    "format"
  ]

  # Sensitive data patterns
  @sensitive_patterns [
    "password",
    "passwd",
    "pwd",
    "secret",
    "token",
    "key",
    "auth",
    "credential",
    "api_key",
    "private",
    "confidential"
  ]

  @doc """
  Assesses the risk level of executing a tool with given parameters.

  ## Parameters

  - `tool` - Tool information map with name and server_id
  - `parameters` - Parameters to be passed to the tool

  ## Returns

  `RiskAssessment.t()` containing risk level, factors, and recommendations

  ## Examples

      iex> tool = %{name: "read_file", server_id: "fs"}
      iex> params = %{"path" => "/tmp/safe.txt"}
      iex> assessment = RiskAssessor.assess_risk(tool, params)
      iex> assessment.risk_level
      :low

      iex> tool = %{name: "execute_command", server_id: "shell"}
      iex> params = %{"command" => "rm -rf /"}
      iex> assessment = RiskAssessor.assess_risk(tool, params)
      iex> assessment.risk_level
      :critical
  """
  @spec assess_risk(tool(), parameters()) :: RiskAssessment.t()
  def assess_risk(tool, parameters) do
    factors = identify_risk_factors(tool, parameters)
    score = calculate_risk_score(factors)
    risk_level = classify_risk_level(factors, score)

    Logger.debug("Risk assessment completed",
      tool: tool.name || "unknown",
      risk_level: risk_level,
      score: score,
      factors: factors
    )

    RiskAssessment.new(risk_level, factors, score)
  end

  @doc """
  Classifies risk level based on identified factors and score.

  Uses both rule-based classification (critical factors always result
  in critical risk) and score-based classification for other cases.
  """
  @spec classify_risk_level([atom()], float()) :: RiskAssessment.risk_level()
  def classify_risk_level(factors, score) do
    cond do
      # Critical factors always result in critical risk
      has_critical_factors?(factors) ->
        :critical

      # High-risk factors
      has_high_risk_factors?(factors) ->
        :high

      # Score-based classification for other cases
      score > @high_threshold ->
        :high

      score > @medium_threshold ->
        :medium

      score > @low_threshold ->
        :low

      true ->
        :low
    end
  end

  @doc """
  Convenience function that takes only factors (used in tests).
  """
  @spec classify_risk_level_by_factors([atom()]) :: RiskAssessment.risk_level()
  def classify_risk_level_by_factors(factors) when is_list(factors) do
    score = calculate_risk_score(factors)
    classify_risk_level(factors, score)
  end

  ## Private Functions

  defp identify_risk_factors(tool, parameters) do
    tool_name = tool.name || tool[:name] || "unknown"

    []
    |> add_tool_based_factors(tool_name)
    |> add_parameter_based_factors(parameters)
    |> Enum.uniq()
  end

  defp add_tool_based_factors(factors, tool_name) do
    case tool_name do
      "read_file" ->
        [:read_only_operation | factors]

      "write_file" ->
        [:file_modification | factors]

      "list_directory" ->
        [:read_only_operation | factors]

      "execute_command" ->
        [:system_command_execution | factors]

      "http_request" ->
        [:network_access | factors]

      "delete_file" ->
        [:destructive_operation | factors]

      _ ->
        factors
    end
  end

  defp add_parameter_based_factors(factors, parameters) when is_map(parameters) do
    factors
    |> add_path_based_factors(parameters)
    |> add_command_based_factors(parameters)
    |> add_network_based_factors(parameters)
    |> add_sensitive_data_factors(parameters)
  end

  defp add_parameter_based_factors(factors, _), do: factors

  defp add_path_based_factors(factors, parameters) do
    case get_path_parameter(parameters) do
      nil ->
        factors

      path ->
        cond do
          sensitive_path?(path) ->
            factors = [:sensitive_path | factors]

            if has_path_traversal?(path) do
              [:path_traversal_risk | factors]
            else
              factors
            end

          has_path_traversal?(path) ->
            [:path_traversal_risk | factors]

          true ->
            [:safe_path | factors]
        end
    end
  end

  defp add_command_based_factors(factors, parameters) do
    case get_command_parameter(parameters) do
      nil ->
        factors

      command ->
        new_factors = []

        new_factors =
          if dangerous_command?(command) do
            [:destructive_command | new_factors]
          else
            new_factors
          end

        new_factors =
          if has_command_injection_risk?(command) do
            [:command_injection_risk | new_factors]
          else
            new_factors
          end

        new_factors =
          if system_modification_command?(command) do
            [:system_modification | new_factors]
          else
            new_factors
          end

        factors ++ new_factors
    end
  end

  defp add_network_based_factors(factors, parameters) do
    case get_network_parameter(parameters) do
      nil ->
        factors

      url ->
        new_factors = [:network_access]

        new_factors =
          if external_service?(url) do
            [:external_service | new_factors]
          else
            new_factors
          end

        new_factors =
          if insecure_protocol?(url) do
            [:insecure_protocol | new_factors]
          else
            new_factors
          end

        factors ++ new_factors
    end
  end

  defp add_sensitive_data_factors(factors, parameters) do
    if contains_sensitive_data?(parameters) do
      [:sensitive_data_detected | factors]
    else
      factors
    end
  end

  defp get_path_parameter(parameters) do
    parameters["path"] || parameters[:path] ||
      parameters["file"] || parameters[:file] ||
      parameters["filename"] || parameters[:filename]
  end

  defp get_command_parameter(parameters) do
    parameters["command"] || parameters[:command] ||
      parameters["cmd"] || parameters[:cmd] ||
      parameters["script"] || parameters[:script]
  end

  defp get_network_parameter(parameters) do
    parameters["url"] || parameters[:url] ||
      parameters["endpoint"] || parameters[:endpoint] ||
      parameters["host"] || parameters[:host]
  end

  defp sensitive_path?(path) when is_binary(path) do
    Enum.any?(@sensitive_paths, &String.contains?(path, &1))
  end

  defp sensitive_path?(_), do: false

  defp has_path_traversal?(path) when is_binary(path) do
    String.contains?(path, "../") or String.contains?(path, "..\\")
  end

  defp has_path_traversal?(_), do: false

  defp dangerous_command?(command) when is_binary(command) do
    Enum.any?(@dangerous_commands, fn pattern ->
      String.contains?(String.downcase(command), String.downcase(pattern))
    end)
  end

  defp dangerous_command?(_), do: false

  defp has_command_injection_risk?(command) when is_binary(command) do
    injection_patterns = [";", "&&", "||", "|", "`", "$(", "${"]
    Enum.any?(injection_patterns, &String.contains?(command, &1))
  end

  defp has_command_injection_risk?(_), do: false

  defp system_modification_command?(command) when is_binary(command) do
    system_commands = ["chmod", "chown", "passwd", "sudo", "systemctl", "service"]
    command_lower = String.downcase(command)
    Enum.any?(system_commands, &String.contains?(command_lower, &1))
  end

  defp system_modification_command?(_), do: false

  defp external_service?(url) when is_binary(url) do
    # Simple heuristic - not localhost or private networks
    not (String.contains?(url, "localhost") or
           String.contains?(url, "127.0.0.1") or
           String.contains?(url, "192.168.") or
           String.contains?(url, "10.0."))
  end

  defp external_service?(_), do: false

  defp insecure_protocol?(url) when is_binary(url) do
    insecure_protocols = ["http://", "ftp://", "telnet://", "ldap://"]
    url_lower = String.downcase(url)
    Enum.any?(insecure_protocols, &String.starts_with?(url_lower, &1))
  end

  defp insecure_protocol?(_), do: false

  defp contains_sensitive_data?(parameters) when is_map(parameters) do
    parameters
    |> Enum.any?(fn {_key, value} ->
      contains_sensitive_value?(value)
    end)
  end

  defp contains_sensitive_data?(_), do: false

  defp contains_sensitive_value?(value) when is_binary(value) do
    value_lower = String.downcase(value)
    Enum.any?(@sensitive_patterns, &String.contains?(value_lower, &1))
  end

  defp contains_sensitive_value?(value) when is_map(value) do
    contains_sensitive_data?(value)
  end

  defp contains_sensitive_value?(value) when is_list(value) do
    Enum.any?(value, &contains_sensitive_value?/1)
  end

  defp contains_sensitive_value?(_), do: false

  defp calculate_risk_score(factors) do
    factors
    |> Enum.map(&factor_weight/1)
    |> Enum.sum()
    # Cap at 1.0
    |> min(1.0)
  end

  # Risk factor weights for score calculation
  # Actually reduces risk
  defp factor_weight(:safe_path), do: -0.05
  defp factor_weight(:read_only_operation), do: 0.0
  defp factor_weight(:file_modification), do: 0.15
  defp factor_weight(:network_access), do: 0.2
  defp factor_weight(:external_service), do: 0.15
  defp factor_weight(:insecure_protocol), do: 0.25
  defp factor_weight(:sensitive_path), do: 0.4
  defp factor_weight(:sensitive_data_detected), do: 0.35
  defp factor_weight(:path_traversal_risk), do: 0.5
  defp factor_weight(:command_injection_risk), do: 0.7
  defp factor_weight(:system_command_execution), do: 0.3
  defp factor_weight(:system_modification), do: 0.5
  defp factor_weight(:destructive_operation), do: 0.6
  defp factor_weight(:destructive_command), do: 0.8
  # Add this one
  defp factor_weight(:system_access), do: 0.4
  # Unknown factors get minimal weight
  defp factor_weight(_), do: 0.05

  defp has_critical_factors?(factors) do
    critical_factors = [:destructive_command, :command_injection_risk]
    Enum.any?(factors, &(&1 in critical_factors))
  end

  defp has_high_risk_factors?(factors) do
    high_risk_factors = [
      :sensitive_path,
      :path_traversal_risk,
      :system_modification,
      :destructive_operation,
      :sensitive_data_detected
    ]

    Enum.any?(factors, &(&1 in high_risk_factors))
  end
end
