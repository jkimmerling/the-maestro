defmodule TheMaestro.Prompts.Integration.ProviderOptimizationIntegrationTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Enhancement.Pipeline
  
  describe "provider optimization integration" do
    test "enhance_prompt_with_provider/3 applies provider-specific optimization for Anthropic" do
      original_prompt = "Write a complex function to analyze data"
      
      context = %{
        user_id: "user123",
        working_directory: "/app",
        environment: %{operating_system: "Darwin"},
        available_tools: [:read_file, :write_file],
        provider_optimization: true
      }

      provider_info = %{
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      }

      result = Pipeline.enhance_prompt_with_provider(original_prompt, context, provider_info)

      assert %{enhanced_prompt: enhanced} = result
      assert is_binary(enhanced)
      assert String.contains?(enhanced, original_prompt)
      
      # Check that provider optimization was applied
      assert Map.get(result.metadata, :provider_optimization_applied, false)
    end

    test "enhance_prompt_with_provider/3 applies provider-specific optimization for Google" do
      original_prompt = "Generate a UI component with image analysis"
      
      context = %{
        user_id: "user123",
        provider_optimization: true
      }

      provider_info = %{
        provider: :google,
        model: "gemini-1.5-pro"
      }

      result = Pipeline.enhance_prompt_with_provider(original_prompt, context, provider_info)

      assert %{enhanced_prompt: enhanced} = result
      assert is_binary(enhanced)
      
      # Check that provider optimization was applied
      assert Map.get(result.metadata, :provider_optimization_applied, false)
    end

    test "enhance_prompt_with_provider/3 applies provider-specific optimization for OpenAI" do
      original_prompt = "Create a structured JSON response"
      
      context = %{
        user_id: "user123",
        provider_optimization: true
      }

      provider_info = %{
        provider: :openai,
        model: "gpt-4o"
      }

      result = Pipeline.enhance_prompt_with_provider(original_prompt, context, provider_info)

      assert %{enhanced_prompt: enhanced} = result
      assert is_binary(enhanced)
      
      # Check that provider optimization was applied
      assert Map.get(result.metadata, :provider_optimization_applied, false)
    end

    test "enhance_prompt_with_provider/3 falls back to generic optimization for unknown providers" do
      original_prompt = "Simple task"
      
      context = %{
        user_id: "user123",
        provider_optimization: true
      }

      # Use invalid provider info to trigger generic fallback
      provider_info = %{
        provider: :invalid_provider,
        model: "invalid-model"
      }

      result = Pipeline.enhance_prompt_with_provider(original_prompt, context, provider_info)

      assert %{enhanced_prompt: enhanced} = result
      assert is_binary(enhanced)
      
      # Should still apply optimization (generic fallback) but indicate it's not provider-specific
      assert Map.get(result.metadata, :provider_optimization_applied, false)
      # Should have a lower optimization score due to generic optimization
      assert Map.get(result.metadata, :optimization_score, 0.0) > 0.0
    end

    test "enhance_prompt/2 continues to work without provider optimization (backward compatibility)" do
      original_prompt = "Fix the auth bug"
      
      context = %{
        user_id: "user123",
        working_directory: "/app",
        available_tools: [:read_file, :write_file]
      }

      result = Pipeline.enhance_prompt(original_prompt, context)

      assert %{enhanced_prompt: enhanced} = result
      assert is_binary(enhanced)
      assert String.contains?(enhanced, original_prompt)
      
      # Should not have provider optimization applied
      refute Map.get(result.metadata, :provider_optimization_applied, false)
    end

    test "enhance_prompt_with_provider/3 with nil provider info works like regular enhance_prompt/2" do
      original_prompt = "Simple task"
      
      context = %{
        user_id: "user123"
      }

      result = Pipeline.enhance_prompt_with_provider(original_prompt, context, nil)

      assert %{enhanced_prompt: enhanced} = result
      assert is_binary(enhanced)
      
      # Should not have provider optimization applied
      refute Map.get(result.metadata, :provider_optimization_applied, false)
    end
  end
end