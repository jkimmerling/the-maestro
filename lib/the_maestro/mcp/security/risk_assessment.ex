defmodule TheMaestro.MCP.Security.RiskAssessment do
  @moduledoc """
  Risk assessment result for MCP tool execution.
  
  Contains the evaluated risk level and contributing factors for a specific
  tool execution attempt.
  """
  
  @type risk_level :: :low | :medium | :high | :critical
  @type risk_factor :: atom()
  
  @type t :: %__MODULE__{
    risk_level: risk_level(),
    factors: [risk_factor()],
    score: float(),
    description: String.t(),
    recommendations: [String.t()]
  }
  
  defstruct [
    :risk_level,
    :factors,
    :score,
    :description,
    :recommendations
  ]
  
  @doc """
  Creates a new risk assessment.
  """
  @spec new(risk_level(), [risk_factor()], float()) :: t()
  def new(risk_level, factors, score) do
    %__MODULE__{
      risk_level: risk_level,
      factors: factors,
      score: score,
      description: build_description(risk_level, factors),
      recommendations: build_recommendations(risk_level, factors)
    }
  end
  
  @doc """
  Determines if the risk level requires user confirmation.
  """
  @spec requires_confirmation?(t()) :: boolean()
  def requires_confirmation?(%__MODULE__{risk_level: :low}), do: false
  def requires_confirmation?(%__MODULE__{risk_level: _}), do: true
  
  @doc """
  Checks if the risk level blocks execution entirely.
  """
  @spec blocks_execution?(t()) :: boolean()
  def blocks_execution?(%__MODULE__{risk_level: :critical}), do: true
  def blocks_execution?(%__MODULE__{}), do: false
  
  @doc """
  Gets a human-readable severity description.
  """
  @spec severity_description(risk_level()) :: String.t()
  def severity_description(:low), do: "Low Risk - Generally safe operation"
  def severity_description(:medium), do: "Medium Risk - May require caution"
  def severity_description(:high), do: "High Risk - Potentially dangerous operation"
  def severity_description(:critical), do: "Critical Risk - Dangerous operation that should be blocked"
  
  ## Private Functions
  
  defp build_description(risk_level, factors) do
    base = severity_description(risk_level)
    
    if length(factors) > 0 do
      factor_text = factors
        |> Enum.map(&format_factor/1)
        |> Enum.join(", ")
      
      "#{base} - Factors: #{factor_text}"
    else
      base
    end
  end
  
  defp build_recommendations(risk_level, factors) do
    base_recommendations = case risk_level do
      :low -> ["Operation appears safe to proceed"]
      :medium -> ["Review parameters before proceeding", "Consider if operation is necessary"]  
      :high -> ["Carefully review all parameters", "Ensure you understand the impact", "Consider safer alternatives"]
      :critical -> ["DO NOT PROCEED", "This operation is too dangerous", "Find an alternative approach"]
    end
    
    factor_recommendations = Enum.flat_map(factors, &factor_recommendation/1)
    
    (base_recommendations ++ factor_recommendations)
    |> Enum.uniq()
  end
  
  defp format_factor(:safe_path), do: "safe path access"
  defp format_factor(:read_only_operation), do: "read-only operation"
  defp format_factor(:sensitive_path), do: "sensitive path access"
  defp format_factor(:system_modification), do: "system modification"
  defp format_factor(:destructive_command), do: "destructive command"
  defp format_factor(:network_access), do: "network access"
  defp format_factor(:external_service), do: "external service access"
  defp format_factor(:command_injection_risk), do: "command injection risk"
  defp format_factor(:path_traversal_risk), do: "path traversal risk"  
  defp format_factor(:sensitive_data_detected), do: "sensitive data detected"
  defp format_factor(:privileged_operation), do: "privileged operation"
  defp format_factor(:system_access), do: "system access"
  defp format_factor(factor), do: "#{factor}"
  
  defp factor_recommendation(:sensitive_path), do: ["Verify the path is correct and necessary"]
  defp factor_recommendation(:destructive_command), do: ["Make a backup before proceeding"]
  defp factor_recommendation(:network_access), do: ["Ensure the network destination is trusted"]
  defp factor_recommendation(:command_injection_risk), do: ["Sanitize input parameters", "Use safer alternatives"]
  defp factor_recommendation(:path_traversal_risk), do: ["Validate and sanitize file paths"]
  defp factor_recommendation(:sensitive_data_detected), do: ["Avoid including sensitive data", "Use environment variables"]
  defp factor_recommendation(_), do: []
end