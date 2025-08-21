defmodule TheMaestro.Prompts.EngineeringTools.TemplateManager do
  @moduledoc """
  Comprehensive prompt template management system with parameterization,
  versioning, performance tracking, and optimization capabilities.
  """

  defmodule PromptTemplate do
    @moduledoc """
    Represents a parameterized prompt template with metadata and performance tracking.
    """
    defstruct [
      :id,
      :name,
      :description,
      :category,
      :template_content,
      :parameters,
      :usage_examples,
      :performance_metrics,
      :version,
      :parent_version,
      :created_by,
      :created_at,
      :updated_at,
      :tags,
      :validation_rules,
      :optimization_suggestions
    ]
  end

  defmodule ParameterDefinition do
    @moduledoc """
    Defines template parameters with types, validation, and relationships.
    """
    defstruct [
      :required_parameters,
      :optional_parameters,
      :parameter_types,
      :validation_rules,
      :default_values,
      :parameter_relationships,
      :conditional_logic
    ]
  end

  defmodule TemplateMetadata do
    @moduledoc """
    Metadata for template creation and management.
    """
    defstruct [
      :name,
      :description,
      :category,
      :author,
      :tags,
      :visibility
    ]
  end

  defmodule TemplateParameters do
    @moduledoc """
    Advanced parameter system for templates with relationships and validation.
    """
    
    @doc """
    Defines template parameters from template content.
    """
    @spec define_template_parameters(String.t()) :: ParameterDefinition.t()
    def define_template_parameters(template_content) do
      parameters = extract_all_parameters(template_content)
      
      %ParameterDefinition{
        required_parameters: extract_required_parameters(parameters),
        optional_parameters: extract_optional_parameters(parameters),
        parameter_types: infer_parameter_types(parameters),
        validation_rules: define_parameter_validation(parameters),
        default_values: extract_default_values(parameters),
        parameter_relationships: analyze_parameter_relationships(template_content, parameters),
        conditional_logic: extract_conditional_parameters(template_content)
      }
    end

    defp extract_all_parameters(template_content) do
      # Extract all {{parameter}} patterns
      Regex.scan(~r/\{\{([^}]+)\}\}/, template_content)
      |> Enum.map(fn [_full, param] -> parse_parameter_definition(String.trim(param)) end)
      |> Enum.uniq_by(& &1.name)
    end

    defp parse_parameter_definition(param_str) do
      parts = String.split(param_str, "|") |> Enum.map(&String.trim/1)
      name = hd(parts)
      
      modifiers = Enum.drop(parts, 1)
      |> Enum.reduce(%{}, fn modifier, acc ->
        parse_modifier(modifier, acc)
      end)
      
      Map.put(modifiers, :name, name)
    end

    defp parse_modifier(modifier, acc) do
      cond do
        String.starts_with?(modifier, "default:") ->
          value = extract_modifier_value(modifier, "default:")
          Map.put(acc, :default, value)
        
        String.starts_with?(modifier, "enum:") ->
          value = extract_modifier_value(modifier, "enum:")
          enum_list = parse_enum_list(value)
          Map.put(acc, :enum, enum_list)
        
        String.starts_with?(modifier, "type:") ->
          value = extract_modifier_value(modifier, "type:")
          Map.put(acc, :type, String.to_atom(value))
        
        String.starts_with?(modifier, "min_length:") ->
          value = extract_modifier_value(modifier, "min_length:")
          Map.put(acc, :min_length, String.to_integer(value))
        
        String.starts_with?(modifier, "max_length:") ->
          value = extract_modifier_value(modifier, "max_length:")
          Map.put(acc, :max_length, String.to_integer(value))
        
        String.starts_with?(modifier, "min:") ->
          value = extract_modifier_value(modifier, "min:")
          Map.put(acc, :min, parse_number(value))
        
        String.starts_with?(modifier, "max:") ->
          value = extract_modifier_value(modifier, "max:")
          Map.put(acc, :max, parse_number(value))
        
        modifier == "required" ->
          Map.put(acc, :required, true)
        
        modifier == "optional" ->
          Map.put(acc, :optional, true)
        
        true ->
          acc
      end
    end

    defp extract_modifier_value(modifier, prefix) do
      String.trim_leading(modifier, prefix) |> String.trim()
    end

    defp parse_enum_list(value) do
      value
      |> String.trim_leading("[")
      |> String.trim_trailing("]")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(& &1 == "")
    end

    defp parse_number(value) do
      case Float.parse(value) do
        {num, ""} -> num
        _ -> 
          case Integer.parse(value) do
            {num, ""} -> num
            _ -> 0
          end
      end
    end

    defp extract_required_parameters(parameters) do
      parameters
      |> Enum.filter(fn p -> Map.get(p, :required, false) end)
      |> Enum.map(& &1.name)
    end

    defp extract_optional_parameters(parameters) do
      parameters
      |> Enum.reject(fn p -> Map.get(p, :required, false) end)
      |> Enum.map(& &1.name)
    end

    defp infer_parameter_types(parameters) do
      parameters
      |> Enum.reduce(%{}, fn param, acc ->
        type = cond do
          Map.has_key?(param, :type) -> param.type
          Map.has_key?(param, :enum) -> :enum
          Map.has_key?(param, :min) || Map.has_key?(param, :max) -> :number
          Map.has_key?(param, :min_length) || Map.has_key?(param, :max_length) -> :string
          String.contains?(param.name, ["email"]) -> :email
          String.contains?(param.name, ["active", "enabled", "flag"]) -> :boolean
          String.contains?(param.name, ["score", "rate", "percentage"]) -> :float
          String.contains?(param.name, ["count", "number", "age"]) -> :integer
          true -> :string
        end
        
        Map.put(acc, param.name, type)
      end)
    end

    defp define_parameter_validation(parameters) do
      parameters
      |> Enum.reduce(%{}, fn param, acc ->
        rules = %{}
        
        rules = if Map.get(param, :required, false), do: Map.put(rules, :required, true), else: rules
        rules = if Map.has_key?(param, :min_length), do: Map.put(rules, :min_length, param.min_length), else: rules
        rules = if Map.has_key?(param, :max_length), do: Map.put(rules, :max_length, param.max_length), else: rules
        rules = if Map.has_key?(param, :min), do: Map.put(rules, :min, param.min), else: rules
        rules = if Map.has_key?(param, :max), do: Map.put(rules, :max, param.max), else: rules
        rules = if Map.has_key?(param, :enum), do: Map.put(rules, :enum, param.enum), else: rules
        
        if map_size(rules) > 0 do
          Map.put(acc, param.name, rules)
        else
          acc
        end
      end)
    end

    defp extract_default_values(parameters) do
      parameters
      |> Enum.filter(fn p -> Map.has_key?(p, :default) end)
      |> Enum.reduce(%{}, fn param, acc ->
        Map.put(acc, param.name, param.default)
      end)
    end

    defp analyze_parameter_relationships(template_content, parameters) do
      # Analyze conditional dependencies between parameters
      relationships = %{}
      
      # Find conditional blocks and their dependencies
      conditionals = Regex.scan(~r/\{\{#if\s+([^}]+)\}\}(.*?)\{\{\/if\}\}/s, template_content)
      
      Enum.reduce(conditionals, relationships, fn [_full, condition, content], acc ->
        condition_param = extract_condition_parameter(condition)
        dependent_params = extract_parameters_from_content(content, parameters)
        
        if condition_param && length(dependent_params) > 0 do
          Enum.reduce(dependent_params, acc, fn dep_param, inner_acc ->
            existing = Map.get(inner_acc, dep_param, [])
            Map.put(inner_acc, dep_param, [condition_param | existing] |> Enum.uniq())
          end)
        else
          acc
        end
      end)
    end

    defp extract_condition_parameter(condition) do
      # Simple extraction - look for parameter name in condition
      case Regex.run(~r/(\w+)/, String.trim(condition)) do
        [_, param] -> param
        _ -> nil
      end
    end

    defp extract_parameters_from_content(content, parameters) do
      param_names = Enum.map(parameters, & &1.name)
      
      Regex.scan(~r/\{\{([^}]+)\}\}/, content)
      |> Enum.map(fn [_full, param] -> 
        String.split(param, "|") |> hd() |> String.trim()
      end)
      |> Enum.filter(fn param -> Enum.member?(param_names, param) end)
      |> Enum.uniq()
    end

    defp extract_conditional_parameters(template_content) do
      conditionals = []
      
      # Extract if conditions
      if_conditions = Regex.scan(~r/\{\{#if\s+([^}]+)\}\}/, template_content)
      |> Enum.map(fn [_full, condition] -> 
        %{type: :if, condition: String.trim(condition)}
      end)
      
      # Extract unless conditions
      unless_conditions = Regex.scan(~r/\{\{#unless\s+([^}]+)\}\}/, template_content)
      |> Enum.map(fn [_full, condition] -> 
        %{type: :unless, condition: String.trim(condition)}
      end)
      
      # Extract each loops
      each_conditions = Regex.scan(~r/\{\{#each\s+([^}]+)\}\}/, template_content)
      |> Enum.map(fn [_full, variable] -> 
        %{type: :each, variable: String.trim(variable)}
      end)
      
      conditionals ++ if_conditions ++ unless_conditions ++ each_conditions
    end
  end

  @template_categories %{
    software_engineering: %{
      code_analysis: "Code analysis and review templates",
      bug_fixing: "Bug investigation and resolution templates", 
      feature_implementation: "Feature development templates",
      code_review: "Code review and quality assessment templates",
      testing: "Testing and validation templates"
    },
    creative_tasks: %{
      writing_assistance: "Creative writing and content generation",
      brainstorming: "Ideation and brainstorming templates",
      content_generation: "Content creation and marketing templates"
    },
    analysis_tasks: %{
      data_analysis: "Data analysis and interpretation templates",
      research_assistance: "Research and investigation templates", 
      problem_solving: "Problem-solving and decision-making templates"
    }
  }

  @doc """
  Creates a new prompt template from a prompt and metadata.
  """
  @spec create_template_from_prompt(String.t(), TemplateMetadata.t()) :: PromptTemplate.t()
  def create_template_from_prompt(prompt, metadata) do
    # Validate template syntax first
    case validate_template_structure(prompt) do
      {:error, reason} ->
        raise ArgumentError, "Invalid template syntax: #{reason}"
      
      :ok ->
        parameters = TemplateParameters.define_template_parameters(prompt)
        
        %PromptTemplate{
          id: generate_template_id(),
          name: metadata.name,
          description: metadata.description,
          category: metadata.category,
          template_content: extract_template_structure(prompt),
          parameters: parameters,
          usage_examples: generate_usage_examples(prompt, parameters),
          performance_metrics: initialize_performance_tracking(),
          version: 1,
          parent_version: nil,
          created_by: metadata.author,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          tags: metadata.tags,
          validation_rules: extract_validation_rules(prompt),
          optimization_suggestions: generate_optimization_suggestions(prompt)
        }
        |> optimize_template_for_reuse()
    end
  end

  @doc """
  Instantiates a template with provided parameters.
  """
  @spec instantiate_template(PromptTemplate.t(), map()) :: String.t()
  def instantiate_template(template, parameters) do
    # Validate required parameters
    validate_required_parameters!(template, parameters)
    
    # Validate parameter values
    validate_parameter_values!(template, parameters)
    
    template.template_content
    |> substitute_template_parameters(parameters, template.parameters)
    |> apply_template_transformations()
    |> validate_instantiated_prompt!()
    |> track_template_usage(template.id)
  end

  @doc """
  Gets all template categories.
  """
  @spec get_template_categories() :: map()
  def get_template_categories, do: @template_categories

  @doc """
  Gets templates by category.
  """
  @spec get_templates_by_category(atom()) :: list(PromptTemplate.t())
  def get_templates_by_category(category) do
    # In a real implementation, this would query a database
    # For now, return mock templates based on category
    case category do
      :code_analysis ->
        [
          %PromptTemplate{
            id: "tpl_code_001",
            name: "Code Security Review",
            description: "Template for security-focused code review",
            category: :code_analysis,
            template_content: "Review the following {{language}} code for security vulnerabilities...",
            tags: ["security", "code-review"],
            created_by: "system"
          }
        ]
      _ ->
        []
    end
  end

  @doc """
  Searches templates by tag.
  """
  @spec search_templates_by_tag(String.t()) :: list(PromptTemplate.t())
  def search_templates_by_tag(tag) do
    # In a real implementation, this would search a database
    # Return mock results for testing
    []
  end

  @doc """
  Updates an existing template.
  """
  @spec update_template(PromptTemplate.t(), String.t()) :: PromptTemplate.t()
  def update_template(template, new_content) do
    %PromptTemplate{template |
      template_content: new_content,
      parameters: TemplateParameters.define_template_parameters(new_content),
      version: template.version + 1,
      parent_version: template.version,
      updated_at: DateTime.utc_now(),
      optimization_suggestions: generate_optimization_suggestions(new_content)
    }
  end

  @doc """
  Gets version history for a template.
  """
  @spec get_template_version_history(String.t()) :: list(PromptTemplate.t())
  def get_template_version_history(_template_id) do
    # Mock implementation - would query database in real system
    []
  end

  @doc """
  Tracks template usage for analytics.
  """
  @spec track_template_usage(String.t(), String.t()) :: :ok
  def track_template_usage(_instantiated_prompt, _template_id) do
    # In a real implementation, this would update usage statistics
    :ok
  end

  # Private helper functions

  defp generate_template_id do
    "tpl_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  defp validate_template_structure(template_content) do
    # Check for basic template syntax errors
    cond do
      String.contains?(template_content, "{{") && not String.contains?(template_content, "}}") ->
        {:error, "Unclosed template tags"}
      
      # Check for nested templates (not supported in basic version)
      Regex.match?(~r/\{\{[^}]*\{\{/, template_content) ->
        {:error, "Nested template tags not supported"}
      
      # Check for mismatched conditional tags
      not balanced_conditionals?(template_content) ->
        {:error, "Mismatched conditional tags"}
      
      true ->
        :ok
    end
  end

  defp balanced_conditionals?(template_content) do
    if_count = length(Regex.scan(~r/\{\{#if\s/, template_content))
    endif_count = length(Regex.scan(~r/\{\{\/if\}\}/, template_content))
    
    unless_count = length(Regex.scan(~r/\{\{#unless\s/, template_content))
    endunless_count = length(Regex.scan(~r/\{\{\/unless\}\}/, template_content))
    
    each_count = length(Regex.scan(~r/\{\{#each\s/, template_content))
    endeach_count = length(Regex.scan(~r/\{\{\/each\}\}/, template_content))
    
    if_count == endif_count && unless_count == endunless_count && each_count == endeach_count
  end

  defp extract_template_structure(prompt) do
    # Clean up and normalize the template structure
    prompt
    |> String.trim()
    |> normalize_whitespace()
    |> normalize_template_tags()
  end

  defp normalize_whitespace(text) do
    # Normalize excessive whitespace while preserving structure
    text
    |> String.replace(~r/\n\s*\n\s*\n+/, "\n\n")  # Multiple newlines to double newline
    |> String.replace(~r/[ \t]+/, " ")              # Multiple spaces/tabs to single space
  end

  defp normalize_template_tags(text) do
    # Normalize template tag spacing
    text
    |> String.replace(~r/\{\{\s+/, "{{")
    |> String.replace(~r/\s+\}\}/, "}}")
  end

  defp generate_usage_examples(prompt, parameters) do
    # Generate example parameter sets based on template analysis
    example_count = min(3, max(1, div(length(parameters.required_parameters), 2) + 1))
    
    Enum.map(1..example_count, fn i ->
      example_params = generate_example_parameters(parameters, i)
      
      %{
        description: "Example #{i}",
        parameters: example_params,
        use_case: infer_use_case(example_params, prompt)
      }
    end)
  end

  defp generate_example_parameters(parameters, variant) do
    # Generate realistic example values for parameters
    required_params = Enum.reduce(parameters.required_parameters, %{}, fn param, acc ->
      example_value = case Map.get(parameters.parameter_types, param) do
        :enum -> 
          enum_values = get_in(parameters.validation_rules, [param, :enum]) || ["option1", "option2"]
          Enum.at(enum_values, rem(variant - 1, length(enum_values)))
        
        :integer -> variant * 10
        :float -> variant * 1.5
        :boolean -> rem(variant, 2) == 1
        :email -> "user#{variant}@example.com"
        _ -> "example_value_#{variant}"
      end
      
      Map.put(acc, param, example_value)
    end)
    
    # Add some optional parameters for variety
    optional_sample = parameters.optional_parameters
    |> Enum.take(min(2, length(parameters.optional_parameters)))
    |> Enum.reduce(%{}, fn param, acc ->
      default_value = Map.get(parameters.default_values, param, "optional_value_#{variant}")
      Map.put(acc, param, default_value)
    end)
    
    Map.merge(required_params, optional_sample)
  end

  defp infer_use_case(example_params, prompt) do
    # Simple heuristic to infer use case from parameters and prompt
    param_context = example_params
    |> Map.values()
    |> Enum.join(" ")
    |> String.downcase()
    
    cond do
      String.contains?(param_context <> prompt, ["code", "function", "bug"]) ->
        "Software development task"
      String.contains?(param_context <> prompt, ["data", "analysis", "report"]) ->
        "Data analysis task"
      String.contains?(param_context <> prompt, ["write", "content", "article"]) ->
        "Content creation task"
      true ->
        "General purpose task"
    end
  end

  defp initialize_performance_tracking do
    %{
      usage_count: 0,
      success_rate: 0.0,
      average_response_quality: 0.0,
      average_response_time: 0,
      user_satisfaction: 0.0,
      last_used: nil,
      performance_trend: :stable
    }
  end

  defp extract_validation_rules(prompt) do
    # Extract validation rules from the prompt structure and parameters
    %{
      max_prompt_length: 5000,
      required_sections: extract_required_sections(prompt),
      parameter_constraints: extract_parameter_constraints(prompt),
      content_guidelines: extract_content_guidelines(prompt)
    }
  end

  defp extract_required_sections(prompt) do
    # Identify sections that appear to be required based on structure
    sections = []
    
    if String.contains?(prompt, ["## Context", "Context:"]) do
      sections = sections ++ [:context]
    end
    
    if String.contains?(prompt, ["## Task", "Task:", "Your task"]) do
      sections = sections ++ [:task]
    end
    
    if String.contains?(prompt, ["## Output", "Format:", "Provide"]) do
      sections = sections ++ [:output_specification]
    end
    
    sections
  end

  defp extract_parameter_constraints(_prompt) do
    # Extract implicit constraints from prompt content
    %{
      min_parameters: 1,
      max_parameters: 20,
      naming_convention: :snake_case
    }
  end

  defp extract_content_guidelines(prompt) do
    guidelines = []
    
    if String.contains?(prompt, ["specific", "detailed", "comprehensive"]) do
      guidelines = guidelines ++ [:require_specificity]
    end
    
    if String.contains?(prompt, ["example", "Example"]) do
      guidelines = guidelines ++ [:include_examples]
    end
    
    if String.contains?(prompt, ["step", "steps", "process"]) do
      guidelines = guidelines ++ [:structured_output]
    end
    
    guidelines
  end

  defp generate_optimization_suggestions(prompt) do
    suggestions = []
    
    # Check for redundancy
    if has_redundant_content?(prompt) do
      suggestions = suggestions ++ [%{type: :reduce_redundancy, priority: :medium}]
    end
    
    # Check for clarity issues
    if has_clarity_issues?(prompt) do
      suggestions = suggestions ++ [%{type: :improve_clarity, priority: :high}]
    end
    
    # Check for length optimization
    if String.length(prompt) > 2000 do
      suggestions = suggestions ++ [%{type: :optimize_length, priority: :low}]
    end
    
    suggestions
  end

  defp has_redundant_content?(prompt) do
    # Simple check for repeated phrases
    words = String.split(prompt, ~r/\s+/)
    word_count = length(words)
    unique_words = length(Enum.uniq(words))
    
    # If less than 70% unique words, consider it redundant
    unique_words / word_count < 0.7
  end

  defp has_clarity_issues?(prompt) do
    # Check for vague language
    vague_indicators = ["something", "things", "stuff", "etc", "and so on"]
    String.downcase(prompt) |> then(fn p ->
      Enum.any?(vague_indicators, fn indicator -> String.contains?(p, indicator) end)
    end)
  end

  defp optimize_template_for_reuse(template) do
    # Add optimization suggestions based on analysis
    optimization_suggestions = analyze_reusability(template.template_content)
    
    %{template | optimization_suggestions: optimization_suggestions}
  end

  defp analyze_reusability(template_content) do
    suggestions = []
    
    # Check parameterization opportunities
    hardcoded_values = find_hardcoded_values(template_content)
    if length(hardcoded_values) > 0 do
      suggestions = suggestions ++ [%{
        type: :parameterize_hardcoded_values,
        description: "Consider parameterizing: #{Enum.join(hardcoded_values, ", ")}",
        impact: :medium
      }]
    end
    
    # Check for modularity opportunities
    if String.length(template_content) > 1000 && not has_section_structure?(template_content) do
      suggestions = suggestions ++ [%{
        type: :add_modular_structure,
        description: "Consider breaking into smaller, reusable sections",
        impact: :high
      }]
    end
    
    suggestions
  end

  defp find_hardcoded_values(template_content) do
    # Find values that look like they could be parameterized
    # This is a simplified heuristic
    potential_values = []
    
    # Find quoted strings that might be hardcoded
    quoted_strings = Regex.scan(~r/"([^"]{3,})"/, template_content)
    |> Enum.map(fn [_full, content] -> content end)
    |> Enum.reject(fn s -> String.contains?(s, [" ", "\n"]) end)  # Skip sentences
    
    # Find numbers that might be configurable
    numbers = Regex.scan(~r/\b(\d+(?:\.\d+)?)\b/, template_content)
    |> Enum.map(fn [_full, num] -> num end)
    |> Enum.reject(fn n -> n in ["1", "2"] end)  # Skip common numbers
    
    potential_values ++ quoted_strings ++ numbers
    |> Enum.take(5)  # Limit suggestions
  end

  defp has_section_structure?(template_content) do
    String.contains?(template_content, ["##", "**", "###", "---"])
  end

  defp validate_required_parameters!(template, parameters) do
    missing = template.parameters.required_parameters
    |> Enum.reject(fn param -> Map.has_key?(parameters, param) end)
    
    if length(missing) > 0 do
      raise ArgumentError, "Required parameter '#{hd(missing)}' is missing"
    end
  end

  defp validate_parameter_values!(template, parameters) do
    Enum.each(parameters, fn {param_name, value} ->
      validation_rules = Map.get(template.parameters.validation_rules, param_name, %{})
      
      # Validate enum values
      if Map.has_key?(validation_rules, :enum) do
        unless Enum.member?(validation_rules.enum, value) do
          raise ArgumentError, "Invalid value '#{value}' for enum parameter '#{param_name}'"
        end
      end
      
      # Validate string length
      if is_binary(value) && Map.has_key?(validation_rules, :min_length) do
        unless String.length(value) >= validation_rules.min_length do
          raise ArgumentError, "Parameter '#{param_name}' is too short (minimum #{validation_rules.min_length} characters)"
        end
      end
      
      # Add more validations as needed
    end)
  end

  defp substitute_template_parameters(template_content, parameters, parameter_definitions) do
    # Apply default values first
    merged_parameters = Map.merge(parameter_definitions.default_values, parameters)
    
    # Substitute simple parameters
    result = Enum.reduce(merged_parameters, template_content, fn {param_name, value}, content ->
      # Handle different parameter patterns
      content
      |> String.replace("{{#{param_name}}}", to_string(value))
      |> String.replace(~r/\{\{#{param_name}\s*\|[^}]*\}\}/, to_string(value))
    end)
    
    # Handle conditional logic
    result = process_conditional_logic(result, merged_parameters)
    
    result
  end

  defp process_conditional_logic(content, parameters) do
    # Process if statements
    content = Regex.replace(~r/\{\{#if\s+([^}]+)\}\}(.*?)\{\{\/if\}\}/s, content, fn _full, condition, inner_content ->
      if evaluate_condition(condition, parameters) do
        String.trim(inner_content)
      else
        ""
      end
    end)
    
    # Process unless statements
    content = Regex.replace(~r/\{\{#unless\s+([^}]+)\}\}(.*?)\{\{\/unless\}\}/s, content, fn _full, condition, inner_content ->
      if not evaluate_condition(condition, parameters) do
        String.trim(inner_content)
      else
        ""
      end
    end)
    
    # Process each loops
    content = Regex.replace(~r/\{\{#each\s+([^}]+)\}\}(.*?)\{\{\/each\}\}/s, content, fn _full, variable, inner_content ->
      case Map.get(parameters, variable) do
        list when is_list(list) ->
          Enum.map(list, fn item ->
            String.replace(inner_content, "{{this}}", to_string(item))
          end)
          |> Enum.join("\n")
        
        _ ->
          ""
      end
    end)
    
    content
  end

  defp evaluate_condition(condition, parameters) do
    # Simple condition evaluation
    condition = String.trim(condition)
    
    cond do
      String.contains?(condition, "==") ->
        [left, right] = String.split(condition, "==") |> Enum.map(&String.trim/1)
        get_value(left, parameters) == parse_literal(right)
      
      String.contains?(condition, "!=") ->
        [left, right] = String.split(condition, "!=") |> Enum.map(&String.trim/1)
        get_value(left, parameters) != parse_literal(right)
      
      # Simple boolean check
      true ->
        case Map.get(parameters, condition) do
          nil -> false
          false -> false
          "" -> false
          0 -> false
          _ -> true
        end
    end
  end

  defp get_value(key, parameters) do
    Map.get(parameters, key, key)
  end

  defp parse_literal(value) do
    value = String.trim(value)
    
    cond do
      String.starts_with?(value, "\"") && String.ends_with?(value, "\"") ->
        String.slice(value, 1..-2)
      
      value in ["true", "false"] ->
        value == "true"
      
      String.match?(value, ~r/^\d+$/) ->
        String.to_integer(value)
      
      String.match?(value, ~r/^\d+\.\d+$/) ->
        String.to_float(value)
      
      true ->
        value
    end
  end

  defp apply_template_transformations(content) do
    # Apply formatting and normalization transformations
    content
    |> normalize_spacing()
    |> apply_case_normalization()
    |> clean_empty_lines()
  end

  defp normalize_spacing(content) do
    # Normalize spacing around punctuation and sections
    content
    |> String.replace(~r/\s*\n\s*\n\s*/, "\n\n")  # Multiple newlines to double
    |> String.replace(~r/\s+/, " ")               # Multiple spaces to single
    |> String.replace(~r/\s*\n\s*/, "\n")         # Clean line breaks
  end

  defp apply_case_normalization(content) do
    # Apply smart case normalization (capitalize sentences, etc.)
    content
    |> String.replace(~r/\.\s+([a-z])/, fn match ->
      String.upcase(String.slice(match, -1..-1)) |> then(fn upper ->
        String.slice(match, 0..-2) <> upper
      end)
    end)
  end

  defp clean_empty_lines(content) do
    # Remove excessive empty lines but preserve intentional structure
    content
    |> String.replace(~r/\n\n\n+/, "\n\n")
    |> String.trim()
  end

  defp validate_instantiated_prompt!(content) do
    # Validate that the instantiated prompt doesn't have issues
    cond do
      String.contains?(content, "{{") ->
        raise ArgumentError, "Invalid template nesting detected"
      
      String.length(content) < 10 ->
        raise ArgumentError, "Instantiated prompt is too short"
      
      String.length(content) > 10000 ->
        raise ArgumentError, "Instantiated prompt is too long"
      
      true ->
        content
    end
  end
end