defmodule TheMaestro.Prompts.Optimization.AdaptiveOptimizerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Optimization.AdaptiveOptimizer
  alias TheMaestro.Prompts.Optimization.Structs.{AdaptationStrategy, InteractionPatterns}

  describe "adapt_optimization_strategy/2" do
    test "analyzes interaction patterns and creates adaptation strategy" do
      provider_info = %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"}
      
      interaction_history = [
        %{
          prompt_type: :reasoning,
          success_rate: 0.95,
          response_quality: 0.9,
          instruction_style: :structured,
          context_length: 5000,
          example_type: :code_focused
        },
        %{
          prompt_type: :creative,
          success_rate: 0.8,
          response_quality: 0.85,
          instruction_style: :conversational,
          context_length: 2000,
          example_type: :narrative_focused
        }
      ]

      result = AdaptiveOptimizer.adapt_optimization_strategy(provider_info, interaction_history)

      assert %AdaptationStrategy{} = result
      assert result.preferred_instruction_style in [:structured, :conversational, :mixed]
      assert is_integer(result.optimal_context_length)
      assert is_list(result.effective_example_types)
      assert is_list(result.successful_reasoning_patterns)
      assert is_list(result.error_prevention_strategies)
    end

    test "validates adaptation effectiveness before storing" do
      provider_info = %{provider: :openai, model: "gpt-4o"}
      
      interaction_history = [
        %{
          prompt_type: :analytical,
          success_rate: 0.3,  # Low success rate
          response_quality: 0.4,
          instruction_style: :unclear,
          context_length: 100_000,  # Too long
          example_type: :confusing
        }
      ]

      result = AdaptiveOptimizer.adapt_optimization_strategy(provider_info, interaction_history)

      assert result.validation_passed == false
      assert is_list(result.validation_issues)
    end

    test "stores successful adaptation strategy for provider" do
      provider_info = %{provider: :google, model: "gemini-1.5-pro"}
      
      interaction_history = [
        %{
          prompt_type: :multimodal,
          success_rate: 0.92,
          response_quality: 0.88,
          instruction_style: :detailed,
          context_length: 10_000,
          example_type: :visual_focused
        }
      ]

      result = AdaptiveOptimizer.adapt_optimization_strategy(provider_info, interaction_history)

      assert result.stored_successfully == true
      assert result.provider_info == provider_info
    end
  end

  describe "analyze_interaction_patterns/1" do
    test "identifies effective instruction styles" do
      history = [
        %{instruction_style: :structured, success_rate: 0.9},
        %{instruction_style: :structured, success_rate: 0.85},
        %{instruction_style: :conversational, success_rate: 0.7},
        %{instruction_style: :detailed, success_rate: 0.95}
      ]

      patterns = AdaptiveOptimizer.analyze_interaction_patterns(history)

      assert %InteractionPatterns{} = patterns
      assert :structured in patterns.effective_instruction_styles
      assert :detailed in patterns.effective_instruction_styles
    end

    test "calculates optimal context lengths" do
      history = [
        %{context_length: 1000, response_quality: 0.7},
        %{context_length: 5000, response_quality: 0.9},
        %{context_length: 10000, response_quality: 0.85},
        %{context_length: 20000, response_quality: 0.6}  # Quality drops at very high length
      ]

      patterns = AdaptiveOptimizer.analyze_interaction_patterns(history)

      # Should identify 5000 as optimal length
      assert patterns.optimal_context_lengths[:average] == 5000
      assert patterns.optimal_context_lengths[:max_effective] <= 10000
    end

    test "classifies effective example types" do
      history = [
        %{example_type: :code_focused, success_rate: 0.9, prompt_type: :technical},
        %{example_type: :narrative_focused, success_rate: 0.6, prompt_type: :technical},
        %{example_type: :visual_focused, success_rate: 0.85, prompt_type: :multimodal},
        %{example_type: :step_by_step, success_rate: 0.92, prompt_type: :reasoning}
      ]

      patterns = AdaptiveOptimizer.analyze_interaction_patterns(history)

      assert :code_focused in patterns.effective_example_types
      assert :step_by_step in patterns.effective_example_types
      # narrative_focused should not be in effective types due to low success rate
      refute :narrative_focused in patterns.effective_example_types
    end

    test "extracts successful reasoning patterns" do
      history = [
        %{
          reasoning_pattern: :step_by_step,
          success_rate: 0.9,
          reasoning_quality: 0.85
        },
        %{
          reasoning_pattern: :pros_and_cons,
          success_rate: 0.88,
          reasoning_quality: 0.9
        },
        %{
          reasoning_pattern: :free_form,
          success_rate: 0.6,
          reasoning_quality: 0.5
        }
      ]

      patterns = AdaptiveOptimizer.analyze_interaction_patterns(history)

      assert :step_by_step in patterns.successful_reasoning_patterns
      assert :pros_and_cons in patterns.successful_reasoning_patterns
      refute :free_form in patterns.successful_reasoning_patterns
    end

    test "identifies error prevention strategies" do
      history = [
        %{
          error_type: :ambiguous_instructions,
          prevention_strategy: :explicit_constraints,
          error_prevented: true
        },
        %{
          error_type: :context_overflow,
          prevention_strategy: :context_compression,
          error_prevented: true
        },
        %{
          error_type: :hallucination,
          prevention_strategy: :fact_checking_prompts,
          error_prevented: false
        }
      ]

      patterns = AdaptiveOptimizer.analyze_interaction_patterns(history)

      assert :explicit_constraints in patterns.error_prevention_strategies
      assert :context_compression in patterns.error_prevention_strategies
      refute :fact_checking_prompts in patterns.error_prevention_strategies
    end
  end

  describe "validate_adaptation_effectiveness/1" do
    test "validates effective adaptation strategies" do
      strategy = %AdaptationStrategy{
        preferred_instruction_style: :structured,
        optimal_context_length: 5000,
        effective_example_types: [:code_focused, :step_by_step],
        successful_reasoning_patterns: [:analytical, :systematic],
        error_prevention_strategies: [:explicit_constraints, :validation_checks]
      }

      result = AdaptiveOptimizer.validate_adaptation_effectiveness(strategy)

      assert result.validation_passed == true
      assert result.validation_score >= 0.7
      assert Enum.empty?(result.validation_issues)
    end

    test "identifies issues with ineffective strategies" do
      strategy = %AdaptationStrategy{
        preferred_instruction_style: nil,
        optimal_context_length: 0,
        effective_example_types: [],
        successful_reasoning_patterns: [],
        error_prevention_strategies: []
      }

      result = AdaptiveOptimizer.validate_adaptation_effectiveness(strategy)

      assert result.validation_passed == false
      assert result.validation_score < 0.5
      assert length(result.validation_issues) > 0
    end

    test "warns about potentially problematic adaptations" do
      strategy = %AdaptationStrategy{
        preferred_instruction_style: :unclear,
        optimal_context_length: 200_000,  # Extremely long
        effective_example_types: [:confusing],
        successful_reasoning_patterns: [:circular],
        error_prevention_strategies: []  # No error prevention
      }

      result = AdaptiveOptimizer.validate_adaptation_effectiveness(strategy)

      assert result.validation_passed == false
      assert "context_length_too_high" in result.validation_issues
      assert "no_error_prevention" in result.validation_issues
    end
  end

  describe "store_adaptation_strategy/2" do
    test "successfully stores validated adaptation strategy" do
      provider_info = %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"}
      
      strategy = %AdaptationStrategy{
        preferred_instruction_style: :structured,
        optimal_context_length: 5000,
        effective_example_types: [:code_focused],
        successful_reasoning_patterns: [:step_by_step],
        error_prevention_strategies: [:validation_checks],
        validation_passed: true,
        validation_score: 0.85
      }

      result = AdaptiveOptimizer.store_adaptation_strategy(strategy, provider_info)

      assert result.stored_successfully == true
      assert result.storage_key == "anthropic:claude-3-5-sonnet-20241022"
      assert result.stored_at != nil
    end

    test "refuses to store invalid adaptation strategy" do
      provider_info = %{provider: :openai, model: "gpt-4o"}
      
      strategy = %AdaptationStrategy{
        preferred_instruction_style: nil,
        validation_passed: false,
        validation_score: 0.3
      }

      result = AdaptiveOptimizer.store_adaptation_strategy(strategy, provider_info)

      assert result.stored_successfully == false
      assert result.error_reason == "validation_failed"
    end
  end
end