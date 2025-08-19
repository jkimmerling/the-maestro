defmodule TheMaestro.Prompts.Optimization.Config.OptimizationConfigTest do
  use ExUnit.Case, async: false

  alias TheMaestro.Prompts.Optimization.Config.OptimizationConfig

  setup do
    # Store original config to restore after tests that modify it
    original_config = Application.get_env(:the_maestro, :prompt_optimization, [])

    on_exit(fn ->
      # Restore original configuration
      Application.put_env(:the_maestro, :prompt_optimization, original_config)
    end)

    {:ok, original_config: original_config}
  end

  describe "get_provider_config/1" do
    test "returns Anthropic configuration" do
      config = OptimizationConfig.get_provider_config(:anthropic)

      assert is_map(config)
      assert Map.has_key?(config, :max_context_utilization)
      assert Map.has_key?(config, :reasoning_enhancement)
      assert Map.has_key?(config, :structured_thinking)
      assert Map.has_key?(config, :safety_optimization)
      assert Map.has_key?(config, :context_navigation)
    end

    test "returns Google configuration" do
      config = OptimizationConfig.get_provider_config(:google)

      assert is_map(config)
      assert Map.has_key?(config, :multimodal_optimization)
      assert Map.has_key?(config, :function_calling_enhancement)
      assert Map.has_key?(config, :large_context_utilization)
      assert Map.has_key?(config, :integration_optimization)
      assert Map.has_key?(config, :visual_reasoning)
    end

    test "returns OpenAI configuration" do
      config = OptimizationConfig.get_provider_config(:openai)

      assert is_map(config)
      assert Map.has_key?(config, :consistency_optimization)
      assert Map.has_key?(config, :structured_output_enhancement)
      assert Map.has_key?(config, :token_efficiency_priority)
      assert Map.has_key?(config, :reliability_optimization)
      assert Map.has_key?(config, :format_specification)
    end

    test "returns default configuration for unknown provider" do
      config = OptimizationConfig.get_provider_config(:unknown_provider)

      assert is_map(config)
      assert Map.has_key?(config, :basic_optimization)
      assert Map.has_key?(config, :quality_enhancement)
    end
  end

  describe "get_all_provider_configs/0" do
    test "returns configurations for all providers" do
      configs = OptimizationConfig.get_all_provider_configs()

      assert is_map(configs)
      assert Map.has_key?(configs, :anthropic)
      assert Map.has_key?(configs, :google)
      assert Map.has_key?(configs, :openai)

      # Verify each provider config has expected structure
      assert is_map(configs.anthropic)
      assert is_map(configs.google)
      assert is_map(configs.openai)
    end
  end

  describe "validate_config/2" do
    test "validates correct Anthropic configuration" do
      config = %{
        max_context_utilization: 0.9,
        reasoning_enhancement: true,
        structured_thinking: true,
        safety_optimization: true,
        context_navigation: true
      }

      assert OptimizationConfig.validate_config(:anthropic, config)
    end

    test "rejects invalid Anthropic configuration" do
      # Invalid context utilization (> 1.0)
      invalid_config = %{
        max_context_utilization: 1.5,
        reasoning_enhancement: true,
        structured_thinking: true,
        safety_optimization: true,
        context_navigation: true
      }

      refute OptimizationConfig.validate_config(:anthropic, invalid_config)

      # Missing required key
      incomplete_config = %{
        max_context_utilization: 0.9,
        reasoning_enhancement: true
        # missing other required keys
      }

      refute OptimizationConfig.validate_config(:anthropic, incomplete_config)
    end

    test "validates correct Google configuration" do
      config = %{
        multimodal_optimization: true,
        function_calling_enhancement: true,
        large_context_utilization: 0.85,
        integration_optimization: true,
        visual_reasoning: true
      }

      assert OptimizationConfig.validate_config(:google, config)
    end

    test "validates correct OpenAI configuration" do
      config = %{
        consistency_optimization: true,
        structured_output_enhancement: true,
        token_efficiency_priority: :high,
        reliability_optimization: true,
        format_specification: true
      }

      assert OptimizationConfig.validate_config(:openai, config)
    end

    test "rejects invalid OpenAI token efficiency priority" do
      config = %{
        consistency_optimization: true,
        structured_output_enhancement: true,
        token_efficiency_priority: :invalid_priority,
        reliability_optimization: true,
        format_specification: true
      }

      refute OptimizationConfig.validate_config(:openai, config)
    end
  end

  describe "update_provider_config/2" do
    test "updates provider configuration with valid changes" do
      # Store original config
      original_config = OptimizationConfig.get_provider_config(:anthropic)

      # Update with valid changes
      updates = %{max_context_utilization: 0.95}

      assert :ok = OptimizationConfig.update_provider_config(:anthropic, updates)

      # Verify update was applied
      updated_config = OptimizationConfig.get_provider_config(:anthropic)
      assert updated_config.max_context_utilization == 0.95

      # Verify other values remain unchanged
      assert updated_config.reasoning_enhancement == original_config.reasoning_enhancement
    end

    test "rejects invalid configuration updates" do
      # Attempt to update with invalid value
      invalid_updates = %{max_context_utilization: 2.0}

      assert {:error, :invalid_configuration} =
               OptimizationConfig.update_provider_config(:anthropic, invalid_updates)

      # Verify configuration was not changed
      config = OptimizationConfig.get_provider_config(:anthropic)
      assert config.max_context_utilization <= 1.0
    end

    test "updates Google provider configuration" do
      updates = %{large_context_utilization: 0.75}

      assert :ok = OptimizationConfig.update_provider_config(:google, updates)

      updated_config = OptimizationConfig.get_provider_config(:google)
      assert updated_config.large_context_utilization == 0.75
    end

    test "updates OpenAI provider configuration" do
      updates = %{token_efficiency_priority: :medium}

      assert :ok = OptimizationConfig.update_provider_config(:openai, updates)

      updated_config = OptimizationConfig.get_provider_config(:openai)
      assert updated_config.token_efficiency_priority == :medium
    end

    test "rejects invalid Google configuration" do
      invalid_updates = %{large_context_utilization: 1.5}

      assert {:error, :invalid_configuration} =
               OptimizationConfig.update_provider_config(:google, invalid_updates)
    end

    test "rejects invalid OpenAI configuration" do
      invalid_updates = %{token_efficiency_priority: :invalid}

      assert {:error, :invalid_configuration} =
               OptimizationConfig.update_provider_config(:openai, invalid_updates)
    end
  end

  describe "validate_config/2 additional edge cases" do
    test "validates Google configuration with edge case values" do
      # Valid edge case: minimum context utilization
      config = %{
        multimodal_optimization: false,
        function_calling_enhancement: false,
        large_context_utilization: 0.0,
        integration_optimization: false,
        visual_reasoning: false
      }

      assert OptimizationConfig.validate_config(:google, config)

      # Valid edge case: maximum context utilization
      config_max = %{
        multimodal_optimization: true,
        function_calling_enhancement: true,
        large_context_utilization: 1.0,
        integration_optimization: true,
        visual_reasoning: true
      }

      assert OptimizationConfig.validate_config(:google, config_max)
    end

    test "rejects Google configuration with invalid context utilization" do
      config = %{
        multimodal_optimization: true,
        function_calling_enhancement: true,
        large_context_utilization: -0.1,
        integration_optimization: true,
        visual_reasoning: true
      }

      refute OptimizationConfig.validate_config(:google, config)
    end

    test "rejects Google configuration with non-boolean values" do
      config = %{
        multimodal_optimization: "true",
        function_calling_enhancement: true,
        large_context_utilization: 0.8,
        integration_optimization: true,
        visual_reasoning: true
      }

      refute OptimizationConfig.validate_config(:google, config)
    end

    test "rejects Anthropic configuration with non-float context utilization" do
      config = %{
        max_context_utilization: "0.9",
        reasoning_enhancement: true,
        structured_thinking: true,
        safety_optimization: true,
        context_navigation: true
      }

      refute OptimizationConfig.validate_config(:anthropic, config)
    end

    test "rejects Anthropic configuration with negative context utilization" do
      config = %{
        max_context_utilization: -0.1,
        reasoning_enhancement: true,
        structured_thinking: true,
        safety_optimization: true,
        context_navigation: true
      }

      refute OptimizationConfig.validate_config(:anthropic, config)
    end

    test "rejects OpenAI configuration with non-boolean values" do
      config = %{
        consistency_optimization: "true",
        structured_output_enhancement: true,
        token_efficiency_priority: :high,
        reliability_optimization: true,
        format_specification: true
      }

      refute OptimizationConfig.validate_config(:openai, config)
    end

    test "validates unknown provider configuration" do
      config = %{
        basic_optimization: true,
        quality_enhancement: false
      }

      assert OptimizationConfig.validate_config(:unknown, config)
    end

    test "rejects unknown provider configuration with invalid values" do
      config = %{
        basic_optimization: "yes",
        quality_enhancement: true
      }

      refute OptimizationConfig.validate_config(:unknown, config)
    end

    test "rejects configuration with missing required keys for unknown provider" do
      config = %{
        basic_optimization: true
        # missing quality_enhancement
      }

      refute OptimizationConfig.validate_config(:unknown, config)
    end
  end

  describe "default configurations" do
    test "returns correct default config for Anthropic" do
      # First clear any existing config to get true defaults
      Application.delete_env(:the_maestro, :prompt_optimization)

      config = OptimizationConfig.get_provider_config(:anthropic)

      assert config.max_context_utilization == 0.9
      assert config.reasoning_enhancement == true
      assert config.structured_thinking == true
      assert config.safety_optimization == true
      assert config.context_navigation == true
    end

    test "returns correct default config for Google" do
      # First clear any existing config to get true defaults
      Application.delete_env(:the_maestro, :prompt_optimization)

      config = OptimizationConfig.get_provider_config(:google)

      assert config.multimodal_optimization == true
      assert config.function_calling_enhancement == true
      assert config.large_context_utilization == 0.8
      assert config.integration_optimization == true
      assert config.visual_reasoning == true
    end

    test "returns correct default config for OpenAI" do
      # First clear any existing config to get true defaults
      Application.delete_env(:the_maestro, :prompt_optimization)

      config = OptimizationConfig.get_provider_config(:openai)

      assert config.consistency_optimization == true
      assert config.structured_output_enhancement == true
      assert config.token_efficiency_priority == :high
      assert config.reliability_optimization == true
      assert config.format_specification == true
    end
  end
end
