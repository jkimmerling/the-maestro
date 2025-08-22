defmodule TheMaestro.Prompts.EngineeringTools.InteractiveBuilder do
  @moduledoc """
  Interactive prompt builder with real-time editing, validation, and collaboration features.

  Provides a comprehensive visual and code-based prompt construction environment
  with real-time preview, validation, suggestions, and collaborative editing capabilities.
  """

  defmodule PromptBuilderSession do
    @moduledoc """
    Represents an interactive prompt builder session.
    """
    defstruct [
      :session_id,
      :current_prompt,
      :prompt_structure,
      :available_components,
      :real_time_preview,
      :validation_engine,
      :suggestion_engine,
      :collaboration_state,
      :performance_prediction,
      :improvement_suggestions,
      :validation_results,
      :auto_save_triggered,
      :last_save_timestamp
    ]
  end

  defmodule PromptModification do
    @moduledoc """
    Represents a modification to be applied to a prompt.
    """
    defstruct [
      :type,
      :target,
      :replacement,
      :insertion,
      :position,
      :section_type,
      :content,
      :component
    ]
  end

  @doc """
  Creates a new interactive prompt builder session.
  """
  @spec create_prompt_builder_session(String.t()) :: PromptBuilderSession.t()
  def create_prompt_builder_session(initial_prompt \\ "") do
    %PromptBuilderSession{
      session_id: generate_session_id(),
      current_prompt: initial_prompt,
      prompt_structure: analyze_prompt_structure(initial_prompt),
      available_components: load_prompt_components(),
      real_time_preview: initialize_preview_system(),
      validation_engine: initialize_validation_engine(),
      suggestion_engine: initialize_suggestion_engine(),
      collaboration_state: initialize_collaboration_state(),
      performance_prediction: predict_prompt_performance(initial_prompt),
      improvement_suggestions: generate_improvement_suggestions(initial_prompt),
      validation_results: validate_prompt_in_real_time(initial_prompt),
      auto_save_triggered: false,
      last_save_timestamp: nil
    }
  end

  @doc """
  Applies a modification to the current prompt in the session.
  """
  @spec apply_prompt_modification(PromptBuilderSession.t(), PromptModification.t()) ::
          PromptBuilderSession.t()
  def apply_prompt_modification(session, modification) do
    updated_prompt = apply_modification_to_prompt(session.current_prompt, modification)

    %{
      session
      | current_prompt: updated_prompt,
        prompt_structure: analyze_prompt_structure(updated_prompt),
        validation_results: validate_prompt_in_real_time(updated_prompt),
        performance_prediction: predict_prompt_performance(updated_prompt),
        improvement_suggestions: generate_improvement_suggestions(updated_prompt),
        auto_save_triggered: true,
        last_save_timestamp: DateTime.utc_now()
    }
    |> update_collaboration_state()
  end

  # Private helper functions

  defp generate_session_id do
    "session_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  defp analyze_prompt_structure(prompt) do
    %{
      content_length: String.length(prompt),
      sections_count: count_sections(prompt),
      parameter_count: count_parameters(prompt),
      complexity_score: calculate_complexity_score(prompt),
      template_parameters: extract_template_parameters(prompt),
      conditional_logic: extract_conditional_logic(prompt)
    }
  end

  defp count_sections(prompt) do
    # Count sections based on headers, line breaks, and structure
    sections = String.split(prompt, ~r/\n\s*\n|\n#+|\n-{3,}/)
    max(1, length(sections))
  end

  defp count_parameters(prompt) do
    # Count template parameters like {{param}}
    Regex.scan(~r/\{\{[^}]+\}\}/, prompt)
    |> length()
  end

  defp calculate_complexity_score(prompt) do
    base_score = String.length(prompt) / 100
    parameter_bonus = count_parameters(prompt) * 0.1
    conditional_bonus = count_conditional_logic(prompt) * 0.2

    min(1.0, base_score + parameter_bonus + conditional_bonus)
  end

  defp count_conditional_logic(prompt) do
    conditionals = [
      ~r/\{\{#if\s+[^}]+\}\}/,
      ~r/\{\{#unless\s+[^}]+\}\}/,
      ~r/\{\{#each\s+[^}]+\}\}/
    ]

    Enum.reduce(conditionals, 0, fn regex, acc ->
      acc + length(Regex.scan(regex, prompt))
    end)
  end

  defp extract_template_parameters(prompt) do
    Regex.scan(~r/\{\{([^}]+)\}\}/, prompt)
    |> Enum.map(fn [_full, param] -> String.trim(param) end)
    |> Enum.map(&parse_parameter_definition/1)
  end

  defp parse_parameter_definition(param_str) do
    # Parse parameter like "name | default: value | required"
    parts = String.split(param_str, "|")
    name = String.trim(hd(parts))

    modifiers =
      Enum.drop(parts, 1)
      |> Enum.map(&String.trim/1)
      |> Enum.reduce(%{}, &parse_parameter_modifier/2)

    Map.put(modifiers, :name, name)
  end

  defp parse_parameter_modifier(modifier, acc) do
    cond do
      String.starts_with?(modifier, "default:") ->
        default_value = String.trim_leading(modifier, "default:") |> String.trim()
        Map.put(acc, :default, default_value)

      String.starts_with?(modifier, "enum:") ->
        enum_values =
          String.trim_leading(modifier, "enum:")
          |> String.trim()
          |> String.trim_leading("[")
          |> String.trim_trailing("]")
          |> String.split(",")
          |> Enum.map(&String.trim/1)

        Map.put(acc, :enum, enum_values)

      modifier == "required" ->
        Map.put(acc, :required, true)

      String.starts_with?(modifier, "type:") ->
        type = String.trim_leading(modifier, "type:") |> String.trim()
        Map.put(acc, :type, String.to_atom(type))

      true ->
        acc
    end
  end

  defp extract_conditional_logic(prompt) do
    conditionals = []

    # Extract if statements
    if_statements =
      Regex.scan(~r/\{\{#if\s+([^}]+)\}\}(.*?)\{\{\/if\}\}/s, prompt)
      |> Enum.map(fn [_full, condition, content] ->
        %{type: :if, condition: String.trim(condition), content: String.trim(content)}
      end)

    # Extract unless statements
    unless_statements =
      Regex.scan(~r/\{\{#unless\s+([^}]+)\}\}(.*?)\{\{\/unless\}\}/s, prompt)
      |> Enum.map(fn [_full, condition, content] ->
        %{type: :unless, condition: String.trim(condition), content: String.trim(content)}
      end)

    # Extract each loops
    each_statements =
      Regex.scan(~r/\{\{#each\s+([^}]+)\}\}(.*?)\{\{\/each\}\}/s, prompt)
      |> Enum.map(fn [_full, variable, content] ->
        %{type: :each, variable: String.trim(variable), content: String.trim(content)}
      end)

    conditionals ++ if_statements ++ unless_statements ++ each_statements
  end

  defp load_prompt_components do
    [
      %{
        name: "Role Definition",
        category: :role_definition,
        template: "You are a {{role | default: assistant}}.",
        description: "Defines the AI's role and personality",
        parameters: ["role"]
      },
      %{
        name: "Task Specification",
        category: :task_specification,
        template: "Your task is to {{task | required}}.",
        description: "Clearly specifies what the AI should do",
        parameters: ["task"]
      },
      %{
        name: "Context Information",
        category: :context,
        template: """
        ## Context
        {{context | required}}
        """,
        description: "Provides relevant background information",
        parameters: ["context"]
      },
      %{
        name: "Output Format",
        category: :output_format,
        template:
          "Provide your response in {{format | enum: [paragraph, list, json, markdown] | default: paragraph}} format.",
        description: "Specifies the desired output format",
        parameters: ["format"]
      },
      %{
        name: "Constraints",
        category: :constraints,
        template: """
        ## Constraints
        {{#each constraints}}
        - {{this}}
        {{/each}}
        """,
        description: "Lists limitations and requirements",
        parameters: ["constraints"]
      },
      %{
        name: "Examples",
        category: :examples,
        template: """
        ## Examples
        {{#each examples}}
        **Input:** {{this.input}}
        **Output:** {{this.output}}

        {{/each}}
        """,
        description: "Provides example inputs and outputs",
        parameters: ["examples"]
      }
    ]
  end

  defp initialize_preview_system do
    %{
      provider: :preview,
      model: "preview-model",
      enabled: true,
      real_time: true,
      debounce_ms: 500
    }
  end

  defp initialize_validation_engine do
    %{
      rules: [
        :template_syntax,
        :parameter_validation,
        :length_constraints,
        :complexity_check,
        :performance_impact
      ],
      enabled: true,
      real_time: true,
      auto_fix_suggestions: true
    }
  end

  defp initialize_suggestion_engine do
    %{
      enabled: true,
      suggestion_types: [
        :structure_improvement,
        :clarity_enhancement,
        :parameter_extraction,
        :performance_optimization,
        :best_practices
      ],
      confidence_threshold: 0.7,
      max_suggestions: 5
    }
  end

  defp initialize_collaboration_state do
    %{
      participants: [],
      active_editors: [],
      requires_sync: false,
      last_edit_by: nil,
      edit_conflicts: []
    }
  end

  defp predict_prompt_performance(prompt) do
    token_estimate = estimate_token_usage(prompt)
    complexity_score = calculate_complexity_score(prompt)

    %{
      estimated_tokens: token_estimate,
      complexity_score: complexity_score,
      estimated_response_time: estimate_response_time(token_estimate, complexity_score),
      quality_prediction: predict_quality_score(prompt),
      cost_estimate: estimate_cost(token_estimate)
    }
  end

  defp estimate_token_usage(prompt) do
    # Rough estimate: ~4 characters per token
    base_tokens = div(String.length(prompt), 4)

    # Add tokens for expected response (heuristic)
    complexity_multiplier = max(1.5, calculate_complexity_score(prompt) * 3)
    response_tokens = round(base_tokens * complexity_multiplier)

    base_tokens + response_tokens
  end

  defp estimate_response_time(token_estimate, complexity_score) do
    # Base response time in milliseconds
    base_time = 1000

    # Add time based on tokens and complexity
    # 2ms per token
    token_time = token_estimate * 2
    complexity_time = round(complexity_score * 1000)

    base_time + token_time + complexity_time
  end

  defp predict_quality_score(prompt) do
    # Base score
    base_score = 0.5

    # Calculate adjustments
    structure_bonus = if String.contains?(prompt, ["##", "**", "-"]), do: 0.1, else: 0.0

    example_bonus =
      if String.contains?(prompt, ["example", "Example", "EXAMPLE"]), do: 0.15, else: 0.0

    instruction_bonus =
      if String.contains?(prompt, ["please", "should", "must", "need to"]), do: 0.1, else: 0.0

    length_penalty = if String.length(prompt) > 2000, do: -0.1, else: 0.0
    short_penalty = if String.length(prompt) < 50, do: -0.2, else: 0.0

    final_score =
      base_score + structure_bonus + example_bonus + instruction_bonus + length_penalty +
        short_penalty

    max(0.0, min(1.0, final_score))
  end

  defp estimate_cost(token_estimate) do
    # Rough cost estimate (varies by provider)
    # $0.02 per 1K tokens
    cost_per_token = 0.00002
    token_estimate * cost_per_token
  end

  defp generate_improvement_suggestions(prompt) do
    [
      check_repetition(prompt),
      check_structure(prompt),
      check_clarity(prompt),
      check_parameterization(prompt),
      check_performance(prompt)
    ]
    |> List.flatten()
  end

  defp check_repetition(prompt) do
    words = String.split(prompt, ~r/\s+/)
    word_counts = Enum.frequencies(words)

    repeated_words =
      Enum.filter(word_counts, fn {word, count} ->
        count > 3 && String.length(word) > 4
      end)

    if length(repeated_words) > 0 do
      [
        %{
          type: :reduce_repetition,
          description:
            "Consider reducing repetition of words: #{Enum.map(repeated_words, fn {word, _} -> word end) |> Enum.join(", ")}",
          priority: :medium,
          fix_suggestion: "Vary your language or use parameters for repeated concepts"
        }
      ]
    else
      []
    end
  end

  defp check_structure(prompt) do
    has_headers = String.contains?(prompt, ["##", "**", "###"])
    has_lists = String.contains?(prompt, ["-", "*", "1.", "2."])

    # Check for unstructured prompts - either too short and vague, or too long without structure
    is_unstructured =
      not has_headers and not has_lists and
        (String.length(prompt) > 50 or contains_vague_terms?(prompt))

    if is_unstructured do
      [
        %{
          type: :add_structure,
          description: "Long prompt could benefit from better structure with headers or lists",
          priority: :medium,
          fix_suggestion: "Add headers (## Section) or bullet points to organize content"
        }
      ]
    else
      []
    end
  end

  defp contains_vague_terms?(prompt) do
    vague_terms = ["something", "things", "stuff", "do", "make", "good", "bad"]
    Enum.any?(vague_terms, fn term -> String.contains?(String.downcase(prompt), term) end)
  end

  defp check_clarity(prompt) do
    # Check for vague terms
    vague_terms = ["something", "things", "stuff", "do", "make", "good", "bad"]

    found_vague =
      Enum.filter(vague_terms, fn term -> String.contains?(String.downcase(prompt), term) end)

    if length(found_vague) > 0 do
      [
        %{
          type: :clarify_instructions,
          description: "Consider replacing vague terms with more specific language",
          priority: :high,
          fix_suggestion:
            "Replace terms like '#{Enum.join(found_vague, ", ")}' with specific descriptions"
        }
      ]
    else
      []
    end
  end

  defp check_parameterization(prompt) do
    # Look for repeated concepts that could be parameters
    concepts = extract_parameterizable_concepts(prompt)

    if length(concepts) > 0 do
      [
        %{
          type: :extract_parameter,
          description: "Consider parameterizing repeated concepts: #{Enum.join(concepts, ", ")}",
          priority: :low,
          fix_suggestion: "Create parameters for repeated values to make the prompt more reusable"
        }
      ]
    else
      []
    end
  end

  defp extract_parameterizable_concepts(prompt) do
    # Simple heuristic: look for repeated words that might be good parameters
    words = String.split(prompt, ~r/\s+/)
    lowercase_words = Enum.map(words, &String.downcase/1)
    word_counts = Enum.frequencies(lowercase_words)

    repeated_concepts =
      Enum.filter(word_counts, fn {word, count} ->
        count >= 2 && String.length(word) > 3 &&
          not Enum.member?(["the", "and", "that", "this", "with", "from"], word)
      end)
      |> Enum.map(fn {word, _count} ->
        # Find the original case version
        Enum.find(words, fn w -> String.downcase(w) == word end) || word
      end)
      |> Enum.take(3)

    repeated_concepts
  end

  defp check_performance(prompt) do
    # Check for excessive verbosity (lots of adverbs, redundant adjectives)
    verbose_indicators = [
      "extremely",
      "very",
      "quite",
      "exceptionally",
      "meticulously",
      "comprehensively",
      "thoroughly",
      "extensively",
      "exhaustive",
      "complete",
      "detailed"
    ]

    verbose_count =
      Enum.count(verbose_indicators, fn indicator ->
        String.contains?(String.downcase(prompt), indicator)
      end)

    length_suggestions =
      if String.length(prompt) > 3000 or verbose_count >= 3 do
        [
          %{
            type: :reduce_verbosity,
            description: "Prompt is quite long and may be inefficient",
            priority: :medium,
            fix_suggestion:
              "Consider condensing content or breaking into multiple focused prompts"
          }
        ]
      else
        []
      end

    # Check for very long sentences
    sentences = String.split(prompt, ~r/[.!?]+/)
    long_sentences = Enum.filter(sentences, fn s -> String.length(s) > 200 end)

    sentence_suggestions =
      if length(long_sentences) > 0 do
        [
          %{
            type: :optimize_length,
            description: "Some sentences are very long and may reduce clarity",
            priority: :low,
            fix_suggestion: "Break long sentences into shorter, clearer statements"
          }
        ]
      else
        []
      end

    length_suggestions ++ sentence_suggestions
  end

  defp validate_prompt_in_real_time(prompt) do
    errors = []
    warnings = []

    # Template syntax validation
    {syntax_errors, template_valid} = validate_template_syntax(prompt)
    errors = errors ++ syntax_errors

    # Length validation
    length_warnings = validate_length_constraints(prompt)
    warnings = warnings ++ length_warnings

    # Parameter validation
    parameter_errors = validate_parameters(prompt)
    errors = errors ++ parameter_errors

    %{
      has_errors: length(errors) > 0,
      errors: errors,
      warnings: warnings,
      template_syntax_valid: template_valid,
      template_parameters: extract_template_parameters(prompt),
      length_warnings: length_warnings
    }
  end

  defp validate_template_syntax(prompt) do
    _all_errors = []

    # Check for unclosed template tags - look for {{ not followed by }}
    open_brackets = length(Regex.scan(~r/\{\{/, prompt))
    close_brackets = length(Regex.scan(~r/\}\}/, prompt))

    unclosed_errors =
      if open_brackets > close_brackets do
        [%{type: :template_syntax_error, message: "Unclosed template tags detected"}]
      else
        []
      end

    # Check for nested template tags (not supported in basic implementation)
    nested = Regex.scan(~r/\{\{[^}]*\{\{/, prompt)

    nested_errors =
      if length(nested) > 0 do
        [%{type: :template_syntax_error, message: "Nested template tags detected"}]
      else
        []
      end

    # Check for malformed conditionals
    if_count = length(Regex.scan(~r/\{\{#if\s+[^}]+\}\}/, prompt))
    endif_count = length(Regex.scan(~r/\{\{\/if\}\}/, prompt))

    conditional_errors =
      if if_count != endif_count do
        [%{type: :template_syntax_error, message: "Mismatched if/endif tags"}]
      else
        []
      end

    all_errors = unclosed_errors ++ nested_errors ++ conditional_errors
    {all_errors, length(all_errors) == 0}
  end

  defp validate_length_constraints(prompt) do
    warnings = []
    length = String.length(prompt)

    cond do
      length > 5000 ->
        warnings ++
          [
            %{
              type: :excessive_length,
              message: "Prompt is very long (#{length} chars) and may cause performance issues"
            }
          ]

      length > 3000 ->
        warnings ++
          [
            %{
              type: :length_warning,
              message: "Prompt is quite long (#{length} chars) - consider optimization"
            }
          ]

      length < 20 ->
        warnings ++
          [%{type: :too_short, message: "Prompt is very short and may lack necessary context"}]

      true ->
        warnings
    end
  end

  defp validate_parameters(prompt) do
    errors = []
    parameters = extract_template_parameters(prompt)

    # Check for parameters with invalid syntax
    Enum.reduce(parameters, errors, fn param, acc ->
      if Map.has_key?(param, :enum) && not is_list(param.enum) do
        acc ++
          [
            %{
              type: :parameter_validation_error,
              message: "Invalid enum definition for parameter '#{param.name}'"
            }
          ]
      else
        acc
      end
    end)
  end

  defp apply_modification_to_prompt(prompt, modification) do
    case modification.type do
      :text_replacement ->
        String.replace(prompt, modification.target, modification.replacement)

      :text_insertion ->
        case modification.position do
          pos when is_integer(pos) ->
            {before, after_part} = String.split_at(prompt, pos)
            before <> modification.insertion <> after_part

          :end ->
            prompt <> modification.insertion

          :beginning ->
            modification.insertion <> prompt
        end

      :section_addition ->
        case modification.position do
          :end ->
            prompt <> "\n\n" <> modification.content

          :beginning ->
            modification.content <> "\n\n" <> prompt

          pos when is_integer(pos) ->
            {before, after_part} = String.split_at(prompt, pos)
            before <> "\n\n" <> modification.content <> "\n\n" <> after_part
        end

      :component_insertion ->
        component_text = modification.component.template

        case modification.position do
          pos when is_integer(pos) ->
            {before, after_part} = String.split_at(prompt, pos)
            before <> component_text <> after_part

          :end ->
            prompt <> "\n\n" <> component_text

          :beginning ->
            component_text <> "\n\n" <> prompt
        end

      _ ->
        prompt
    end
  end

  defp update_collaboration_state(session) do
    # Update collaboration state to reflect changes
    current_collab = session.collaboration_state || %{}
    participants = Map.get(current_collab, :participants, [])

    updated_collab =
      Map.merge(current_collab, %{
        requires_sync: length(participants) > 1,
        last_edit_by: "current_user"
      })

    %{session | collaboration_state: updated_collab}
  end
end
