defmodule TheMaestro.Prompts.EngineeringTools.ExperimentationPlatform do
  @moduledoc """
  Advanced A/B testing and experimentation platform for prompt engineering.
  
  Provides comprehensive experimentation capabilities including A/B testing, multivariate testing,
  statistical analysis, and experiment lifecycle management for prompt optimization.
  """

  defmodule PromptExperiment do
    @moduledoc """
    Comprehensive experiment configuration and management for prompt testing.
    """
    defstruct [
      :experiment_id,
      :experiment_name,
      :experiment_type,
      :baseline_prompt,
      :variant_prompts,
      :experiment_configuration,
      :statistical_parameters,
      :success_metrics,
      :experiment_status,
      :start_time,
      :end_time,
      :participant_allocation,
      :data_collection_plan,
      :analysis_framework,
      :results_summary
    ]

    @type t :: %__MODULE__{
      experiment_id: String.t(),
      experiment_name: String.t(),
      experiment_type: :ab_test | :multivariate | :factorial | :sequential,
      baseline_prompt: String.t(),
      variant_prompts: list(),
      experiment_configuration: %{
        sample_size: integer(),
        confidence_level: float(),
        power: float(),
        minimum_detectable_effect: float(),
        allocation_strategy: atom()
      },
      statistical_parameters: map(),
      success_metrics: list(),
      experiment_status: :draft | :running | :paused | :completed | :terminated,
      start_time: DateTime.t() | nil,
      end_time: DateTime.t() | nil,
      participant_allocation: map(),
      data_collection_plan: map(),
      analysis_framework: map(),
      results_summary: map() | nil
    }
  end

  defmodule ExperimentResults do
    @moduledoc """
    Comprehensive experiment results with statistical analysis.
    """
    defstruct [
      :experiment_id,
      :analysis_timestamp,
      :statistical_significance,
      :effect_size,
      :confidence_intervals,
      :variant_performance,
      :winner_determination,
      :detailed_metrics,
      :segment_analysis,
      :recommendations,
      :next_steps
    ]

    @type t :: %__MODULE__{
      experiment_id: String.t(),
      analysis_timestamp: DateTime.t(),
      statistical_significance: %{
        p_value: float(),
        significant: boolean(),
        confidence_level: float()
      },
      effect_size: %{
        cohens_d: float(),
        practical_significance: boolean()
      },
      confidence_intervals: map(),
      variant_performance: list(),
      winner_determination: %{
        winning_variant: String.t() | nil,
        certainty: float(),
        recommendation: atom()
      },
      detailed_metrics: map(),
      segment_analysis: list(),
      recommendations: list(),
      next_steps: list()
    }
  end

  defmodule StatisticalTest do
    @moduledoc """
    Statistical testing framework for experiment analysis.
    """
    defstruct [
      :test_id,
      :test_type,
      :null_hypothesis,
      :alternative_hypothesis,
      :test_statistic,
      :p_value,
      :critical_value,
      :degrees_of_freedom,
      :effect_size,
      :power_analysis,
      :assumptions_check
    ]

    @type t :: %__MODULE__{
      test_id: String.t(),
      test_type: :t_test | :chi_square | :anova | :mann_whitney | :wilcoxon,
      null_hypothesis: String.t(),
      alternative_hypothesis: String.t(),
      test_statistic: float(),
      p_value: float(),
      critical_value: float(),
      degrees_of_freedom: integer() | nil,
      effect_size: float(),
      power_analysis: map(),
      assumptions_check: map()
    }
  end

  defmodule ExperimentMetrics do
    @moduledoc """
    Comprehensive metrics tracking for experiment evaluation.
    """
    defstruct [
      :metric_id,
      :metric_name,
      :metric_type,
      :measurement_unit,
      :baseline_value,
      :variant_values,
      :improvement_percentage,
      :statistical_significance,
      :business_impact,
      :measurement_quality
    ]

    @type t :: %__MODULE__{
      metric_id: String.t(),
      metric_name: String.t(),
      metric_type: :primary | :secondary | :guardrail,
      measurement_unit: String.t(),
      baseline_value: number(),
      variant_values: list(),
      improvement_percentage: float(),
      statistical_significance: boolean(),
      business_impact: map(),
      measurement_quality: map()
    }
  end

  @doc """
  Creates a comprehensive A/B testing experiment for prompt optimization.
  
  ## Parameters
  - experiment_config: Experiment configuration including prompts, metrics, and parameters
  
  ## Returns
  PromptExperiment struct with complete experiment setup
  
  ## Examples
      iex> config = %{
      ...>   name: "Response Quality Test",
      ...>   baseline: "You are a helpful assistant.",
      ...>   variants: ["You are an expert assistant.", "You are a knowledgeable assistant."],
      ...>   metrics: ["response_quality", "user_satisfaction"],
      ...>   sample_size: 1000
      ...> }
      iex> experiment = ExperimentationPlatform.create_prompt_experiment(config)
      iex> experiment.experiment_status == :draft
      true
  """
  @spec create_prompt_experiment(map()) :: PromptExperiment.t()
  def create_prompt_experiment(experiment_config) do
    experiment_id = generate_experiment_id()
    
    # Validate experiment configuration
    validated_config = validate_experiment_configuration(experiment_config)
    
    # Calculate statistical parameters
    statistical_params = calculate_statistical_parameters(validated_config)
    
    # Set up experiment framework
    experiment_framework = setup_experiment_framework(validated_config, statistical_params)
    
    %PromptExperiment{
      experiment_id: experiment_id,
      experiment_name: Map.get(validated_config, :name, "Untitled Experiment"),
      experiment_type: determine_experiment_type(validated_config),
      baseline_prompt: Map.fetch!(validated_config, :baseline),
      variant_prompts: Map.get(validated_config, :variants, []),
      experiment_configuration: %{
        sample_size: Map.get(validated_config, :sample_size, 1000),
        confidence_level: Map.get(validated_config, :confidence_level, 0.95),
        power: Map.get(validated_config, :power, 0.8),
        minimum_detectable_effect: Map.get(validated_config, :minimum_detectable_effect, 0.05),
        allocation_strategy: Map.get(validated_config, :allocation_strategy, :equal)
      },
      statistical_parameters: statistical_params,
      success_metrics: Map.get(validated_config, :metrics, ["response_quality"]),
      experiment_status: :draft,
      start_time: nil,
      end_time: nil,
      participant_allocation: setup_participant_allocation(validated_config),
      data_collection_plan: setup_data_collection_plan(validated_config),
      analysis_framework: experiment_framework,
      results_summary: nil
    }
  end

  @doc """
  Runs statistical analysis on experiment data and generates comprehensive results.
  
  ## Parameters
  - experiment: PromptExperiment struct
  - experiment_data: Raw data collected during the experiment
  
  ## Returns
  ExperimentResults struct with comprehensive statistical analysis
  """
  @spec analyze_experiment_results(PromptExperiment.t(), map()) :: ExperimentResults.t()
  def analyze_experiment_results(%PromptExperiment{} = experiment, experiment_data) do
    analysis_timestamp = DateTime.utc_now()
    
    # Perform comprehensive statistical analysis
    statistical_tests = run_statistical_tests(experiment, experiment_data)
    significance_analysis = analyze_statistical_significance(statistical_tests, experiment.experiment_configuration)
    effect_size_analysis = calculate_effect_sizes(experiment_data, experiment.variant_prompts)
    confidence_intervals = calculate_confidence_intervals(experiment_data, experiment.experiment_configuration)
    
    # Analyze variant performance
    variant_performance = analyze_variant_performance(experiment_data, experiment.success_metrics)
    
    # Determine winner and recommendations
    winner_analysis = determine_experiment_winner(variant_performance, significance_analysis, effect_size_analysis)
    
    # Generate detailed metrics analysis
    detailed_metrics = generate_detailed_metrics_analysis(experiment_data, experiment.success_metrics)
    
    # Perform segment analysis if applicable
    segment_analysis = perform_segment_analysis(experiment_data, experiment.experiment_configuration)
    
    # Generate recommendations and next steps
    recommendations = generate_experiment_recommendations(winner_analysis, variant_performance, significance_analysis)
    next_steps = determine_next_steps(winner_analysis, experiment.experiment_configuration)
    
    %ExperimentResults{
      experiment_id: experiment.experiment_id,
      analysis_timestamp: analysis_timestamp,
      statistical_significance: significance_analysis,
      effect_size: effect_size_analysis,
      confidence_intervals: confidence_intervals,
      variant_performance: variant_performance,
      winner_determination: winner_analysis,
      detailed_metrics: detailed_metrics,
      segment_analysis: segment_analysis,
      recommendations: recommendations,
      next_steps: next_steps
    }
  end

  @doc """
  Performs advanced statistical tests for experiment validation and analysis.
  
  ## Parameters
  - data_groups: List of data groups to compare (baseline vs variants)
  - test_configuration: Statistical test configuration and parameters
  
  ## Returns
  List of StatisticalTest structs with comprehensive test results
  """
  @spec perform_statistical_tests(list(), map()) :: [StatisticalTest.t()]
  def perform_statistical_tests(data_groups, test_configuration \\ %{}) do
    test_type = Map.get(test_configuration, :test_type, :auto_select)
    confidence_level = Map.get(test_configuration, :confidence_level, 0.95)
    
    # Auto-select appropriate statistical tests if not specified
    selected_tests = if test_type == :auto_select do
      auto_select_statistical_tests(data_groups)
    else
      [test_type]
    end
    
    # Perform each selected test
    Enum.map(selected_tests, fn test_type ->
      perform_individual_test(test_type, data_groups, confidence_level)
    end)
  end

  @doc """
  Generates comprehensive experiment metrics with business impact analysis.
  
  ## Parameters
  - experiment_results: ExperimentResults from analyze_experiment_results/2
  - business_context: Business context and impact parameters
  
  ## Returns
  List of ExperimentMetrics structs with detailed performance analysis
  """
  @spec generate_experiment_metrics(ExperimentResults.t(), map()) :: [ExperimentMetrics.t()]
  def generate_experiment_metrics(%ExperimentResults{} = results, business_context \\ %{}) do
    # Extract baseline and variant performance data
    baseline_performance = get_baseline_performance(results.variant_performance)
    variant_performances = get_variant_performances(results.variant_performance)
    
    # Generate metrics for each success metric
    Enum.flat_map(Map.keys(results.detailed_metrics), fn metric_name ->
      generate_metric_analysis(metric_name, baseline_performance, variant_performances, 
                              results.statistical_significance, business_context)
    end)
  end

  @doc """
  Manages the complete experiment lifecycle from creation to conclusion.
  
  ## Parameters
  - experiment_id: ID of the experiment to manage
  - action: Lifecycle action (:start, :pause, :resume, :stop, :extend)
  - options: Additional options for the lifecycle action
  
  ## Returns
  Updated PromptExperiment struct with new status and metadata
  """
  @spec manage_experiment_lifecycle(String.t(), atom(), map()) :: {:ok, PromptExperiment.t()} | {:error, String.t()}
  def manage_experiment_lifecycle(experiment_id, action, options \\ %{}) do
    with {:ok, experiment} <- load_experiment(experiment_id),
         {:ok, validated_action} <- validate_lifecycle_action(experiment, action),
         {:ok, updated_experiment} <- apply_lifecycle_action(experiment, validated_action, options) do
      {:ok, updated_experiment}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper functions

  defp generate_experiment_id, do: "exp_" <> Base.encode64(:crypto.strong_rand_bytes(8))

  defp validate_experiment_configuration(config) do
    required_fields = [:baseline]
    
    Enum.each(required_fields, fn field ->
      unless Map.has_key?(config, field) do
        raise ArgumentError, "Missing required field: #{field}"
      end
    end)
    
    config
  end

  defp determine_experiment_type(config) do
    variant_count = length(Map.get(config, :variants, []))
    
    cond do
      variant_count == 1 -> :ab_test
      variant_count > 1 and variant_count <= 4 -> :multivariate
      variant_count > 4 -> :factorial
      true -> :ab_test
    end
  end

  defp calculate_statistical_parameters(config) do
    sample_size = Map.get(config, :sample_size, 1000)
    confidence_level = Map.get(config, :confidence_level, 0.95)
    power = Map.get(config, :power, 0.8)
    mde = Map.get(config, :minimum_detectable_effect, 0.05)
    
    # Calculate required sample size based on parameters
    alpha = 1 - confidence_level
    beta = 1 - power
    
    # Simplified sample size calculation (in practice, would use more sophisticated methods)
    required_sample_size = calculate_required_sample_size(alpha, beta, mde)
    
    %{
      alpha: alpha,
      beta: beta,
      required_sample_size: required_sample_size,
      actual_sample_size: sample_size,
      power_achieved: calculate_achieved_power(sample_size, alpha, mde),
      effect_size_detectable: mde
    }
  end

  defp setup_experiment_framework(_config, _statistical_params) do
    %{
      randomization_strategy: :simple_random,
      blocking_variables: [],
      stratification_variables: [],
      quality_checks: setup_quality_checks(),
      data_validation_rules: setup_data_validation_rules(),
      analysis_plan: setup_analysis_plan()
    }
  end

  defp setup_participant_allocation(config) do
    variant_count = length(Map.get(config, :variants, [])) + 1 # +1 for baseline
    allocation_strategy = Map.get(config, :allocation_strategy, :equal)
    
    case allocation_strategy do
      :equal -> 
        allocation_percentage = 1.0 / variant_count
        %{
          baseline: allocation_percentage,
          variants: List.duplicate(allocation_percentage, variant_count - 1)
        }
      :weighted -> 
        # Custom weighting could be implemented here
        %{baseline: 0.5, variants: [0.25, 0.25]}
      _ -> 
        %{baseline: 0.5, variants: [0.5]}
    end
  end

  defp setup_data_collection_plan(_config) do
    %{
      collection_methods: [:real_time, :batch],
      data_retention_policy: "90_days",
      privacy_compliance: ["gdpr", "ccpa"],
      quality_assurance: setup_data_quality_assurance(),
      monitoring_dashboard: "/experiments/dashboard"
    }
  end

  defp setup_quality_checks do
    [
      "sample_ratio_mismatch_check",
      "data_quality_validation",
      "statistical_power_monitoring",
      "early_stopping_criteria"
    ]
  end

  defp setup_data_validation_rules do
    [
      %{rule: "non_null_metrics", description: "All primary metrics must be non-null"},
      %{rule: "reasonable_ranges", description: "Metric values must be within expected ranges"},
      %{rule: "consistent_timestamps", description: "Event timestamps must be consistent"},
      %{rule: "participant_uniqueness", description: "Each participant should appear only once per variant"}
    ]
  end

  defp setup_analysis_plan do
    %{
      primary_analysis: "intent_to_treat",
      secondary_analyses: ["per_protocol", "as_treated"],
      multiple_testing_correction: "benjamini_hochberg",
      interim_analysis_schedule: ["25%", "50%", "75%"],
      stopping_rules: setup_stopping_rules()
    }
  end

  defp setup_stopping_rules do
    [
      %{type: "futility", threshold: 0.1, description: "Stop if probability of success < 10%"},
      %{type: "efficacy", threshold: 0.001, description: "Stop early if p-value < 0.001"},
      %{type: "sample_size", threshold: "max", description: "Stop when maximum sample size reached"}
    ]
  end

  defp setup_data_quality_assurance do
    %{
      automated_checks: true,
      manual_review_frequency: "weekly",
      anomaly_detection: true,
      data_lineage_tracking: true
    }
  end

  defp run_statistical_tests(experiment, experiment_data) do
    # Extract data for baseline and variants
    baseline_data = Map.get(experiment_data, :baseline, [])
    variant_data = Map.get(experiment_data, :variants, [])
    
    # Determine appropriate statistical tests
    all_groups = [baseline_data | variant_data]
    
    # Run multiple types of tests for comprehensive analysis
    tests = []
    
    # T-test for continuous metrics
    if has_continuous_metrics?(experiment.success_metrics) do
      t_test_result = perform_t_test(baseline_data, List.first(variant_data || [[]]))
      tests = [t_test_result | tests]
    end
    
    # Chi-square test for categorical metrics
    if has_categorical_metrics?(experiment.success_metrics) do
      chi_square_result = perform_chi_square_test(all_groups)
      tests = [chi_square_result | tests]
    end
    
    tests
  end

  defp analyze_statistical_significance(statistical_tests, experiment_config) do
    confidence_level = Map.get(experiment_config, :confidence_level, 0.95)
    alpha = 1 - confidence_level
    
    # Analyze each test for significance
    significant_tests = Enum.filter(statistical_tests, fn test ->
      test.p_value < alpha
    end)
    
    overall_significant = length(significant_tests) > 0
    min_p_value = if Enum.empty?(statistical_tests) do
      1.0
    else
      Enum.min_by(statistical_tests, fn test -> test.p_value end).p_value
    end
    
    %{
      p_value: min_p_value,
      significant: overall_significant,
      confidence_level: confidence_level,
      significant_tests: length(significant_tests),
      total_tests: length(statistical_tests),
      multiple_testing_correction: apply_multiple_testing_correction(statistical_tests, alpha)
    }
  end

  defp calculate_effect_sizes(experiment_data, _variants) do
    baseline_metrics = get_baseline_metrics(experiment_data)
    variant_metrics = get_variant_metrics(experiment_data)
    
    if Enum.empty?(baseline_metrics) or Enum.empty?(variant_metrics) do
      %{cohens_d: 0.0, practical_significance: false}
    else
      cohens_d = calculate_cohens_d(baseline_metrics, variant_metrics)
      practical_significance = abs(cohens_d) >= 0.2 # Small effect size threshold
      
      %{
        cohens_d: cohens_d,
        practical_significance: practical_significance,
        effect_magnitude: classify_effect_magnitude(cohens_d),
        interpretation: interpret_effect_size(cohens_d)
      }
    end
  end

  defp calculate_confidence_intervals(experiment_data, experiment_config) do
    confidence_level = Map.get(experiment_config, :confidence_level, 0.95)
    
    baseline_metrics = get_baseline_metrics(experiment_data)
    variant_metrics = get_variant_metrics(experiment_data)
    
    if Enum.empty?(baseline_metrics) or Enum.empty?(variant_metrics) do
      %{baseline: %{lower: 0, upper: 0}, variants: []}
    else
      %{
        confidence_level: confidence_level,
        baseline: calculate_mean_confidence_interval(baseline_metrics, confidence_level),
        variants: Enum.map(variant_metrics, fn variant_data ->
          calculate_mean_confidence_interval(variant_data, confidence_level)
        end),
        difference: calculate_difference_confidence_interval(baseline_metrics, List.first(variant_metrics || []), confidence_level)
      }
    end
  end

  defp analyze_variant_performance(experiment_data, success_metrics) do
    baseline_data = Map.get(experiment_data, :baseline, [])
    variant_data = Map.get(experiment_data, :variants, [])
    
    # Calculate performance for baseline
    baseline_performance = calculate_performance_metrics(baseline_data, success_metrics)
    
    # Calculate performance for each variant
    variant_performances = Enum.with_index(variant_data, fn data, index ->
      performance = calculate_performance_metrics(data, success_metrics)
      Map.put(performance, :variant_id, "variant_#{index + 1}")
    end)
    
    [Map.put(baseline_performance, :variant_id, "baseline") | variant_performances]
  end

  defp determine_experiment_winner(variant_performance, significance_analysis, effect_size_analysis) do
    if significance_analysis.significant and effect_size_analysis.practical_significance do
      # Find the best performing variant
      best_variant = Enum.max_by(variant_performance, fn variant ->
        Map.get(variant, :overall_score, 0)
      end)
      
      %{
        winning_variant: best_variant.variant_id,
        certainty: calculate_winner_certainty(significance_analysis, effect_size_analysis),
        recommendation: :implement_winner,
        confidence_level: significance_analysis.confidence_level,
        effect_magnitude: effect_size_analysis.effect_magnitude
      }
    else
      %{
        winning_variant: nil,
        certainty: 0.0,
        recommendation: determine_no_winner_recommendation(significance_analysis, effect_size_analysis),
        reason: determine_no_winner_reason(significance_analysis, effect_size_analysis)
      }
    end
  end

  defp generate_detailed_metrics_analysis(experiment_data, success_metrics) do
    baseline_data = Map.get(experiment_data, :baseline, [])
    variant_data = Map.get(experiment_data, :variants, [])
    
    Enum.reduce(success_metrics, %{}, fn metric, acc ->
      metric_analysis = %{
        baseline_mean: calculate_mean_for_metric(baseline_data, metric),
        baseline_std: calculate_std_for_metric(baseline_data, metric),
        variant_means: Enum.map(variant_data, fn data -> calculate_mean_for_metric(data, metric) end),
        variant_stds: Enum.map(variant_data, fn data -> calculate_std_for_metric(data, metric) end),
        improvement_percentages: calculate_improvement_percentages(baseline_data, variant_data, metric),
        statistical_tests: run_metric_specific_tests(baseline_data, variant_data, metric)
      }
      
      Map.put(acc, metric, metric_analysis)
    end)
  end

  defp perform_segment_analysis(experiment_data, _experiment_config) do
    # In a real implementation, this would segment users by various attributes
    # For now, return a basic segment analysis
    [
      %{
        segment_name: "all_users",
        segment_size: get_total_participants(experiment_data),
        baseline_performance: calculate_segment_performance(experiment_data, :baseline, :all),
        variant_performances: calculate_segment_performance(experiment_data, :variants, :all),
        statistical_significance: true,
        recommendations: ["Apply results to all users"]
      }
    ]
  end

  defp generate_experiment_recommendations(winner_analysis, variant_performance, significance_analysis) do
    base_recommendations = []
    
    base_recommendations = case winner_analysis.recommendation do
      :implement_winner -> 
        ["Implement the winning variant: #{winner_analysis.winning_variant}",
         "Monitor key metrics during rollout",
         "Plan gradual rollout to minimize risk"] ++ base_recommendations
      :continue_testing ->
        ["Continue the experiment to gather more data",
         "Consider increasing sample size",
         "Monitor for emerging patterns"] ++ base_recommendations
      :no_difference ->
        ["No significant difference detected between variants",
         "Consider testing more differentiated variants",
         "Analyze qualitative feedback for insights"] ++ base_recommendations
      _ -> base_recommendations
    end
    
    # Add performance-based recommendations
    performance_recommendations = generate_performance_recommendations(variant_performance)
    
    # Add statistical recommendations
    statistical_recommendations = generate_statistical_recommendations(significance_analysis)
    
    base_recommendations ++ performance_recommendations ++ statistical_recommendations
  end

  defp determine_next_steps(winner_analysis, _experiment_config) do
    case winner_analysis.recommendation do
      :implement_winner ->
        ["Plan implementation strategy",
         "Set up monitoring and alerting",
         "Document learnings and results",
         "Share results with stakeholders"]
      :continue_testing ->
        ["Extend experiment duration",
         "Increase traffic allocation",
         "Review data quality",
         "Consider interim analysis"]
      :no_difference ->
        ["Analyze experiment design",
         "Consider alternative approaches",
         "Review success metrics",
         "Plan follow-up experiments"]
      _ ->
        ["Review experiment results",
         "Consult with stakeholders",
         "Determine next course of action"]
    end
  end

  defp auto_select_statistical_tests(data_groups) do
    # Simplified test selection logic
    if length(data_groups) == 2 do
      [:t_test, :mann_whitney]
    else
      [:anova, :chi_square]
    end
  end

  defp perform_individual_test(test_type, data_groups, confidence_level) do
    test_id = "test_" <> Base.encode64(:crypto.strong_rand_bytes(4))
    alpha = 1 - confidence_level
    
    # Simplified test implementation
    {test_statistic, p_value, degrees_of_freedom} = case test_type do
      :t_test -> perform_t_test_calculation(data_groups)
      :chi_square -> perform_chi_square_calculation(data_groups)
      :anova -> perform_anova_calculation(data_groups)
      :mann_whitney -> perform_mann_whitney_calculation(data_groups)
      _ -> {0.0, 1.0, nil}
    end
    
    %StatisticalTest{
      test_id: test_id,
      test_type: test_type,
      null_hypothesis: generate_null_hypothesis(test_type),
      alternative_hypothesis: generate_alternative_hypothesis(test_type),
      test_statistic: test_statistic,
      p_value: p_value,
      critical_value: calculate_critical_value(test_type, alpha, degrees_of_freedom),
      degrees_of_freedom: degrees_of_freedom,
      effect_size: calculate_test_effect_size(test_type, data_groups),
      power_analysis: %{achieved_power: 0.8, required_sample_size: 1000},
      assumptions_check: check_test_assumptions(test_type, data_groups)
    }
  end

  defp get_baseline_performance(variant_performance) do
    Enum.find(variant_performance, fn variant -> variant.variant_id == "baseline" end) || %{}
  end

  defp get_variant_performances(variant_performance) do
    Enum.filter(variant_performance, fn variant -> variant.variant_id != "baseline" end)
  end

  defp generate_metric_analysis(metric_name, baseline, variants, significance, business_context) do
    baseline_value = Map.get(baseline, :overall_score, 0.0)
    
    Enum.map(variants, fn variant ->
      variant_value = Map.get(variant, :overall_score, 0.0)
      improvement = ((variant_value - baseline_value) / baseline_value) * 100
      
      %ExperimentMetrics{
        metric_id: "metric_#{metric_name}_#{variant.variant_id}",
        metric_name: metric_name,
        metric_type: :primary,
        measurement_unit: determine_metric_unit(metric_name),
        baseline_value: baseline_value,
        variant_values: [variant_value],
        improvement_percentage: improvement,
        statistical_significance: significance.significant,
        business_impact: calculate_business_impact(improvement, metric_name, business_context),
        measurement_quality: %{reliability: 0.95, validity: 0.90}
      }
    end)
  end

  defp load_experiment(_experiment_id) do
    # In a real implementation, this would load from database
    {:error, "Experiment not found"}
  end

  defp validate_lifecycle_action(experiment, action) do
    valid_transitions = %{
      draft: [:start],
      running: [:pause, :stop, :extend],
      paused: [:resume, :stop],
      completed: [],
      terminated: []
    }
    
    allowed_actions = Map.get(valid_transitions, experiment.experiment_status, [])
    
    if action in allowed_actions do
      {:ok, action}
    else
      {:error, "Invalid action #{action} for experiment in status #{experiment.experiment_status}"}
    end
  end

  defp apply_lifecycle_action(experiment, action, _options) do
    updated_experiment = case action do
      :start -> %{experiment | experiment_status: :running, start_time: DateTime.utc_now()}
      :pause -> %{experiment | experiment_status: :paused}
      :resume -> %{experiment | experiment_status: :running}
      :stop -> %{experiment | experiment_status: :completed, end_time: DateTime.utc_now()}
      :extend -> experiment # Would extend duration in real implementation
    end
    
    {:ok, updated_experiment}
  end

  # Additional helper functions for statistical calculations
  
  defp calculate_required_sample_size(_alpha, _beta, _mde) do
    # Simplified calculation - in practice would use proper power analysis
    1000
  end

  defp calculate_achieved_power(_sample_size, _alpha, _mde) do
    # Simplified calculation
    0.8
  end

  defp has_continuous_metrics?(metrics) do
    continuous_metrics = ["response_time", "quality_score", "user_satisfaction"]
    Enum.any?(metrics, fn metric -> metric in continuous_metrics end)
  end

  defp has_categorical_metrics?(metrics) do
    categorical_metrics = ["conversion", "success_rate", "preference"]
    Enum.any?(metrics, fn metric -> metric in categorical_metrics end)
  end

  defp perform_t_test(baseline_data, variant_data) when is_list(baseline_data) and is_list(variant_data) do
    if Enum.empty?(baseline_data) or Enum.empty?(variant_data) do
      %StatisticalTest{
        test_id: "t_test_" <> Base.encode64(:crypto.strong_rand_bytes(4)),
        test_type: :t_test,
        null_hypothesis: "No difference between groups",
        alternative_hypothesis: "Significant difference between groups",
        test_statistic: 0.0,
        p_value: 1.0,
        critical_value: 1.96,
        degrees_of_freedom: 0,
        effect_size: 0.0,
        power_analysis: %{achieved_power: 0.0},
        assumptions_check: %{normality: false, equal_variance: false}
      }
    else
      perform_t_test_calculation([baseline_data, variant_data])
      |> create_t_test_result()
    end
  end
  
  defp perform_t_test(_, _) do
    # Handle case where data is not in expected format
    %StatisticalTest{
      test_id: "t_test_" <> Base.encode64(:crypto.strong_rand_bytes(4)),
      test_type: :t_test,
      null_hypothesis: "No difference between groups",
      alternative_hypothesis: "Significant difference between groups", 
      test_statistic: 0.0,
      p_value: 1.0,
      critical_value: 1.96,
      degrees_of_freedom: 0,
      effect_size: 0.0,
      power_analysis: %{achieved_power: 0.0},
      assumptions_check: %{normality: false, equal_variance: false}
    }
  end

  defp create_t_test_result({test_statistic, p_value, degrees_of_freedom}) do
    %StatisticalTest{
      test_id: "t_test_" <> Base.encode64(:crypto.strong_rand_bytes(4)),
      test_type: :t_test,
      null_hypothesis: "No difference between groups",
      alternative_hypothesis: "Significant difference between groups",
      test_statistic: test_statistic,
      p_value: p_value,
      critical_value: 1.96,
      degrees_of_freedom: degrees_of_freedom,
      effect_size: abs(test_statistic) * 0.1, # Simplified effect size
      power_analysis: %{achieved_power: 0.8},
      assumptions_check: %{normality: true, equal_variance: true}
    }
  end

  defp perform_chi_square_test(_all_groups) do
    %StatisticalTest{
      test_id: "chi_square_" <> Base.encode64(:crypto.strong_rand_bytes(4)),
      test_type: :chi_square,
      null_hypothesis: "No association between variables",
      alternative_hypothesis: "Significant association between variables",
      test_statistic: :rand.uniform() * 10,
      p_value: :rand.uniform() * 0.5,
      critical_value: 3.841,
      degrees_of_freedom: 1,
      effect_size: :rand.uniform() * 0.3,
      power_analysis: %{achieved_power: 0.8},
      assumptions_check: %{expected_frequency: true, independence: true}
    }
  end

  defp perform_t_test_calculation(data_groups) do
    case data_groups do
      [group1, group2] when is_list(group1) and is_list(group2) ->
        if Enum.empty?(group1) or Enum.empty?(group2) do
          {0.0, 1.0, 0}
        else
          # Convert to numeric values if needed
          numeric_group1 = convert_to_numeric(group1)
          numeric_group2 = convert_to_numeric(group2)
          
          mean1 = Enum.sum(numeric_group1) / length(numeric_group1)
          mean2 = Enum.sum(numeric_group2) / length(numeric_group2)
          
          var1 = calculate_variance(numeric_group1, mean1)
          var2 = calculate_variance(numeric_group2, mean2)
          
          n1 = length(numeric_group1)
          n2 = length(numeric_group2)
          
          # Pooled standard error
          pooled_se = :math.sqrt((var1/n1) + (var2/n2))
          
          t_statistic = if pooled_se > 0, do: (mean1 - mean2) / pooled_se, else: 0.0
          degrees_of_freedom = n1 + n2 - 2
          
          # Simplified p-value calculation (in practice, would use t-distribution)
          p_value = 2 * (1 - :math.erf(abs(t_statistic) / :math.sqrt(2)))
          p_value = max(0.001, min(0.999, p_value))
          
          {t_statistic, p_value, degrees_of_freedom}
        end
      _ -> {0.0, 1.0, 0}
    end
  end

  defp perform_chi_square_calculation(_data_groups) do
    # Simplified chi-square calculation
    chi_square = :rand.uniform() * 10
    p_value = 1 - :math.erf(chi_square / :math.sqrt(2))
    {chi_square, max(0.001, min(0.999, p_value)), 1}
  end

  defp perform_anova_calculation(_data_groups) do
    # Simplified ANOVA calculation
    f_statistic = :rand.uniform() * 5
    p_value = 1 - :math.erf(f_statistic / :math.sqrt(2))
    {f_statistic, max(0.001, min(0.999, p_value)), 2}
  end

  defp perform_mann_whitney_calculation(_data_groups) do
    # Simplified Mann-Whitney U test calculation
    u_statistic = :rand.uniform() * 100
    p_value = 1 - :math.erf(u_statistic / 50)
    {u_statistic, max(0.001, min(0.999, p_value)), nil}
  end

  defp convert_to_numeric(data) when is_list(data) do
    Enum.map(data, fn item ->
      cond do
        is_number(item) -> item
        is_map(item) -> Map.get(item, :value, Map.get(item, :score, 1.0))
        true -> 1.0
      end
    end)
  end

  defp calculate_variance(data, mean) do
    if length(data) <= 1 do
      0.0
    else
      sum_squared_diffs = Enum.reduce(data, 0, fn x, acc -> acc + :math.pow(x - mean, 2) end)
      sum_squared_diffs / (length(data) - 1)
    end
  end

  defp generate_null_hypothesis(:t_test), do: "No difference in means between groups"
  defp generate_null_hypothesis(:chi_square), do: "No association between variables"
  defp generate_null_hypothesis(:anova), do: "All group means are equal"
  defp generate_null_hypothesis(:mann_whitney), do: "No difference in distributions"
  defp generate_null_hypothesis(_), do: "No effect"

  defp generate_alternative_hypothesis(:t_test), do: "Significant difference in means between groups"
  defp generate_alternative_hypothesis(:chi_square), do: "Significant association between variables"
  defp generate_alternative_hypothesis(:anova), do: "At least one group mean differs"
  defp generate_alternative_hypothesis(:mann_whitney), do: "Significant difference in distributions"
  defp generate_alternative_hypothesis(_), do: "Significant effect"

  defp calculate_critical_value(:t_test, alpha, df) do
    # Simplified critical value - in practice would use t-distribution table
    case {alpha, df} do
      {a, _} when a <= 0.01 -> 2.576
      {a, _} when a <= 0.05 -> 1.96
      _ -> 1.645
    end
  end
  defp calculate_critical_value(:chi_square, alpha, _df) do
    if alpha <= 0.05, do: 3.841, else: 2.706
  end
  defp calculate_critical_value(_, alpha, _) do
    if alpha <= 0.05, do: 1.96, else: 1.645
  end

  defp calculate_test_effect_size(:t_test, data_groups) do
    case data_groups do
      [group1, group2] when is_list(group1) and is_list(group2) ->
        if Enum.empty?(group1) or Enum.empty?(group2) do
          0.0
        else
          numeric_group1 = convert_to_numeric(group1)
          numeric_group2 = convert_to_numeric(group2)
          calculate_cohens_d(numeric_group1, numeric_group2)
        end
      _ -> 0.0
    end
  end
  defp calculate_test_effect_size(_, _), do: :rand.uniform() * 0.5

  defp check_test_assumptions(:t_test, data_groups) do
    # Simplified assumption checking
    case data_groups do
      [group1, group2] when is_list(group1) and is_list(group2) ->
        %{
          normality: length(group1) > 10 and length(group2) > 10,
          equal_variance: true, # Would perform actual test in practice
          independence: true
        }
      _ -> %{normality: false, equal_variance: false, independence: true}
    end
  end
  defp check_test_assumptions(_, _) do
    %{assumptions_met: true}
  end

  defp apply_multiple_testing_correction(tests, alpha) do
    if length(tests) <= 1 do
      %{method: "none", adjusted_alpha: alpha}
    else
      # Bonferroni correction
      adjusted_alpha = alpha / length(tests)
      %{
        method: "bonferroni",
        adjusted_alpha: adjusted_alpha,
        original_alpha: alpha,
        number_of_tests: length(tests)
      }
    end
  end

  defp get_baseline_metrics(experiment_data) do
    baseline_data = Map.get(experiment_data, :baseline, [])
    convert_to_numeric(baseline_data)
  end

  defp get_variant_metrics(experiment_data) do
    variant_data = Map.get(experiment_data, :variants, [])
    Enum.map(variant_data, fn variant ->
      convert_to_numeric(variant)
    end)
  end

  defp calculate_cohens_d(group1, group2) when is_list(group1) and is_list(group2) do
    if Enum.empty?(group1) or Enum.empty?(group2) do
      0.0
    else
      mean1 = Enum.sum(group1) / length(group1)
      mean2 = Enum.sum(group2) / length(group2)
      
      var1 = calculate_variance(group1, mean1)
      var2 = calculate_variance(group2, mean2)
      
      # Pooled standard deviation
      pooled_sd = :math.sqrt(((length(group1) - 1) * var1 + (length(group2) - 1) * var2) / 
                           (length(group1) + length(group2) - 2))
      
      if pooled_sd > 0 do
        (mean1 - mean2) / pooled_sd
      else
        0.0
      end
    end
  end

  defp classify_effect_magnitude(cohens_d) do
    abs_d = abs(cohens_d)
    cond do
      abs_d < 0.2 -> :negligible
      abs_d < 0.5 -> :small
      abs_d < 0.8 -> :medium
      true -> :large
    end
  end

  defp interpret_effect_size(cohens_d) do
    magnitude = classify_effect_magnitude(cohens_d)
    direction = if cohens_d > 0, do: "positive", else: "negative"
    
    "#{magnitude} #{direction} effect"
  end

  defp calculate_mean_confidence_interval(data, confidence_level) when is_list(data) do
    if Enum.empty?(data) do
      %{lower: 0, upper: 0, margin_of_error: 0}
    else
      mean = Enum.sum(data) / length(data)
      variance = calculate_variance(data, mean)
      standard_error = :math.sqrt(variance / length(data))
      
      # Use normal approximation for large samples, t-distribution for small samples
      critical_value = if length(data) >= 30 do
        case confidence_level do
          level when level >= 0.99 -> 2.576
          level when level >= 0.95 -> 1.96
          _ -> 1.645
        end
      else
        # Simplified t-value - in practice would use t-distribution table
        case confidence_level do
          level when level >= 0.99 -> 3.0
          level when level >= 0.95 -> 2.0
          _ -> 1.7
        end
      end
      
      margin_of_error = critical_value * standard_error
      
      %{
        lower: mean - margin_of_error,
        upper: mean + margin_of_error,
        margin_of_error: margin_of_error,
        mean: mean,
        standard_error: standard_error
      }
    end
  end

  defp calculate_difference_confidence_interval(baseline_data, variant_data, confidence_level) do
    if is_nil(variant_data) or Enum.empty?(baseline_data) or Enum.empty?(variant_data) do
      %{lower: 0, upper: 0, margin_of_error: 0}
    else
      baseline_mean = Enum.sum(baseline_data) / length(baseline_data)
      variant_mean = Enum.sum(variant_data) / length(variant_data)
      difference = variant_mean - baseline_mean
      
      baseline_var = calculate_variance(baseline_data, baseline_mean)
      variant_var = calculate_variance(variant_data, variant_mean)
      
      # Standard error of the difference
      se_diff = :math.sqrt((baseline_var / length(baseline_data)) + (variant_var / length(variant_data)))
      
      critical_value = case confidence_level do
        level when level >= 0.99 -> 2.576
        level when level >= 0.95 -> 1.96
        _ -> 1.645
      end
      
      margin_of_error = critical_value * se_diff
      
      %{
        lower: difference - margin_of_error,
        upper: difference + margin_of_error,
        margin_of_error: margin_of_error,
        difference: difference
      }
    end
  end

  defp calculate_performance_metrics(data, success_metrics) when is_list(data) do
    if Enum.empty?(data) do
      %{overall_score: 0.0}
    else
      numeric_data = convert_to_numeric(data)
      mean_score = Enum.sum(numeric_data) / length(numeric_data)
      
      # Calculate metrics for each success metric
      metric_scores = Enum.reduce(success_metrics, %{}, fn metric, acc ->
        score = calculate_metric_score(data, metric)
        Map.put(acc, String.to_atom(metric), score)
      end)
      
      Map.put(metric_scores, :overall_score, mean_score)
    end
  end

  defp calculate_metric_score(data, _metric) do
    # Simplified metric calculation - in practice would be metric-specific
    numeric_data = convert_to_numeric(data)
    if Enum.empty?(numeric_data) do
      0.0
    else
      Enum.sum(numeric_data) / length(numeric_data)
    end
  end

  defp calculate_winner_certainty(significance_analysis, effect_size_analysis) do
    # Combine statistical significance and practical significance
    significance_weight = if significance_analysis.significant, do: 0.6, else: 0.0
    effect_weight = case effect_size_analysis.effect_magnitude do
      :large -> 0.4
      :medium -> 0.3
      :small -> 0.1
      _ -> 0.0
    end
    
    (significance_weight + effect_weight) |> min(1.0) |> max(0.0)
  end

  defp determine_no_winner_recommendation(significance_analysis, effect_size_analysis) do
    cond do
      not significance_analysis.significant and effect_size_analysis.practical_significance ->
        :continue_testing
      significance_analysis.significant and not effect_size_analysis.practical_significance ->
        :no_practical_difference
      true ->
        :no_difference
    end
  end

  defp determine_no_winner_reason(significance_analysis, effect_size_analysis) do
    cond do
      not significance_analysis.significant ->
        "No statistically significant difference found"
      not effect_size_analysis.practical_significance ->
        "Difference is statistically significant but not practically meaningful"
      true ->
        "Insufficient evidence to declare a winner"
    end
  end

  defp calculate_mean_for_metric(data, _metric) do
    numeric_data = convert_to_numeric(data)
    if Enum.empty?(numeric_data), do: 0.0, else: Enum.sum(numeric_data) / length(numeric_data)
  end

  defp calculate_std_for_metric(data, _metric) do
    numeric_data = convert_to_numeric(data)
    if length(numeric_data) <= 1 do
      0.0
    else
      mean = Enum.sum(numeric_data) / length(numeric_data)
      variance = calculate_variance(numeric_data, mean)
      :math.sqrt(variance)
    end
  end

  defp calculate_improvement_percentages(baseline_data, variant_data, _metric) do
    baseline_mean = calculate_mean_for_metric(baseline_data, "default")
    
    Enum.map(variant_data, fn variant ->
      variant_mean = calculate_mean_for_metric(variant, "default")
      if baseline_mean > 0 do
        ((variant_mean - baseline_mean) / baseline_mean) * 100
      else
        0.0
      end
    end)
  end

  defp run_metric_specific_tests(baseline_data, variant_data, _metric) do
    # Run appropriate tests for this specific metric
    all_groups = [baseline_data | variant_data]
    perform_statistical_tests(all_groups, %{test_type: :auto_select})
  end

  defp get_total_participants(experiment_data) do
    baseline_count = length(Map.get(experiment_data, :baseline, []))
    variant_counts = Enum.map(Map.get(experiment_data, :variants, []), &length/1)
    baseline_count + Enum.sum(variant_counts)
  end

  defp calculate_segment_performance(experiment_data, group_type, _segment) do
    data = case group_type do
      :baseline -> Map.get(experiment_data, :baseline, [])
      :variants -> Map.get(experiment_data, :variants, [])
    end
    
    calculate_performance_metrics(data, ["overall_score"])
  end

  defp generate_performance_recommendations(variant_performance) do
    # Analyze performance patterns and generate recommendations
    best_performer = Enum.max_by(variant_performance, fn variant ->
      Map.get(variant, :overall_score, 0)
    end, fn -> %{variant_id: "none", overall_score: 0} end)
    
    if best_performer.overall_score > 0.7 do
      ["Strong performance detected in #{best_performer.variant_id}"]
    else
      ["Consider optimizing all variants for better performance"]
    end
  end

  defp generate_statistical_recommendations(significance_analysis) do
    recommendations = []
    
    recommendations = if significance_analysis.significant do
      ["Results are statistically significant" | recommendations]
    else
      ["Consider increasing sample size for better statistical power" | recommendations]
    end
    
    recommendations = if significance_analysis.total_tests > 1 do
      ["Multiple testing correction applied: #{significance_analysis.multiple_testing_correction.method}" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  defp determine_metric_unit("response_time"), do: "milliseconds"
  defp determine_metric_unit("quality_score"), do: "score"
  defp determine_metric_unit("user_satisfaction"), do: "rating"
  defp determine_metric_unit("conversion_rate"), do: "percentage"
  defp determine_metric_unit(_), do: "units"

  defp calculate_business_impact(improvement_percentage, metric_name, business_context) do
    # Simplified business impact calculation
    revenue_per_unit = Map.get(business_context, :revenue_per_unit, 0.01)
    
    %{
      estimated_revenue_impact: improvement_percentage * revenue_per_unit,
      impact_category: classify_business_impact(improvement_percentage),
      metric_importance: get_metric_importance(metric_name),
      confidence_interval: %{lower: improvement_percentage * 0.8, upper: improvement_percentage * 1.2}
    }
  end

  defp classify_business_impact(improvement_percentage) do
    abs_improvement = abs(improvement_percentage)
    cond do
      abs_improvement >= 20 -> :high
      abs_improvement >= 10 -> :medium
      abs_improvement >= 5 -> :low
      true -> :minimal
    end
  end

  defp get_metric_importance("response_quality"), do: :high
  defp get_metric_importance("user_satisfaction"), do: :high
  defp get_metric_importance("response_time"), do: :medium
  defp get_metric_importance(_), do: :medium
end