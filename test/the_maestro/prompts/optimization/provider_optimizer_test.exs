defmodule TheMaestro.Prompts.ProviderOptimizerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Optimization.ProviderOptimizer
  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  alias TheMaestro.Prompts.Optimization.Structs.OptimizationContext

  describe "optimize_for_provider/3" do
    test "routes to AnthropicOptimizer for Claude models" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test prompt",
        metadata: %{}
      }

      provider_info = %{
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      }

      result = ProviderOptimizer.optimize_for_provider(enhanced_prompt, provider_info)

      assert {:ok, optimized_context} = result
      assert %OptimizationContext{} = optimized_context
    end

    test "routes to GoogleOptimizer for Gemini models" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test prompt",
        metadata: %{}
      }

      provider_info = %{
        provider: :google,
        model: "gemini-1.5-pro"
      }

      result = ProviderOptimizer.optimize_for_provider(enhanced_prompt, provider_info)

      assert {:ok, optimized_context} = result
      assert %OptimizationContext{} = optimized_context
    end

    test "routes to OpenAIOptimizer for ChatGPT models" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test prompt",
        metadata: %{}
      }

      provider_info = %{
        provider: :openai,
        model: "gpt-4o"
      }

      result = ProviderOptimizer.optimize_for_provider(enhanced_prompt, provider_info)

      assert {:ok, optimized_context} = result
      assert %OptimizationContext{} = optimized_context
    end

    test "applies generic optimization for unsupported providers" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test prompt",
        metadata: %{}
      }

      provider_info = %{
        provider: :unknown_provider,
        model: "unknown-model"
      }

      result = ProviderOptimizer.optimize_for_provider(enhanced_prompt, provider_info)

      assert {:ok, optimized_context} = result
      assert %OptimizationContext{} = optimized_context
    end

    test "includes model capabilities in optimization context" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test prompt",
        metadata: %{}
      }

      provider_info = %{
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      }

      {:ok, optimized_context} = ProviderOptimizer.optimize_for_provider(enhanced_prompt, provider_info)

      assert optimized_context.model_capabilities.context_window > 0
      assert is_boolean(optimized_context.model_capabilities.supports_function_calling)
      assert is_boolean(optimized_context.model_capabilities.supports_multimodal)
    end

    test "applies optimization targets based on configuration" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test prompt",
        metadata: %{}
      }

      provider_info = %{
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      }

      optimization_config = %{
        optimize_for_quality: true,
        optimize_for_speed: false,
        optimize_for_cost: true
      }

      {:ok, optimized_context} = ProviderOptimizer.optimize_for_provider(
        enhanced_prompt, 
        provider_info, 
        optimization_config
      )

      assert optimized_context.optimization_targets.quality == true
      assert optimized_context.optimization_targets.speed == false
      assert optimized_context.optimization_targets.cost == true
    end
  end

  describe "get_model_capabilities/1" do
    test "returns comprehensive capabilities for Claude models" do
      provider_info = %{
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      }

      capabilities = ProviderOptimizer.get_model_capabilities(provider_info)

      assert capabilities.context_window == 200_000
      assert capabilities.supports_function_calling == true
      assert capabilities.supports_multimodal == true
      assert capabilities.reasoning_strength == :excellent
      assert capabilities.code_understanding == :excellent
    end

    test "returns comprehensive capabilities for Gemini models" do
      provider_info = %{
        provider: :google,
        model: "gemini-1.5-pro"
      }

      capabilities = ProviderOptimizer.get_model_capabilities(provider_info)

      assert capabilities.context_window == 2_000_000
      assert capabilities.supports_function_calling == true
      assert capabilities.supports_multimodal == true
      assert capabilities.reasoning_strength == :very_good
    end

    test "returns comprehensive capabilities for OpenAI models" do
      provider_info = %{
        provider: :openai,
        model: "gpt-4o"
      }

      capabilities = ProviderOptimizer.get_model_capabilities(provider_info)

      assert capabilities.context_window == 128_000
      assert capabilities.supports_function_calling == true
      assert capabilities.supports_multimodal == true
      assert capabilities.reasoning_strength == :excellent
    end

    test "includes dynamic capability measurements" do
      provider_info = %{
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      }

      capabilities = ProviderOptimizer.get_model_capabilities(provider_info)

      assert is_float(capabilities.actual_context_utilization)
      assert is_float(capabilities.function_calling_reliability)
      assert is_float(capabilities.response_consistency)
    end
  end

  describe "validate_optimization_results/1" do
    test "validates successful optimization results" do
      optimization_context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{enhanced_prompt: "Optimized prompt"},
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        optimization_applied: true,
        optimization_score: 0.85,
        validation_passed: true
      }

      result = ProviderOptimizer.validate_optimization_results(optimization_context)

      assert {:ok, ^optimization_context} = result
    end

    test "returns error for failed optimization validation" do
      optimization_context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{enhanced_prompt: "Failed prompt"},
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        optimization_applied: false,
        optimization_score: 0.3,
        validation_passed: false
      }

      result = ProviderOptimizer.validate_optimization_results(optimization_context)

      assert {:error, :optimization_validation_failed} = result
    end
  end
end