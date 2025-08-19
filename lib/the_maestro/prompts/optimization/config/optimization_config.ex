defmodule TheMaestro.Prompts.Optimization.Config.OptimizationConfig do
  @moduledoc """
  Configuration management for provider-specific prompt optimization.

  This module provides functions to retrieve and validate optimization 
  configurations for different LLM providers from the application config.
  """

  @doc """
  Gets optimization configuration for a specific provider.

  ## Parameters

  - `provider` - The provider atom (:anthropic, :google, :openai)

  ## Returns

  A map containing the optimization configuration for the provider,
  or default values if no configuration is found.

  ## Examples

      iex> get_provider_config(:anthropic)
      %{
        max_context_utilization: 0.9,
        reasoning_enhancement: true,
        structured_thinking: true,
        safety_optimization: true,
        context_navigation: true
      }
  """
  @spec get_provider_config(atom()) :: map()
  def get_provider_config(provider) when is_atom(provider) do
    Application.get_env(:the_maestro, :prompt_optimization, [])
    |> Enum.into(%{})
    |> Map.get(provider, get_default_config(provider))
  end

  @doc """
  Gets optimization configuration for all providers.

  ## Returns

  A map with provider atoms as keys and their optimization configs as values.
  """
  @spec get_all_provider_configs() :: map()
  def get_all_provider_configs do
    base_configs =
      Application.get_env(:the_maestro, :prompt_optimization, [])
      |> Enum.into(%{})

    [:anthropic, :google, :openai]
    |> Enum.into(%{}, fn provider ->
      {provider, Map.get(base_configs, provider, get_default_config(provider))}
    end)
  end

  @doc """
  Updates optimization configuration for a provider at runtime.

  ## Parameters

  - `provider` - The provider atom (:anthropic, :google, :openai)
  - `config_updates` - Map of configuration updates to apply

  ## Returns

  `:ok` if successful, `{:error, reason}` if validation fails.
  """
  @spec update_provider_config(atom(), map()) :: :ok | {:error, term()}
  def update_provider_config(provider, config_updates)
      when is_atom(provider) and is_map(config_updates) do
    current_config = get_provider_config(provider)
    updated_config = Map.merge(current_config, config_updates)

    if validate_config_update(provider, updated_config) do
      all_configs = get_all_provider_configs()
      new_all_configs = Map.put(all_configs, provider, updated_config)

      Application.put_env(:the_maestro, :prompt_optimization, new_all_configs)
      :ok
    else
      {:error, :invalid_configuration}
    end
  end

  @doc """
  Validates optimization configuration for a provider.

  ## Parameters

  - `provider` - The provider atom
  - `config` - Configuration map to validate

  ## Returns

  `true` if valid, `false` otherwise.
  """
  @spec validate_config(atom(), map()) :: boolean()
  def validate_config(provider, config) when is_atom(provider) and is_map(config) do
    required_keys = get_required_config_keys(provider)

    # Check that all required keys are present
    has_required_keys = Enum.all?(required_keys, &Map.has_key?(config, &1))

    # Validate value types and ranges
    has_valid_values = validate_config_values(provider, config)

    has_required_keys and has_valid_values
  end

  # Private functions

  defp get_default_config(:anthropic) do
    %{
      max_context_utilization: 0.9,
      reasoning_enhancement: true,
      structured_thinking: true,
      safety_optimization: true,
      context_navigation: true
    }
  end

  defp get_default_config(:google) do
    %{
      multimodal_optimization: true,
      function_calling_enhancement: true,
      large_context_utilization: 0.8,
      integration_optimization: true,
      visual_reasoning: true
    }
  end

  defp get_default_config(:openai) do
    %{
      consistency_optimization: true,
      structured_output_enhancement: true,
      token_efficiency_priority: :high,
      reliability_optimization: true,
      format_specification: true
    }
  end

  defp get_default_config(_provider) do
    %{
      basic_optimization: true,
      quality_enhancement: true
    }
  end

  defp get_required_config_keys(:anthropic) do
    [
      :max_context_utilization,
      :reasoning_enhancement,
      :structured_thinking,
      :safety_optimization,
      :context_navigation
    ]
  end

  defp get_required_config_keys(:google) do
    [
      :multimodal_optimization,
      :function_calling_enhancement,
      :large_context_utilization,
      :integration_optimization,
      :visual_reasoning
    ]
  end

  defp get_required_config_keys(:openai) do
    [
      :consistency_optimization,
      :structured_output_enhancement,
      :token_efficiency_priority,
      :reliability_optimization,
      :format_specification
    ]
  end

  defp get_required_config_keys(_provider) do
    [:basic_optimization, :quality_enhancement]
  end

  defp validate_config_update(provider, config) do
    validate_config(provider, config)
  end

  defp validate_config_values(:anthropic, config) do
    # Validate Anthropic-specific configuration values
    valid_context_utilization =
      case Map.get(config, :max_context_utilization) do
        value when is_float(value) and value >= 0.0 and value <= 1.0 -> true
        _ -> false
      end

    valid_booleans =
      [:reasoning_enhancement, :structured_thinking, :safety_optimization, :context_navigation]
      |> Enum.all?(fn key ->
        case Map.get(config, key) do
          value when is_boolean(value) -> true
          _ -> false
        end
      end)

    valid_context_utilization and valid_booleans
  end

  defp validate_config_values(:google, config) do
    # Validate Google-specific configuration values
    valid_context_utilization =
      case Map.get(config, :large_context_utilization) do
        value when is_float(value) and value >= 0.0 and value <= 1.0 -> true
        _ -> false
      end

    valid_booleans =
      [
        :multimodal_optimization,
        :function_calling_enhancement,
        :integration_optimization,
        :visual_reasoning
      ]
      |> Enum.all?(fn key ->
        case Map.get(config, key) do
          value when is_boolean(value) -> true
          _ -> false
        end
      end)

    valid_context_utilization and valid_booleans
  end

  defp validate_config_values(:openai, config) do
    # Validate OpenAI-specific configuration values
    valid_priority =
      case Map.get(config, :token_efficiency_priority) do
        priority when priority in [:low, :medium, :high] -> true
        _ -> false
      end

    valid_booleans =
      [
        :consistency_optimization,
        :structured_output_enhancement,
        :reliability_optimization,
        :format_specification
      ]
      |> Enum.all?(fn key ->
        case Map.get(config, key) do
          value when is_boolean(value) -> true
          _ -> false
        end
      end)

    valid_priority and valid_booleans
  end

  defp validate_config_values(_provider, config) do
    # Generic validation for unknown providers
    [:basic_optimization, :quality_enhancement]
    |> Enum.all?(fn key ->
      case Map.get(config, key) do
        value when is_boolean(value) -> true
        _ -> false
      end
    end)
  end
end
