defmodule TheMaestro.Prompts.Optimization.Structs do
  @moduledoc """
  Data structures for provider-specific prompt optimization.
  """

  defmodule OptimizationContext do
    @moduledoc """
    Context structure containing all information needed for provider-specific optimization.
    """
    
    @enforce_keys [:enhanced_prompt, :provider_info]
    defstruct [
      :enhanced_prompt,
      :provider_info,
      :model_capabilities,
      :optimization_targets,
      :performance_constraints,
      :quality_requirements,
      :available_tools,
      optimization_applied: false,
      optimization_score: 0.0,
      validation_passed: false,
      # Provider-specific optimization flags
      reasoning_enhanced: false,
      structured_thinking_applied: false,
      safety_optimized: false,
      claude_formatted: false,
      multimodal_optimized: false,
      function_calling_optimized: false,
      code_generation_optimized: false,
      large_context_leveraged: false,
      google_services_integrated: false,
      gemini_formatted: false,
      gemini_optimized: false,
      consistent_reasoning_optimized: false,
      structured_output_enhanced: false,
      api_reliability_optimized: false,
      language_capabilities_leveraged: false,
      creative_analytical_balanced: false,
      openai_formatted: false,
      openai_optimized: false,
      large_context_optimized: false
    ]

    @type t :: %__MODULE__{
      enhanced_prompt: TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt.t(),
      provider_info: map(),
      model_capabilities: ModelCapabilities.t() | nil,
      optimization_targets: OptimizationTargets.t() | nil,
      performance_constraints: map() | nil,
      quality_requirements: map() | nil,
      available_tools: list() | nil,
      optimization_applied: boolean(),
      optimization_score: float(),
      validation_passed: boolean(),
      reasoning_enhanced: boolean(),
      structured_thinking_applied: boolean(),
      safety_optimized: boolean(),
      claude_formatted: boolean(),
      multimodal_optimized: boolean(),
      function_calling_optimized: boolean(),
      code_generation_optimized: boolean(),
      large_context_leveraged: boolean(),
      google_services_integrated: boolean(),
      gemini_formatted: boolean(),
      gemini_optimized: boolean(),
      consistent_reasoning_optimized: boolean(),
      structured_output_enhanced: boolean(),
      api_reliability_optimized: boolean(),
      language_capabilities_leveraged: boolean(),
      creative_analytical_balanced: boolean(),
      openai_formatted: boolean(),
      openai_optimized: boolean(),
      large_context_optimized: boolean()
    }
  end

  defmodule ModelCapabilities do
    @moduledoc """
    Comprehensive model capability information for optimization decisions.
    """
    
    defstruct [
      context_window: 0,
      supports_function_calling: false,
      supports_multimodal: false,
      supports_structured_output: false,
      supports_streaming: false,
      reasoning_strength: :unknown,
      code_understanding: :unknown,
      language_capabilities: :unknown,
      safety_filtering: :unknown,
      latency_characteristics: :unknown,
      cost_characteristics: :unknown,
      # Dynamic capability measurements
      actual_context_utilization: 0.0,
      function_calling_reliability: 0.0,
      response_consistency: 0.0
    ]

    @type strength_level :: :poor | :fair | :good | :very_good | :excellent | :unknown
    
    @type t :: %__MODULE__{
      context_window: non_neg_integer(),
      supports_function_calling: boolean(),
      supports_multimodal: boolean(),
      supports_structured_output: boolean(),
      supports_streaming: boolean(),
      reasoning_strength: strength_level(),
      code_understanding: strength_level(),
      language_capabilities: strength_level(),
      safety_filtering: strength_level(),
      latency_characteristics: strength_level(),
      cost_characteristics: strength_level(),
      actual_context_utilization: float(),
      function_calling_reliability: float(),
      response_consistency: float()
    }
  end

  defmodule OptimizationTargets do
    @moduledoc """
    Optimization targets and priorities for the current request.
    """
    
    defstruct [
      quality: false,
      speed: false,
      cost: false,
      reliability: false,
      creativity: false,
      accuracy: false
    ]

    @type t :: %__MODULE__{
      quality: boolean(),
      speed: boolean(),
      cost: boolean(),
      reliability: boolean(),
      creativity: boolean(),
      accuracy: boolean()
    }
  end

  defmodule AdaptationStrategy do
    @moduledoc """
    Adaptation strategy learned from interaction patterns.
    """
    
    defstruct [
      preferred_instruction_style: nil,
      optimal_context_length: 0,
      effective_example_types: [],
      successful_reasoning_patterns: [],
      error_prevention_strategies: [],
      validation_passed: false,
      validation_score: 0.0,
      validation_issues: [],
      provider_info: nil,
      stored_successfully: false,
      storage_key: nil,
      stored_at: nil,
      error_reason: nil
    ]

    @type instruction_style :: :structured | :conversational | :detailed | :mixed | :unclear | nil
    
    @type t :: %__MODULE__{
      preferred_instruction_style: instruction_style(),
      optimal_context_length: non_neg_integer(),
      effective_example_types: list(atom()),
      successful_reasoning_patterns: list(atom()),
      error_prevention_strategies: list(atom()),
      validation_passed: boolean(),
      validation_score: float(),
      validation_issues: list(String.t()),
      provider_info: map() | nil,
      stored_successfully: boolean(),
      storage_key: String.t() | nil,
      stored_at: DateTime.t() | nil
    }
  end

  defmodule InteractionPatterns do
    @moduledoc """
    Patterns extracted from interaction history analysis.
    """
    
    defstruct [
      effective_instruction_styles: [],
      optimal_context_lengths: %{},
      effective_example_types: [],
      successful_reasoning_patterns: [],
      error_prevention_strategies: []
    ]

    @type t :: %__MODULE__{
      effective_instruction_styles: list(atom()),
      optimal_context_lengths: map(),
      effective_example_types: list(atom()),
      successful_reasoning_patterns: list(atom()),
      error_prevention_strategies: list(atom())
    }
  end
end