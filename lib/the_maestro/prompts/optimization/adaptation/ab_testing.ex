defmodule TheMaestro.Prompts.Optimization.Adaptation.ABTesting do
  @moduledoc """
  A/B testing integration for continuous optimization improvement.

  This module provides A/B testing capabilities to systematically test
  different optimization strategies and improve prompt optimization 
  effectiveness over time.
  """

  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt

  defmodule Experiment do
    @moduledoc """
    Structure representing an A/B testing experiment.
    """

    defstruct [
      :id,
      :name,
      :provider,
      :variant,
      :optimization_type,
      :experiment_config,
      :start_date,
      :end_date,
      :is_active,
      :target_metric,
      :success_threshold,
      :control_group_size,
      :test_group_size,
      :current_results
    ]

    @type optimization_type ::
            :token_efficiency | :quality_enhancement | :latency_optimization | :safety_improvement
    @type variant :: :control | :test_a | :test_b | :test_c

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            provider: atom(),
            variant: variant(),
            optimization_type: optimization_type(),
            experiment_config: map(),
            start_date: DateTime.t(),
            end_date: DateTime.t() | nil,
            is_active: boolean(),
            target_metric: String.t(),
            success_threshold: float(),
            control_group_size: non_neg_integer(),
            test_group_size: non_neg_integer(),
            current_results: map()
          }
  end

  @doc """
  Integrates A/B testing optimization with the enhanced prompt.

  Applies experimental optimizations based on active experiments
  and tracks their application for effectiveness measurement.
  """
  @spec integrate_ab_testing_optimization(EnhancedPrompt.t(), map()) :: EnhancedPrompt.t()
  def integrate_ab_testing_optimization(enhanced_prompt, provider_info) do
    active_experiments = get_active_experiments(provider_info)

    Enum.reduce(active_experiments, enhanced_prompt, fn experiment, current_prompt ->
      if should_apply_experiment?(experiment, current_prompt) do
        apply_experimental_optimization(current_prompt, experiment)
      else
        current_prompt
      end
    end)
    |> track_experiment_application(active_experiments, provider_info)
  end

  @doc """
  Gets currently active experiments for a provider.
  """
  @spec get_active_experiments(map()) :: [Experiment.t()]
  def get_active_experiments(provider_info) do
    # Fetch active experiments from configuration or storage
    experiments = [
      %Experiment{
        id: "token_efficiency_001",
        name: "Token Compression Strategy A",
        provider: provider_info.provider,
        variant: :test_a,
        optimization_type: :token_efficiency,
        experiment_config: %{
          compression_threshold: 0.7,
          use_abbreviations: true,
          aggressive_pruning: true
        },
        start_date: DateTime.utc_now() |> DateTime.add(-7, :day),
        end_date: DateTime.utc_now() |> DateTime.add(7, :day),
        is_active: true,
        target_metric: "token_reduction",
        success_threshold: 0.15,
        control_group_size: 100,
        test_group_size: 100,
        current_results: %{}
      },
      %Experiment{
        id: "quality_enhancement_002",
        name: "Structured Reasoning Enhancement",
        provider: provider_info.provider,
        variant: :test_b,
        optimization_type: :quality_enhancement,
        experiment_config: %{
          add_reasoning_steps: true,
          include_validation_prompts: true,
          structured_output_format: true
        },
        start_date: DateTime.utc_now() |> DateTime.add(-5, :day),
        end_date: DateTime.utc_now() |> DateTime.add(10, :day),
        is_active: true,
        target_metric: "response_quality_score",
        success_threshold: 0.10,
        control_group_size: 150,
        test_group_size: 150,
        current_results: %{}
      },
      %Experiment{
        id: "safety_optimization_003",
        name: "Enhanced Safety Guidelines",
        provider: provider_info.provider,
        variant: :test_a,
        optimization_type: :safety_improvement,
        experiment_config: %{
          add_safety_reminders: true,
          include_ethical_guidelines: true,
          bias_awareness_prompts: true
        },
        start_date: DateTime.utc_now() |> DateTime.add(-3, :day),
        end_date: DateTime.utc_now() |> DateTime.add(14, :day),
        is_active: true,
        target_metric: "safety_compliance_score",
        success_threshold: 0.05,
        control_group_size: 200,
        test_group_size: 200,
        current_results: %{}
      }
    ]

    # Filter for active experiments matching the provider
    experiments
    |> Enum.filter(& &1.is_active)
    |> Enum.filter(fn exp ->
      exp.provider == provider_info.provider and
        DateTime.compare(DateTime.utc_now(), exp.start_date) != :lt and
        (is_nil(exp.end_date) or DateTime.compare(DateTime.utc_now(), exp.end_date) == :lt)
    end)
  end

  @doc """
  Determines whether an experiment should be applied to the current prompt.
  """
  @spec should_apply_experiment?(Experiment.t(), EnhancedPrompt.t()) :: boolean()
  def should_apply_experiment?(experiment, enhanced_prompt) do
    # Use deterministic selection based on prompt content hash
    prompt_hash =
      :crypto.hash(:md5, enhanced_prompt.enhanced_prompt)
      |> Base.encode16()
      |> String.slice(0, 8)

    hash_int = String.to_integer(prompt_hash, 16)
    selection_bucket = rem(hash_int, 100)

    # Apply experiment to approximately 50% of prompts
    cond do
      experiment.variant == :control -> selection_bucket < 25
      experiment.variant == :test_a -> selection_bucket >= 25 and selection_bucket < 50
      experiment.variant == :test_b -> selection_bucket >= 50 and selection_bucket < 75
      experiment.variant == :test_c -> selection_bucket >= 75
      true -> false
    end
  end

  @doc """
  Applies experimental optimization to the enhanced prompt.
  """
  @spec apply_experimental_optimization(EnhancedPrompt.t(), Experiment.t()) :: EnhancedPrompt.t()
  def apply_experimental_optimization(enhanced_prompt, experiment) do
    case experiment.optimization_type do
      :token_efficiency ->
        apply_token_efficiency_experiment(enhanced_prompt, experiment)

      :quality_enhancement ->
        apply_quality_enhancement_experiment(enhanced_prompt, experiment)

      :latency_optimization ->
        apply_latency_optimization_experiment(enhanced_prompt, experiment)

      :safety_improvement ->
        apply_safety_improvement_experiment(enhanced_prompt, experiment)

      _ ->
        enhanced_prompt
    end
  end

  @doc """
  Tracks the application of experiments to the enhanced prompt.
  """
  @spec track_experiment_application(EnhancedPrompt.t(), [Experiment.t()], map()) ::
          EnhancedPrompt.t()
  def track_experiment_application(enhanced_prompt, active_experiments, _provider_info) do
    applied_experiments =
      active_experiments
      |> Enum.filter(&should_apply_experiment?(&1, enhanced_prompt))
      |> Enum.map(fn exp -> %{id: exp.id, variant: exp.variant, type: exp.optimization_type} end)

    # Add experiment tracking to metadata
    experiment_metadata = %{
      ab_test_applied: length(applied_experiments) > 0,
      applied_experiments: applied_experiments,
      experiment_session: generate_experiment_session_id(),
      tracked_at: DateTime.utc_now()
    }

    updated_metadata = Map.merge(enhanced_prompt.metadata || %{}, experiment_metadata)

    %{enhanced_prompt | metadata: updated_metadata}
  end

  # Private functions for applying specific experiment types

  defp apply_token_efficiency_experiment(enhanced_prompt, experiment) do
    config = experiment.experiment_config
    text = enhanced_prompt.enhanced_prompt

    optimized_text =
      text
      |> apply_compression_if_enabled(config[:compression_threshold], config[:aggressive_pruning])
      |> apply_abbreviations_if_enabled(config[:use_abbreviations])
      |> remove_redundant_phrases_if_enabled(config[:aggressive_pruning])

    %{enhanced_prompt | enhanced_prompt: optimized_text}
  end

  defp apply_quality_enhancement_experiment(enhanced_prompt, experiment) do
    config = experiment.experiment_config
    text = enhanced_prompt.enhanced_prompt

    enhanced_text =
      text
      |> add_reasoning_structure_if_enabled(config[:add_reasoning_steps])
      |> include_validation_if_enabled(config[:include_validation_prompts])
      |> structure_output_format_if_enabled(config[:structured_output_format])

    %{enhanced_prompt | enhanced_prompt: enhanced_text}
  end

  defp apply_latency_optimization_experiment(enhanced_prompt, experiment) do
    config = experiment.experiment_config
    text = enhanced_prompt.enhanced_prompt

    optimized_text =
      text
      |> simplify_instructions_if_enabled(config[:simplify_instructions])
      |> reduce_examples_if_enabled(config[:reduce_examples])
      |> prioritize_essential_context_if_enabled(config[:prioritize_essential])

    %{enhanced_prompt | enhanced_prompt: optimized_text}
  end

  defp apply_safety_improvement_experiment(enhanced_prompt, experiment) do
    config = experiment.experiment_config
    text = enhanced_prompt.enhanced_prompt

    safety_enhanced_text =
      text
      |> add_safety_reminders_if_enabled(config[:add_safety_reminders])
      |> include_ethical_guidelines_if_enabled(config[:include_ethical_guidelines])
      |> add_bias_awareness_if_enabled(config[:bias_awareness_prompts])

    %{enhanced_prompt | enhanced_prompt: safety_enhanced_text}
  end

  # Helper functions for conditional optimizations

  defp apply_compression_if_enabled(text, threshold, true) when is_float(threshold) do
    word_count = String.split(text) |> length()
    target_reduction = trunc(word_count * (1 - threshold))

    if word_count > target_reduction do
      # Simple compression by removing filler words and redundant phrases
      text
      |> String.replace(~r/\b(very|quite|rather|somewhat|fairly)\s+/, "")
      |> String.replace(~r/\b(in order to|so as to)\b/, "to")
      |> String.replace(~r/\b(due to the fact that|because of the fact that)\b/, "because")
    else
      text
    end
  end

  defp apply_compression_if_enabled(text, _threshold, _enabled), do: text

  defp apply_abbreviations_if_enabled(text, true) do
    text
    |> String.replace("for example", "e.g.")
    |> String.replace("that is", "i.e.")
    |> String.replace("et cetera", "etc.")
    |> String.replace("versus", "vs.")
  end

  defp apply_abbreviations_if_enabled(text, _), do: text

  defp remove_redundant_phrases_if_enabled(text, true) do
    text
    |> String.replace(~r/\bplease note that\b/i, "")
    |> String.replace(~r/\bit should be noted that\b/i, "")
    |> String.replace(~r/\bit is important to (mention|note) that\b/i, "")
  end

  defp remove_redundant_phrases_if_enabled(text, _), do: text

  defp add_reasoning_structure_if_enabled(text, true) do
    if not String.contains?(text, ["## Reasoning", "## Analysis", "## Approach"]) do
      text <>
        """

        ## Reasoning Approach
        Please work through this systematically:
        1. Analyze the requirements and constraints
        2. Consider multiple approaches and their trade-offs
        3. Select the optimal approach with clear reasoning
        4. Implement step-by-step with validation
        """
    else
      text
    end
  end

  defp add_reasoning_structure_if_enabled(text, _), do: text

  defp include_validation_if_enabled(text, true) do
    if not String.contains?(text, ["validate", "verify", "check"]) do
      text <>
        """

        ## Validation Requirements
        - Verify the accuracy of your response
        - Check for completeness against requirements
        - Validate logical consistency
        - Confirm adherence to any constraints
        """
    else
      text
    end
  end

  defp include_validation_if_enabled(text, _), do: text

  defp structure_output_format_if_enabled(text, true) do
    if not String.contains?(text, ["## Output", "format", "structure"]) do
      text <>
        """

        ## Output Format
        Please structure your response with:
        - Clear section headers
        - Bullet points or numbered lists where appropriate
        - Specific examples to illustrate key points
        - Summary of key findings or recommendations
        """
    else
      text
    end
  end

  defp structure_output_format_if_enabled(text, _), do: text

  defp simplify_instructions_if_enabled(text, true) do
    # Simplify complex sentence structures
    text
    |> String.replace(~r/\b(consequently|therefore|furthermore|moreover|nevertheless)\b/, "")
    |> String.replace(~r/\b(in addition to|in conjunction with)\b/, "and")
  end

  defp simplify_instructions_if_enabled(text, _), do: text

  defp reduce_examples_if_enabled(text, true) do
    # Remove excessive example phrases
    text
    |> String.replace(~r/(for instance|for example|such as)[^.]*\./, "")
    |> String.replace(~r/\n\n+/, "\n\n")
  end

  defp reduce_examples_if_enabled(text, _), do: text

  defp prioritize_essential_context_if_enabled(text, true) do
    # Keep only essential context by removing optional details
    text
    |> String.replace(~r/\((optional|note|hint)[^)]*\)/i, "")
    |> String.replace(~r/\boptionally,?\s*/, "")
  end

  defp prioritize_essential_context_if_enabled(text, _), do: text

  defp add_safety_reminders_if_enabled(text, true) do
    if not String.contains?(text, ["## Safety Guidelines", "safety", "responsible"]) do
      text <>
        """

        ## Safety Guidelines
        Please ensure your response:
        - Prioritizes user safety and well-being
        - Avoids harmful, biased, or misleading content
        - Respects privacy and confidentiality
        - Adheres to guidelines
        """
    else
      text
    end
  end

  defp add_safety_reminders_if_enabled(text, _), do: text

  defp include_ethical_guidelines_if_enabled(text, true) do
    if not String.contains?(text, ["## Ethical Considerations", "fairness", "discrimination"]) do
      text <>
        """

        ## Ethical Considerations
        - Ensure fairness and avoid discrimination
        - Respect diverse perspectives and backgrounds
        - Maintain transparency about limitations
        - Consider long-term implications of recommendations
        """
    else
      text
    end
  end

  defp include_ethical_guidelines_if_enabled(text, _), do: text

  defp add_bias_awareness_if_enabled(text, true) do
    if not String.contains?(text, [
         "## Bias Awareness",
         "Cultural and demographic",
         "algorithmic biases"
       ]) do
      text <>
        """

        ## Bias Awareness
        Please be mindful of:
        - Cultural and demographic assumptions
        - Personal or algorithmic biases
        - Limited perspectives in examples
        - Inclusive language and representation
        """
    else
      text
    end
  end

  defp add_bias_awareness_if_enabled(text, _), do: text

  defp generate_experiment_session_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
  end
end
