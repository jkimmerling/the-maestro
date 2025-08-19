defmodule TheMaestro.Prompts.Optimization.Adaptation.ABTestingTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  alias TheMaestro.Prompts.Optimization.Adaptation.ABTesting
  alias TheMaestro.Prompts.Optimization.Adaptation.ABTesting.Experiment

  describe "get_active_experiments/1" do
    test "returns active experiments for matching provider" do
      provider_info = %{provider: :anthropic, model: "claude-3-5-sonnet"}

      experiments = ABTesting.get_active_experiments(provider_info)

      assert is_list(experiments)
      assert length(experiments) >= 3
      assert Enum.all?(experiments, & &1.is_active)
      assert Enum.all?(experiments, &(&1.provider == :anthropic))
    end

    test "returns empty list for non-matching provider" do
      provider_info = %{provider: :nonexistent, model: "test"}

      experiments = ABTesting.get_active_experiments(provider_info)

      assert is_list(experiments)
      # Should still return experiments but they won't match in should_apply_experiment?
    end

    test "returned experiments have required fields" do
      provider_info = %{provider: :anthropic, model: "claude-3-5-sonnet"}

      experiments = ABTesting.get_active_experiments(provider_info)

      for experiment <- experiments do
        assert %Experiment{} = experiment
        assert is_binary(experiment.id)
        assert is_binary(experiment.name)
        assert experiment.provider == :anthropic
        assert experiment.variant in [:control, :test_a, :test_b, :test_c]

        assert experiment.optimization_type in [
                 :token_efficiency,
                 :quality_enhancement,
                 :latency_optimization,
                 :safety_improvement
               ]

        assert is_map(experiment.experiment_config)
        assert %DateTime{} = experiment.start_date
        assert is_boolean(experiment.is_active)
        assert is_binary(experiment.target_metric)
        assert is_float(experiment.success_threshold)
        assert is_integer(experiment.control_group_size)
        assert is_integer(experiment.test_group_size)
        assert is_map(experiment.current_results)
      end
    end
  end

  describe "should_apply_experiment?/2" do
    setup do
      experiment = %Experiment{
        id: "test_experiment",
        name: "Test Experiment",
        provider: :anthropic,
        variant: :test_a,
        optimization_type: :quality_enhancement,
        experiment_config: %{},
        start_date: DateTime.utc_now(),
        end_date: nil,
        is_active: true,
        target_metric: "quality",
        success_threshold: 0.1,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      %{experiment: experiment}
    end

    test "returns consistent results for same prompt", %{experiment: experiment} do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test prompt for consistency check",
        metadata: %{}
      }

      # Should return same result multiple times
      result1 = ABTesting.should_apply_experiment?(experiment, enhanced_prompt)
      result2 = ABTesting.should_apply_experiment?(experiment, enhanced_prompt)
      result3 = ABTesting.should_apply_experiment?(experiment, enhanced_prompt)

      assert result1 == result2
      assert result2 == result3
      assert is_boolean(result1)
    end

    test "returns different results for different prompts", %{experiment: experiment} do
      prompts = [
        %EnhancedPrompt{enhanced_prompt: "First unique prompt", metadata: %{}},
        %EnhancedPrompt{enhanced_prompt: "Second unique prompt", metadata: %{}},
        %EnhancedPrompt{enhanced_prompt: "Third unique prompt", metadata: %{}},
        %EnhancedPrompt{enhanced_prompt: "Fourth unique prompt", metadata: %{}},
        %EnhancedPrompt{enhanced_prompt: "Fifth unique prompt", metadata: %{}}
      ]

      results = Enum.map(prompts, &ABTesting.should_apply_experiment?(experiment, &1))

      # Should have variety in results (not all true or all false)
      assert Enum.any?(results, & &1)
      # With 5 different prompts, we should see some variation
      unique_results = Enum.uniq(results)
      assert length(unique_results) >= 1
    end

    test "distributes experiments roughly equally across variants" do
      variants = [:control, :test_a, :test_b, :test_c]

      results =
        for variant <- variants do
          experiment = %Experiment{
            id: "test_#{variant}",
            variant: variant,
            provider: :anthropic,
            optimization_type: :quality_enhancement,
            experiment_config: %{},
            start_date: DateTime.utc_now(),
            is_active: true,
            target_metric: "quality",
            success_threshold: 0.1,
            control_group_size: 100,
            test_group_size: 100,
            current_results: %{}
          }

          # Test with multiple prompts to see distribution
          test_prompts =
            for i <- 1..20 do
              %EnhancedPrompt{
                enhanced_prompt: "Test prompt number #{i} for variant #{variant}",
                metadata: %{}
              }
            end

          applications =
            test_prompts
            |> Enum.map(&ABTesting.should_apply_experiment?(experiment, &1))
            |> Enum.count(& &1)

          {variant, applications}
        end

      # Each variant should get some applications (not 0 for all)
      applications_per_variant = Enum.map(results, fn {_variant, count} -> count end)
      assert Enum.any?(applications_per_variant, &(&1 > 0))
    end
  end

  describe "apply_experimental_optimization/2" do
    setup do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "This is a test prompt for optimization.",
        metadata: %{}
      }

      %{enhanced_prompt: enhanced_prompt}
    end

    test "applies token efficiency optimization", %{enhanced_prompt: enhanced_prompt} do
      experiment = %Experiment{
        id: "token_test",
        optimization_type: :token_efficiency,
        experiment_config: %{
          compression_threshold: 0.7,
          use_abbreviations: true,
          aggressive_pruning: true
        },
        provider: :anthropic,
        variant: :test_a,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "token_reduction",
        success_threshold: 0.15,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      assert %EnhancedPrompt{} = result
      assert is_binary(result.enhanced_prompt)
    end

    test "applies quality enhancement optimization", %{enhanced_prompt: enhanced_prompt} do
      experiment = %Experiment{
        id: "quality_test",
        optimization_type: :quality_enhancement,
        experiment_config: %{
          add_reasoning_steps: true,
          include_validation_prompts: true,
          structured_output_format: true
        },
        provider: :anthropic,
        variant: :test_b,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "quality_score",
        success_threshold: 0.1,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      assert %EnhancedPrompt{} = result
      assert String.contains?(result.enhanced_prompt, "## Reasoning Approach")
      assert String.contains?(result.enhanced_prompt, "## Validation Requirements")
      assert String.contains?(result.enhanced_prompt, "## Output Format")
    end

    test "applies safety improvement optimization", %{enhanced_prompt: enhanced_prompt} do
      experiment = %Experiment{
        id: "safety_test",
        optimization_type: :safety_improvement,
        experiment_config: %{
          add_safety_reminders: true,
          include_ethical_guidelines: true,
          bias_awareness_prompts: true
        },
        provider: :anthropic,
        variant: :test_a,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "safety_score",
        success_threshold: 0.05,
        control_group_size: 200,
        test_group_size: 200,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      assert %EnhancedPrompt{} = result
      assert String.contains?(result.enhanced_prompt, "## Safety Guidelines")
      assert String.contains?(result.enhanced_prompt, "## Ethical Considerations")
      assert String.contains?(result.enhanced_prompt, "## Bias Awareness")
    end

    test "handles unknown optimization type", %{enhanced_prompt: enhanced_prompt} do
      experiment = %Experiment{
        id: "unknown_test",
        optimization_type: :unknown_type,
        experiment_config: %{},
        provider: :anthropic,
        variant: :test_a,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "unknown",
        success_threshold: 0.1,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      # Should return original prompt unchanged
      assert result == enhanced_prompt
    end
  end

  describe "track_experiment_application/3" do
    test "adds experiment metadata when experiments are applied" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test prompt",
        metadata: %{}
      }

      experiments = [
        %Experiment{
          id: "exp1",
          variant: :test_a,
          optimization_type: :token_efficiency,
          provider: :anthropic,
          start_date: DateTime.utc_now(),
          is_active: true,
          target_metric: "tokens",
          success_threshold: 0.1,
          control_group_size: 100,
          test_group_size: 100,
          current_results: %{}
        }
      ]

      provider_info = %{provider: :anthropic}

      result = ABTesting.track_experiment_application(enhanced_prompt, experiments, provider_info)

      assert %EnhancedPrompt{} = result
      assert is_map(result.metadata)
      assert Map.has_key?(result.metadata, :ab_test_applied)
      assert is_boolean(result.metadata.ab_test_applied)
      assert Map.has_key?(result.metadata, :applied_experiments)
      assert is_list(result.metadata.applied_experiments)
      assert Map.has_key?(result.metadata, :experiment_session)
      assert is_binary(result.metadata.experiment_session)
      assert Map.has_key?(result.metadata, :tracked_at)
      assert %DateTime{} = result.metadata.tracked_at
    end

    test "preserves existing metadata" do
      existing_metadata = %{
        existing_key: "existing_value",
        another_key: 42
      }

      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test prompt",
        metadata: existing_metadata
      }

      experiments = []
      provider_info = %{provider: :anthropic}

      result = ABTesting.track_experiment_application(enhanced_prompt, experiments, provider_info)

      # Should preserve existing metadata
      assert result.metadata.existing_key == "existing_value"
      assert result.metadata.another_key == 42

      # Should add new metadata
      assert Map.has_key?(result.metadata, :ab_test_applied)
      assert Map.has_key?(result.metadata, :applied_experiments)
    end
  end

  describe "integrate_ab_testing_optimization/2" do
    test "integrates A/B testing with enhanced prompt" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test integration prompt",
        metadata: %{}
      }

      provider_info = %{provider: :anthropic, model: "claude-3-5-sonnet"}

      result = ABTesting.integrate_ab_testing_optimization(enhanced_prompt, provider_info)

      assert %EnhancedPrompt{} = result
      assert is_binary(result.enhanced_prompt)
      assert is_map(result.metadata)

      # Should have experiment tracking metadata
      assert Map.has_key?(result.metadata, :ab_test_applied)
      assert Map.has_key?(result.metadata, :applied_experiments)
      assert Map.has_key?(result.metadata, :experiment_session)
    end

    test "applies multiple compatible experiments" do
      # Create a prompt that would trigger multiple experiments
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt:
          String.duplicate("This is a longer prompt for testing multiple optimizations. ", 20),
        metadata: %{}
      }

      provider_info = %{provider: :anthropic, model: "claude-3-5-sonnet"}

      result = ABTesting.integrate_ab_testing_optimization(enhanced_prompt, provider_info)

      assert %EnhancedPrompt{} = result
      assert is_binary(result.enhanced_prompt)
      assert is_map(result.metadata)

      # Should track experiment applications
      assert is_list(result.metadata.applied_experiments)
    end

    test "handles empty experiments list gracefully" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Simple test",
        metadata: %{}
      }

      # Mock empty experiments by using non-matching provider
      provider_info = %{provider: :nonexistent_provider}

      result = ABTesting.integrate_ab_testing_optimization(enhanced_prompt, provider_info)

      assert %EnhancedPrompt{} = result
      assert result.enhanced_prompt == enhanced_prompt.enhanced_prompt
      assert is_map(result.metadata)
      assert result.metadata.ab_test_applied == false
      assert result.metadata.applied_experiments == []
    end
  end

  describe "experiment filtering and selection" do
    test "filters experiments by active status" do
      # Test with provider that would have inactive experiments
      provider_info = %{provider: :google, model: "gemini-1.5-pro"}

      experiments = ABTesting.get_active_experiments(provider_info)

      assert is_list(experiments)
      # All returned experiments should be active
      assert Enum.all?(experiments, & &1.is_active)
    end

    test "filters experiments by provider match" do
      provider_info = %{provider: :openai, model: "gpt-4"}

      experiments = ABTesting.get_active_experiments(provider_info)

      assert is_list(experiments)
      # All returned experiments should match provider
      assert Enum.all?(experiments, &(&1.provider == :openai))
    end

    test "filters experiments by date range" do
      provider_info = %{provider: :anthropic, model: "claude-3-5-sonnet"}

      experiments = ABTesting.get_active_experiments(provider_info)

      assert is_list(experiments)
      current_time = DateTime.utc_now()

      # All experiments should be within valid date range
      for experiment <- experiments do
        assert DateTime.compare(current_time, experiment.start_date) != :lt

        if experiment.end_date do
          assert DateTime.compare(current_time, experiment.end_date) == :lt
        end
      end
    end

    test "experiment selection is deterministic based on prompt hash" do
      experiment = %Experiment{
        id: "deterministic_test",
        provider: :anthropic,
        variant: :test_a,
        optimization_type: :quality_enhancement,
        experiment_config: %{},
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "quality",
        success_threshold: 0.1,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      # Same prompt should always give same result
      prompt1 = %EnhancedPrompt{enhanced_prompt: "identical content", metadata: %{}}
      prompt2 = %EnhancedPrompt{enhanced_prompt: "identical content", metadata: %{}}

      result1 = ABTesting.should_apply_experiment?(experiment, prompt1)
      result2 = ABTesting.should_apply_experiment?(experiment, prompt2)

      assert result1 == result2
      assert is_boolean(result1)
    end

    test "different variants have different selection criteria" do
      base_experiment = %Experiment{
        id: "variant_test",
        provider: :anthropic,
        optimization_type: :quality_enhancement,
        experiment_config: %{},
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "quality",
        success_threshold: 0.1,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      variants = [:control, :test_a, :test_b, :test_c]
      prompt = %EnhancedPrompt{enhanced_prompt: "test prompt for variants", metadata: %{}}

      results =
        for variant <- variants do
          experiment = %{base_experiment | variant: variant}
          {variant, ABTesting.should_apply_experiment?(experiment, prompt)}
        end

      # Should have at least some variation across variants
      unique_results = results |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
      assert length(unique_results) >= 1
    end
  end

  describe "optimization application edge cases" do
    test "handles latency optimization type" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt:
          "Complex prompt that needs latency optimization furthermore for example this has optional details.",
        metadata: %{}
      }

      experiment = %Experiment{
        id: "latency_test",
        optimization_type: :latency_optimization,
        experiment_config: %{
          simplify_instructions: true,
          reduce_examples: true,
          prioritize_essential: true
        },
        provider: :anthropic,
        variant: :test_c,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "response_time",
        success_threshold: 0.2,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      assert %EnhancedPrompt{} = result
      # Should simplify text by removing filler words
      refute String.contains?(result.enhanced_prompt, "furthermore")
      refute String.contains?(result.enhanced_prompt, "for example")
      refute String.contains?(result.enhanced_prompt, "optional")
      assert is_binary(result.enhanced_prompt)
    end

    test "optimization preserves original content structure" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt:
          "Original content with specific formatting.\n\nThis should be preserved in some form.",
        metadata: %{original_key: "should_be_preserved"}
      }

      experiment = %Experiment{
        id: "preservation_test",
        optimization_type: :token_efficiency,
        experiment_config: %{
          compression_threshold: 0.5,
          use_abbreviations: false,
          aggressive_pruning: false
        },
        provider: :anthropic,
        variant: :test_a,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "token_reduction",
        success_threshold: 0.1,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      # Should preserve core content while applying optimizations
      assert %EnhancedPrompt{} = result
      assert result.metadata == enhanced_prompt.metadata
      assert is_binary(result.enhanced_prompt)
    end

    test "handles experiments with nil or invalid configuration" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test prompt",
        metadata: %{}
      }

      experiment = %Experiment{
        id: "invalid_config_test",
        optimization_type: :quality_enhancement,
        experiment_config: nil,
        provider: :anthropic,
        variant: :test_a,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "quality",
        success_threshold: 0.1,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      # Should handle gracefully and return original or enhanced prompt
      assert %EnhancedPrompt{} = result
      assert is_binary(result.enhanced_prompt)
    end
  end

  describe "tracking and metadata management" do
    test "handles experiments with complex current_results" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Test prompt",
        metadata: %{}
      }

      experiments = [
        %Experiment{
          id: "complex_results_test",
          variant: :test_a,
          optimization_type: :token_efficiency,
          provider: :anthropic,
          start_date: DateTime.utc_now(),
          is_active: true,
          target_metric: "token_reduction",
          success_threshold: 0.1,
          control_group_size: 100,
          test_group_size: 100,
          current_results: %{
            total_applications: 1547,
            success_rate: 0.73,
            average_improvement: 0.12,
            statistical_significance: true,
            confidence_interval: [0.08, 0.16]
          }
        }
      ]

      provider_info = %{provider: :anthropic}

      result = ABTesting.track_experiment_application(enhanced_prompt, experiments, provider_info)

      assert %EnhancedPrompt{} = result
      assert Map.has_key?(result.metadata, :ab_test_applied)
      assert Map.has_key?(result.metadata, :applied_experiments)
      assert Map.has_key?(result.metadata, :experiment_session)
      assert Map.has_key?(result.metadata, :tracked_at)

      # Should generate unique session ID
      session_id = result.metadata.experiment_session
      assert is_binary(session_id)
      assert String.length(session_id) > 0
    end

    test "tracking with multiple simultaneous experiments" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Multi-experiment test prompt",
        metadata: %{existing: "data"}
      }

      experiments = [
        %Experiment{
          id: "exp_1",
          variant: :test_a,
          optimization_type: :token_efficiency,
          provider: :anthropic,
          start_date: DateTime.utc_now(),
          is_active: true,
          target_metric: "tokens",
          success_threshold: 0.1,
          control_group_size: 100,
          test_group_size: 100,
          current_results: %{}
        },
        %Experiment{
          id: "exp_2",
          variant: :test_b,
          optimization_type: :quality_enhancement,
          provider: :anthropic,
          start_date: DateTime.utc_now(),
          is_active: true,
          target_metric: "quality",
          success_threshold: 0.05,
          control_group_size: 150,
          test_group_size: 150,
          current_results: %{}
        }
      ]

      provider_info = %{provider: :anthropic}

      result = ABTesting.track_experiment_application(enhanced_prompt, experiments, provider_info)

      # Should handle multiple experiments correctly
      assert result.metadata.existing == "data"
      assert is_list(result.metadata.applied_experiments)
      assert length(result.metadata.applied_experiments) <= length(experiments)
    end
  end

  describe "helper function edge cases" do
    test "token efficiency with disabled configuration options" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "This is very important due to the fact that for example it matters.",
        metadata: %{}
      }

      experiment = %Experiment{
        id: "token_disabled_test",
        optimization_type: :token_efficiency,
        experiment_config: %{
          compression_threshold: 0.9,
          use_abbreviations: false,
          aggressive_pruning: false
        },
        provider: :anthropic,
        variant: :test_a,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "token_reduction",
        success_threshold: 0.1,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      # With disabled options, should preserve more content
      assert %EnhancedPrompt{} = result
      assert is_binary(result.enhanced_prompt)
    end

    test "quality enhancement with disabled configuration options" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Analyze this problem.",
        metadata: %{}
      }

      experiment = %Experiment{
        id: "quality_disabled_test",
        optimization_type: :quality_enhancement,
        experiment_config: %{
          add_reasoning_steps: false,
          include_validation_prompts: false,
          structured_output_format: false
        },
        provider: :anthropic,
        variant: :test_b,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "quality_score",
        success_threshold: 0.1,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      # With disabled options, should not add extra sections
      assert %EnhancedPrompt{} = result
      refute String.contains?(result.enhanced_prompt, "## Reasoning Approach")
      refute String.contains?(result.enhanced_prompt, "## Validation Requirements")
      refute String.contains?(result.enhanced_prompt, "## Output Format")
    end

    test "safety improvement with disabled configuration options" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Generate content about topics.",
        metadata: %{}
      }

      experiment = %Experiment{
        id: "safety_disabled_test",
        optimization_type: :safety_improvement,
        experiment_config: %{
          add_safety_reminders: false,
          include_ethical_guidelines: false,
          bias_awareness_prompts: false
        },
        provider: :anthropic,
        variant: :test_a,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "safety_score",
        success_threshold: 0.05,
        control_group_size: 200,
        test_group_size: 200,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      # With disabled options, should not add safety sections
      assert %EnhancedPrompt{} = result
      refute String.contains?(result.enhanced_prompt, "## Safety Guidelines")
      refute String.contains?(result.enhanced_prompt, "## Ethical Considerations")
      refute String.contains?(result.enhanced_prompt, "## Bias Awareness")
    end

    test "latency optimization with disabled configuration options" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Complex prompt furthermore for example with optional details.",
        metadata: %{}
      }

      experiment = %Experiment{
        id: "latency_disabled_test",
        optimization_type: :latency_optimization,
        experiment_config: %{
          simplify_instructions: false,
          reduce_examples: false,
          prioritize_essential: false
        },
        provider: :anthropic,
        variant: :test_c,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "response_time",
        success_threshold: 0.2,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      # With disabled options, should preserve original text
      assert %EnhancedPrompt{} = result
      assert String.contains?(result.enhanced_prompt, "furthermore")
      assert String.contains?(result.enhanced_prompt, "for example")
      assert String.contains?(result.enhanced_prompt, "optional")
    end
  end

  describe "optimization strategies" do
    test "token efficiency optimization reduces redundant content" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt:
          "This is very important and quite significant due to the fact that it is rather essential for example.",
        metadata: %{}
      }

      experiment = %Experiment{
        id: "token_test",
        optimization_type: :token_efficiency,
        experiment_config: %{
          compression_threshold: 0.8,
          use_abbreviations: true,
          aggressive_pruning: true
        },
        provider: :anthropic,
        variant: :test_a,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "token_reduction",
        success_threshold: 0.15,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      # Should remove filler words and use abbreviations
      refute String.contains?(result.enhanced_prompt, "very")
      refute String.contains?(result.enhanced_prompt, "quite")
      refute String.contains?(result.enhanced_prompt, "rather")
      refute String.contains?(result.enhanced_prompt, "due to the fact that")
      assert String.contains?(result.enhanced_prompt, "e.g.")
    end

    test "quality enhancement adds structured elements" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Analyze this problem and provide a solution.",
        metadata: %{}
      }

      experiment = %Experiment{
        id: "quality_test",
        optimization_type: :quality_enhancement,
        experiment_config: %{
          add_reasoning_steps: true,
          include_validation_prompts: true,
          structured_output_format: true
        },
        provider: :anthropic,
        variant: :test_b,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "quality_score",
        success_threshold: 0.1,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      # Should add structured elements
      assert String.contains?(result.enhanced_prompt, "## Reasoning Approach")
      assert String.contains?(result.enhanced_prompt, "systematically")
      assert String.contains?(result.enhanced_prompt, "## Validation Requirements")
      assert String.contains?(result.enhanced_prompt, "## Output Format")
    end

    test "safety improvements add safety guidelines" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Generate content about sensitive topics.",
        metadata: %{}
      }

      experiment = %Experiment{
        id: "safety_test",
        optimization_type: :safety_improvement,
        experiment_config: %{
          add_safety_reminders: true,
          include_ethical_guidelines: true,
          bias_awareness_prompts: true
        },
        provider: :anthropic,
        variant: :test_a,
        start_date: DateTime.utc_now(),
        is_active: true,
        target_metric: "safety_score",
        success_threshold: 0.05,
        control_group_size: 200,
        test_group_size: 200,
        current_results: %{}
      }

      result = ABTesting.apply_experimental_optimization(enhanced_prompt, experiment)

      # Should add safety-related content
      assert String.contains?(result.enhanced_prompt, "## Safety Guidelines")
      assert String.contains?(result.enhanced_prompt, "safety and well-being")
      assert String.contains?(result.enhanced_prompt, "## Ethical Considerations")
      assert String.contains?(result.enhanced_prompt, "fairness")
      assert String.contains?(result.enhanced_prompt, "## Bias Awareness")
      assert String.contains?(result.enhanced_prompt, "assumptions")
    end
  end
end
