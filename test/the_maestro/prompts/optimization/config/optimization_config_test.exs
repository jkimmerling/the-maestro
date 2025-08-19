defmodule TheMaestro.Prompts.Optimization.Config.OptimizationConfigTest do
  use ExUnit.Case, async: true
  
  alias TheMaestro.Prompts.Optimization.Config.OptimizationConfig

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
  end
end