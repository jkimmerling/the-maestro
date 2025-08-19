defmodule TheMaestro.Prompts.Enhancement.Structs do
  @moduledoc """
  Data structures for the prompt enhancement pipeline.
  """

  defmodule EnhancementContext do
    @moduledoc """
    Context structure that flows through the enhancement pipeline.
    """
    
    @type t :: %__MODULE__{
      original_prompt: String.t(),
      user_context: map(),
      enhancement_config: map(),
      pipeline_state: map()
    }

    defstruct [
      :original_prompt,
      :user_context,
      :enhancement_config,
      :pipeline_state
    ]
  end

  defmodule ContextAnalysis do
    @moduledoc """
    Analysis results from the context analysis stage.
    """

    @type prompt_type :: :software_engineering | :file_operations | :system_operations | 
                        :information_seeking | :general
    @type intent :: :bug_fix | :debugging | :troubleshooting | :feature_implementation |
                   :refactoring | :optimization | :read_file | :write_file | :information_seeking |
                   :learning | :deployment | :testing | :configuration | :general
    @type complexity :: :low | :medium | :high
    @type urgency :: :low | :medium | :high  
    @type collaboration :: :individual | :team | :enterprise

    @type t :: %__MODULE__{
      prompt_type: prompt_type(),
      user_intent: intent(),
      mentioned_entities: [String.t()],
      implicit_requirements: [atom()],
      complexity_level: complexity(),
      domain_indicators: [atom()],
      urgency_level: urgency(),
      collaboration_mode: collaboration()
    }

    defstruct [
      :prompt_type,
      :user_intent,
      :mentioned_entities,
      :implicit_requirements,
      :complexity_level,
      :domain_indicators,
      :urgency_level,
      :collaboration_mode
    ]
  end

  defmodule IntentResult do
    @moduledoc """
    Intent detection result structure.
    """

    @type t :: %__MODULE__{
      category: atom(),
      confidence: float(),
      context_requirements: [atom()],
      patterns_matched: [String.t()]
    }

    defstruct [
      :category,
      :confidence,
      :context_requirements,
      :patterns_matched
    ]
  end

  defmodule EnvironmentalContext do
    @moduledoc """
    Environmental context information structure.
    """

    @type t :: %__MODULE__{
      timestamp: DateTime.t(),
      timezone: String.t(),
      operating_system: String.t(),
      working_directory: String.t(),
      directory_contents: [String.t()],
      system_resources: map(),
      network_status: :connected | :disconnected | :limited,
      shell_environment: map(),
      git_status: map() | nil,
      project_type: String.t() | nil
    }

    defstruct [
      :timestamp,
      :timezone,
      :operating_system,
      :working_directory,
      :directory_contents,
      :system_resources,
      :network_status,
      :shell_environment,
      :git_status,
      :project_type
    ]
  end

  defmodule ProjectStructureContext do
    @moduledoc """
    Project structure analysis context.
    """

    @type t :: %__MODULE__{
      project_type: String.t() | nil,
      language_detection: [String.t()],
      framework_detection: [String.t()],
      configuration_files: [String.t()],
      dependency_files: [String.t()],
      build_systems: [String.t()],
      test_frameworks: [String.t()],
      documentation_files: [String.t()],
      entry_points: [String.t()],
      directory_structure: map(),
      file_patterns: map(),
      recent_changes: [map()]
    }

    defstruct [
      :project_type,
      :language_detection,
      :framework_detection,
      :configuration_files,
      :dependency_files,
      :build_systems,
      :test_frameworks,
      :documentation_files,
      :entry_points,
      :directory_structure,
      :file_patterns,
      :recent_changes
    ]
  end

  defmodule CodeAnalysisContext do
    @moduledoc """
    Code analysis context structure.
    """

    @type t :: %__MODULE__{
      relevant_files: [String.t()],
      code_patterns: map(),
      dependencies: [String.t()],
      imports_and_exports: map(),
      function_signatures: [String.t()],
      class_definitions: [String.t()],
      configuration_values: map(),
      test_coverage: map(),
      documentation_coverage: map(),
      code_quality_metrics: map(),
      architectural_patterns: [atom()],
      potential_issues: [map()]
    }

    defstruct [
      :relevant_files,
      :code_patterns,
      :dependencies,
      :imports_and_exports,
      :function_signatures,
      :class_definitions,
      :configuration_values,
      :test_coverage,
      :documentation_coverage,
      :code_quality_metrics,
      :architectural_patterns,
      :potential_issues
    ]
  end

  defmodule ContextItem do
    @moduledoc """
    Individual context item with relevance scoring.
    """

    @type t :: %__MODULE__{
      type: atom(),
      value: any(),
      relevance_score: float(),
      contributing_factors: map()
    }

    defstruct [
      :type,
      :value,
      :relevance_score,
      :contributing_factors
    ]
  end

  defmodule EnhancedPrompt do
    @moduledoc """
    Final enhanced prompt structure.
    """

    @type t :: %__MODULE__{
      original: String.t(),
      pre_context: String.t(),
      enhanced_prompt: String.t(),
      post_context: String.t(),
      metadata: map(),
      total_tokens: integer(),
      relevance_scores: [float()]
    }

    defstruct [
      :original,
      :pre_context,
      :enhanced_prompt,
      :post_context,
      :metadata,
      :total_tokens,
      :relevance_scores
    ]
  end

  defmodule ValidationResult do
    @moduledoc """
    Enhancement quality validation result.
    """

    @type t :: %__MODULE__{
      quality_score: float(),
      validations: map(),
      recommendations: [String.t()],
      pass: boolean()
    }

    defstruct [
      :quality_score,
      :validations,
      :recommendations,
      :pass
    ]
  end
end