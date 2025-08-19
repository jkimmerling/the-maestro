defmodule TheMaestro.Prompts.Enhancement.Analyzers.IntentDetector do
  @moduledoc """
  Sophisticated intent classification system for understanding user goals and requirements.

  This module uses pattern matching and confidence scoring to determine the user's
  primary intent, which helps drive context gathering and prompt enhancement decisions.
  """

  alias TheMaestro.Prompts.Enhancement.Structs.IntentResult

  defp intent_categories do
    %{
      software_engineering: %{
        patterns: [
          ~r/(?:fix|debug|refactor|optimize|improve).+(?:code|function|class|module|bug|authentication|error|issue)/i,
          ~r/(?:add|implement|create|update).+(?:feature|function|class|component|test|api|endpoint|user|information)/i,
          ~r/(?:analyze|review|explain).+(?:code|implementation|architecture|algorithm)/i,
          ~r/(?:unit test|integration test|testing|test coverage)/i,
          ~r/(?:bug|error|exception|crash|fail).+(?:in|with|on).+(?:service|module|component|function)/i,
          ~r/(?:authentication|authorization|security|validation|encryption)/i,
          ~r/(?:api|endpoint|service|microservice)/i,
          ~r/(?:database|sql|query|migration)/i,
          ~r/(?:performance|optimization|scaling)/i,
          ~r/(?:vulnerability|security)/i
        ],
        confidence_boost: 0.3,
        context_requirements: [:project_structure, :existing_code, :dependencies]
      },
      file_operations: %{
        patterns: [
          ~r/(?:read|write|create|delete|modify|edit).+(?:file|directory|\.json|\.yml|\.xml|\.txt|\.md)/i,
          ~r/(?:list|show|display).+(?:files|directories|contents|folder)/i,
          ~r/(?:find|search|locate).+(?:in|within).+(?:files|directory|folder)/i,
          ~r/(?:copy|move|rename).+(?:file|folder|directory)/i,
          ~r/(?:json|csv|xml|yaml|config)/i,
          # File extensions like .json, .txt, etc.
          ~r/\.\w{2,5}\b/,
          # File paths
          ~r/\/[\w\/.-]+/
        ],
        confidence_boost: 0.25,
        context_requirements: [:current_directory, :file_permissions, :directory_structure]
      },
      system_operations: %{
        patterns: [
          ~r/(?:run|execute|start|stop).+(?:command|script|process|server|test suite|tests)/i,
          ~r/(?:install|configure|setup).+(?:package|software|system|environment|dependencies)/i,
          ~r/(?:restart|reload|kill).+(?:server|service|process)/i,
          ~r/(?:shell|terminal|command line|bash|zsh|powershell)/i,
          ~r/(?:npm|yarn|pip|gem|cargo|mix).+(?:install|start|build|run)/i,
          ~r/(?:docker|kubernetes|deploy|build).+(?:container|image|service)/i,
          ~r/(?:server|daemon|background).+(?:start|stop|restart)/i
        ],
        confidence_boost: 0.2,
        context_requirements: [:operating_system, :available_commands, :permissions]
      },
      information_seeking: %{
        patterns: [
          ~r/^(?:what|how|why|when|where|which)/i,
          ~r/(?:explain|describe|tell me about|show me).+(?:how|what|concept|idea|pattern)/i,
          ~r/(?:help|assist|guide|tutorial).+(?:with understanding|to learn|me learn)/i,
          ~r/(?:documentation|docs|manual|reference|information about)/i,
          ~r/(?:learn|understand|know|concept)/i,
          ~r/(?:difference|compare|vs|versus)/i,
          ~r/(?:best practice|pattern|approach)/i
        ],
        confidence_boost: 0.15,
        context_requirements: [:knowledge_base, :documentation, :examples]
      }
    }
  end

  @doc """
  Detects the primary intent from a user prompt using pattern matching and confidence scoring.

  ## Parameters

  - `prompt` - The user's prompt string to analyze

  ## Returns

  An `IntentResult` struct containing:
  - `category` - The detected intent category
  - `confidence` - Confidence score (0.0 to 1.0)
  - `context_requirements` - List of required context types
  - `patterns_matched` - List of patterns that matched

  ## Examples

      iex> IntentDetector.detect_intent("Fix the authentication bug in user service")
      %IntentResult{
        category: :software_engineering,
        confidence: 0.85,
        context_requirements: [:project_structure, :existing_code, :dependencies],
        patterns_matched: ["fix.*bug", "authentication"]
      }
  """
  @spec detect_intent(String.t()) :: IntentResult.t()
  def detect_intent(prompt) do
    intent_categories()
    |> Enum.map(&score_intent_category(&1, prompt))
    |> Enum.max_by(& &1.confidence)
  end

  @doc """
  Scores a single intent category against the prompt.

  ## Parameters

  - `category_config` - Tuple of {category_name, category_config}
  - `prompt` - The prompt to score against

  ## Returns

  An `IntentResult` struct with the scoring results for this category.
  """
  @spec score_intent_category({atom(), map()}, String.t()) :: IntentResult.t()
  def score_intent_category({category, config}, prompt) do
    patterns = config.patterns
    confidence_boost = config.confidence_boost
    context_requirements = config.context_requirements

    # Count pattern matches
    {matched_patterns, match_count} = count_pattern_matches(patterns, prompt)

    # Calculate base confidence from pattern matches
    base_confidence =
      case match_count do
        0 -> 0.0
        1 -> 0.3
        2 -> 0.5
        3 -> 0.7
        _ -> 0.9
      end

    # Apply confidence boost only if there are pattern matches
    final_confidence =
      case match_count do
        # No boost for zero matches
        0 -> base_confidence
        _ -> min(base_confidence + confidence_boost, 1.0)
      end

    # Adjust for prompt length (longer prompts may have more matches by chance)
    word_count = String.split(prompt) |> length()

    length_adjustment =
      case word_count do
        count when count < 5 -> 0.1
        count when count < 10 -> 0.0
        count when count < 20 -> -0.05
        _ -> -0.1
      end

    adjusted_confidence = max(final_confidence + length_adjustment, 0.0)

    %IntentResult{
      category: category,
      confidence: adjusted_confidence,
      context_requirements: context_requirements,
      patterns_matched: matched_patterns
    }
  end

  # Private helper functions

  defp count_pattern_matches(patterns, prompt) do
    matched_info =
      Enum.reduce(patterns, {[], 0}, fn pattern, {matched, count} ->
        if Regex.match?(pattern, prompt) do
          # Remove ~r/ and /i
          pattern_string = inspect(pattern) |> String.slice(2..-3//1)
          {[pattern_string | matched], count + 1}
        else
          {matched, count}
        end
      end)

    matched_info
  end
end
