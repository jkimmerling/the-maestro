defmodule TheMaestro.Prompts.EngineeringTools.TemplateManager do
  @moduledoc """
  Comprehensive prompt template management system with parameterization,
  versioning, performance tracking, and optimization capabilities.
  """

  import Ecto.Query
  alias TheMaestro.Repo
  alias __MODULE__.PromptTemplate

  # Type definitions
  @type template_id :: String.t()
  @type template_name :: String.t()
  @type template_content :: String.t()
  @type template_category :: String.t()
  @type parameter_key :: String.t()
  @type parameter_value :: any()
  @type parameters :: %{parameter_key() => parameter_value()}
  @type metadata :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:category) => String.t(),
          optional(:tags) => [String.t()],
          optional(:created_by) => String.t()
        }
  @type template_result :: {:ok, PromptTemplate.t()} | {:error, Ecto.Changeset.t()}
  @type instantiation_result :: {:ok, String.t()} | {:error, String.t()}
  @type usage_example :: %{
          parameters: parameters(),
          expected_output: String.t(),
          use_case: String.t()
        }
  @type performance_metrics :: %{
          creation_date: DateTime.t(),
          usage_count: non_neg_integer(),
          avg_tokens: float(),
          success_rate: float()
        }
  @type validation_rule :: %{
          parameter: String.t(),
          constraint: String.t(),
          message: String.t()
        }

  defmodule PromptTemplate do
    @moduledoc """
    Represents a parameterized prompt template with metadata and performance tracking.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "prompt_templates" do
      field :template_id, :string  # Common ID across all versions
      field :name, :string
      field :description, :string
      field :category, :string
      field :template_content, :string
      field :parameters, :map
      field :usage_examples, {:array, :map}
      field :performance_metrics, :map
      field :version, :integer, default: 1
      field :parent_version, :integer
      field :created_by, :string
      field :tags, {:array, :string}
      field :validation_rules, :map
      field :optimization_suggestions, {:array, :string}

      timestamps()
    end

    def changeset(template, attrs) do
      template
      |> cast(attrs, [
        :template_id, :name, :description, :category, :template_content,
        :parameters, :usage_examples, :performance_metrics,
        :version, :parent_version, :created_by, :tags,
        :validation_rules, :optimization_suggestions
      ])
      |> validate_required([:template_id, :name, :template_content, :category, :created_by])
      |> validate_length(:name, min: 1, max: 255)
      |> validate_length(:description, max: 1000)
    end
  end

  defmodule ParameterDefinition do
    @moduledoc """
    Defines template parameters with types, validation, and relationships.
    """
    @derive Jason.Encoder
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

      modifiers =
        Enum.drop(parts, 1)
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
      value = String.trim_leading(modifier, prefix) |> String.trim()
      
      # Remove surrounding quotes if present
      cond do
        String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
          String.slice(value, 1..-2//1)
        String.starts_with?(value, "'") and String.ends_with?(value, "'") ->
          String.slice(value, 1..-2//1)
        true ->
          value
      end
    end

    defp parse_enum_list(value) do
      value
      |> String.trim_leading("[")
      |> String.trim_trailing("]")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    end

    defp parse_number(value) do
      case Float.parse(value) do
        {num, ""} ->
          num

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
        type =
          cond do
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

        rules =
          if Map.get(param, :required, false), do: Map.put(rules, :required, true), else: rules

        rules =
          if Map.has_key?(param, :min_length),
            do: Map.put(rules, :min_length, param.min_length),
            else: rules

        rules =
          if Map.has_key?(param, :max_length),
            do: Map.put(rules, :max_length, param.max_length),
            else: rules

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
      if_conditions =
        Regex.scan(~r/\{\{#if\s+([^}]+)\}\}/, template_content)
        |> Enum.map(fn [_full, condition] ->
          %{type: :if, condition: String.trim(condition)}
        end)

      # Extract unless conditions
      unless_conditions =
        Regex.scan(~r/\{\{#unless\s+([^}]+)\}\}/, template_content)
        |> Enum.map(fn [_full, condition] ->
          %{type: :unless, condition: String.trim(condition)}
        end)

      # Extract each loops
      each_conditions =
        Regex.scan(~r/\{\{#each\s+([^}]+)\}\}/, template_content)
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
  @spec create_template_from_prompt(template_content(), metadata()) :: template_result()
  def create_template_from_prompt(prompt, metadata) do
    # Validate template syntax first
    case validate_template_structure(prompt) do
      {:error, reason} ->
        raise ArgumentError, "Invalid template syntax: #{reason}"

      :ok ->
        parameters = TemplateParameters.define_template_parameters(prompt)

        template_id = generate_template_id()
        
        attrs = %{
          template_id: template_id,
          name: metadata.name,
          description: metadata.description,
          category: to_string(metadata.category),
          template_content: extract_template_structure(prompt),
          parameters: parameters,
          usage_examples: generate_usage_examples(prompt, parameters),
          performance_metrics: initialize_performance_tracking(),
          version: 1,
          parent_version: nil,
          created_by: metadata.author,
          tags: metadata.tags || [],
          validation_rules: extract_validation_rules(prompt),
          optimization_suggestions: generate_optimization_suggestions(prompt)
        }

        {:ok, template} = %PromptTemplate{}
        |> PromptTemplate.changeset(attrs)
        |> Repo.insert()

        optimize_template_for_reuse(template)
    end
  end

  @doc """
  Instantiates a template with provided parameters.
  """
  @spec instantiate_template(PromptTemplate.t(), parameters()) :: instantiation_result()
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
  @spec get_template_categories() :: %{atom() => String.t()}
  def get_template_categories, do: @template_categories

  @doc """
  Gets templates by category.
  """
  @spec get_templates_by_category(template_category()) :: [PromptTemplate.t()]
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
            template_content:
              "Review the following {{language}} code for security vulnerabilities...",
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
  @spec search_templates_by_tag(String.t()) :: [PromptTemplate.t()]
  def search_templates_by_tag(_tag) do
    # In a real implementation, this would search a database
    # Return mock results for testing
    []
  end

  @doc """
  Updates an existing template.
  """
  @spec update_template(PromptTemplate.t(), template_content()) :: template_result()
  def update_template(template, new_content) do
    # Create a new version as a separate database record
    new_parameters = TemplateParameters.define_template_parameters(new_content)
    
    attrs = %{
      template_id: template.template_id,  # Keep the same template_id
      name: template.name,
      description: template.description,
      category: template.category,
      template_content: new_content,
      parameters: new_parameters,
      usage_examples: template.usage_examples,
      performance_metrics: template.performance_metrics,
      version: template.version + 1,
      parent_version: template.version,
      created_by: template.created_by,
      tags: template.tags,
      validation_rules: template.validation_rules,
      optimization_suggestions: generate_optimization_suggestions(new_content)
    }

    {:ok, new_template} = %PromptTemplate{}
    |> PromptTemplate.changeset(attrs)
    |> Repo.insert()

    new_template
  end

  @doc """
  Gets version history for a template.
  """
  @spec get_template_version_history(template_id()) :: [PromptTemplate.t()]
  def get_template_version_history(id) do
    # First, find the template to get its template_id
    case Repo.get(PromptTemplate, id) do
      nil -> []
      template ->
        # Now find all versions with the same template_id
        from(t in PromptTemplate,
          where: t.template_id == ^template.template_id,
          order_by: [asc: t.version]
        )
        |> Repo.all()
    end
  end

  @doc """
  Tracks template usage for analytics.
  """
  @spec track_template_usage(String.t(), template_id()) :: String.t()
  def track_template_usage(instantiated_prompt, _template_id) do
    # In a real implementation, this would update usage statistics
    # For now, we just return the instantiated prompt
    instantiated_prompt
  end

  # Private helper functions

  @spec generate_template_id() :: String.t()
  defp generate_template_id do
    "tpl_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  @spec validate_template_structure(String.t()) :: :ok | {:error, String.t()}
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

  @spec extract_template_structure(String.t()) :: String.t()
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
    # Multiple newlines to double newline
    |> String.replace(~r/\n\s*\n\s*\n+/, "\n\n")
    # Multiple spaces/tabs to single space
    |> String.replace(~r/[ \t]+/, " ")
  end

  defp normalize_template_tags(text) do
    # Normalize template tag spacing
    text
    |> String.replace(~r/\{\{\s+/, "{{")
    |> String.replace(~r/\s+\}\}/, "}}")
  end

  @spec generate_usage_examples(String.t(), map()) :: [usage_example()]
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
    required_params =
      Enum.reduce(parameters.required_parameters, %{}, fn param, acc ->
        example_value =
          case Map.get(parameters.parameter_types, param) do
            :enum ->
              enum_values =
                get_in(parameters.validation_rules, [param, :enum]) || ["option1", "option2"]

              Enum.at(enum_values, rem(variant - 1, length(enum_values)))

            :integer ->
              variant * 10

            :float ->
              variant * 1.5

            :boolean ->
              rem(variant, 2) == 1

            :email ->
              "user#{variant}@example.com"

            _ ->
              "example_value_#{variant}"
          end

        Map.put(acc, param, example_value)
      end)

    # Add some optional parameters for variety
    optional_sample =
      parameters.optional_parameters
      |> Enum.take(min(2, length(parameters.optional_parameters)))
      |> Enum.reduce(%{}, fn param, acc ->
        default_value = Map.get(parameters.default_values, param, "optional_value_#{variant}")
        Map.put(acc, param, default_value)
      end)

    Map.merge(required_params, optional_sample)
  end

  defp infer_use_case(example_params, prompt) do
    # Simple heuristic to infer use case from parameters and prompt
    param_context =
      example_params
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

  @spec initialize_performance_tracking() :: performance_metrics()
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

    sections = if String.contains?(prompt, ["## Context", "Context:"]) do
      sections ++ [:context]
    else
      sections
    end

    sections = if String.contains?(prompt, ["## Task", "Task:", "Your task"]) do
      sections ++ [:task]
    else
      sections
    end

    sections = if String.contains?(prompt, ["## Output", "Format:", "Provide"]) do
      sections ++ [:output_specification]
    else
      sections
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

    guidelines = if String.contains?(prompt, ["specific", "detailed", "comprehensive"]) do
      guidelines ++ [:require_specificity]
    else
      guidelines
    end

    guidelines = if String.contains?(prompt, ["example", "Example"]) do
      guidelines ++ [:include_examples]
    else
      guidelines
    end

    guidelines = if String.contains?(prompt, ["step", "steps", "process"]) do
      guidelines ++ [:structured_output]
    else
      guidelines
    end

    guidelines
  end

  @spec generate_optimization_suggestions(String.t()) :: [String.t()]
  defp generate_optimization_suggestions(prompt) do
    suggestions = []

    # Check for redundancy
    suggestions = if has_redundant_content?(prompt) do
      suggestions ++ ["Consider reducing redundant content to improve clarity and conciseness"]
    else
      suggestions
    end

    # Check for clarity issues
    suggestions = if has_clarity_issues?(prompt) do
      suggestions ++ ["Improve prompt clarity by using more specific language and examples"]
    else
      suggestions
    end

    # Check for length optimization
    suggestions = if String.length(prompt) > 2000 do
      suggestions ++ ["Consider shortening the prompt while maintaining essential information"]
    else
      suggestions
    end

    suggestions
  end

  defp has_redundant_content?(prompt) do
    # Check for repeated phrases and words
    words = String.split(prompt, ~r/\s+/) 
      |> Enum.map(&String.downcase/1)
      |> Enum.map(fn w -> String.replace(w, ~r/[^\w]/, "") end) # Remove punctuation
      |> Enum.reject(&(&1 == ""))

    word_count = length(words)
    unique_words = length(Enum.uniq(words))

    # If less than 80% unique words, consider it redundant
    unique_ratio = unique_words / word_count
    
    # Debug info for development
    # IO.puts("Word count: #{word_count}, Unique: #{unique_words}, Ratio: #{unique_ratio}")
    
    unique_ratio < 0.8
  end

  defp has_clarity_issues?(prompt) do
    # Check for vague language
    vague_indicators = ["something", "things", "stuff", "etc", "and so on"]

    String.downcase(prompt)
    |> then(fn p ->
      Enum.any?(vague_indicators, fn indicator -> String.contains?(p, indicator) end)
    end)
  end

  defp optimize_template_for_reuse(template) do
    # Add additional optimization suggestions based on reusability analysis
    reusability_suggestions = analyze_reusability(template.template_content)
    
    # Merge with existing optimization suggestions
    all_suggestions = template.optimization_suggestions ++ reusability_suggestions

    %{template | optimization_suggestions: all_suggestions}
  end

  defp analyze_reusability(template_content) do
    suggestions = []

    # Check parameterization opportunities
    hardcoded_values = find_hardcoded_values(template_content)

    suggestions = if length(hardcoded_values) > 0 do
      suggestions ++
        [
          %{
            type: :parameterize_hardcoded_values,
            description: "Consider parameterizing: #{Enum.join(hardcoded_values, ", ")}",
            impact: :medium
          }
        ]
    else
      suggestions
    end

    # Check for modularity opportunities
    suggestions = if String.length(template_content) > 1000 && not has_section_structure?(template_content) do
      suggestions ++
        [
          %{
            type: :add_modular_structure,
            description: "Consider breaking into smaller, reusable sections",
            impact: :high
          }
        ]
    else
      suggestions
    end

    suggestions
  end

  defp find_hardcoded_values(template_content) do
    # Find values that look like they could be parameterized
    # This is a simplified heuristic
    potential_values = []

    # Find quoted strings that might be hardcoded
    quoted_strings =
      Regex.scan(~r/"([^"]{3,})"/, template_content)
      |> Enum.map(fn [_full, content] -> content end)
      # Skip sentences
      |> Enum.reject(fn s -> String.contains?(s, [" ", "\n"]) end)

    # Find numbers that might be configurable
    numbers =
      Regex.scan(~r/\b(\d+(?:\.\d+)?)\b/, template_content)
      |> Enum.map(fn [_full, num] -> num end)
      # Skip common numbers
      |> Enum.reject(fn n -> n in ["1", "2"] end)

    (potential_values ++ quoted_strings ++ numbers)
    # Limit suggestions
    |> Enum.take(5)
  end

  defp has_section_structure?(template_content) do
    String.contains?(template_content, ["##", "**", "###", "---"])
  end

  defp is_parameter_conditionally_required?(template_content, param_name) do
    # Check if parameter is inside a conditional block like {{#if condition}}{{param | required}}{{/if}}
    conditional_pattern = ~r/\{\{#if\s+\w+\}\}.*?\{\{#{param_name}\s*\|.*?required.*?\}\}.*?\{\{\/if\}\}/s
    Regex.match?(conditional_pattern, template_content)
  end

  defp should_validate_conditional_param?(template_content, param_name, parameters) do
    # Find the condition for this parameter
    # Look for patterns like {{#if include_context}}...{{context | required}}...{{/if}}
    conditional_pattern = ~r/\{\{#if\s+(\w+)\}\}.*?\{\{#{param_name}\s*\|.*?required.*?\}\}.*?\{\{\/if\}\}/s
    
    case Regex.run(conditional_pattern, template_content) do
      [_, condition_param] ->
        # Check if the condition parameter is truthy
        condition_value = Map.get(parameters, condition_param)
        is_truthy_value?(condition_value)
      _ ->
        # If we can't find the pattern, default to requiring validation
        true
    end
  end

  defp is_truthy_value?(nil), do: false
  defp is_truthy_value?(false), do: false
  defp is_truthy_value?("false"), do: false
  defp is_truthy_value?(0), do: false
  defp is_truthy_value?(""), do: false
  defp is_truthy_value?(_), do: true

  defp validate_required_parameters!(template, parameters) do
    # Get unconditionally required parameters
    unconditional_missing =
      template.parameters.required_parameters
      |> Enum.filter(fn param -> 
        # Check if this parameter is inside a conditional block
        not is_parameter_conditionally_required?(template.template_content, param)
      end)
      |> Enum.reject(fn param -> Map.has_key?(parameters, param) end)
    
    # Check conditionally required parameters
    conditional_missing = 
      template.parameters.required_parameters
      |> Enum.filter(fn param ->
        is_parameter_conditionally_required?(template.template_content, param)
      end)
      |> Enum.filter(fn param ->
        # Only check if the condition is true
        should_validate_conditional_param?(template.template_content, param, parameters)
      end)
      |> Enum.reject(fn param -> Map.has_key?(parameters, param) end)
    
    missing = unconditional_missing ++ conditional_missing

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
          raise ArgumentError,
                "Parameter '#{param_name}' is too short (minimum #{validation_rules.min_length} characters)"
        end
      end

      # Add more validations as needed
    end)
  end

  defp substitute_template_parameters(template_content, parameters, parameter_definitions) do
    # Apply default values first
    merged_parameters = Map.merge(parameter_definitions.default_values, parameters)

    # Substitute simple parameters
    result =
      Enum.reduce(merged_parameters, template_content, fn {param_name, value}, content ->
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
    content =
      Regex.replace(~r/\{\{#if\s+([^}]+)\}\}(.*?)\{\{\/if\}\}/s, content, fn _full,
                                                                             condition,
                                                                             inner_content ->
        if evaluate_condition(condition, parameters) do
          String.trim(inner_content)
        else
          ""
        end
      end)

    # Process unless statements
    content =
      Regex.replace(~r/\{\{#unless\s+([^}]+)\}\}(.*?)\{\{\/unless\}\}/s, content, fn _full,
                                                                                     condition,
                                                                                     inner_content ->
        if not evaluate_condition(condition, parameters) do
          String.trim(inner_content)
        else
          ""
        end
      end)

    # Process each loops
    content =
      Regex.replace(~r/\{\{#each\s+([^}]+)\}\}(.*?)\{\{\/each\}\}/s, content, fn _full,
                                                                                 variable,
                                                                                 inner_content ->
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
        String.slice(value, 1..-2//1)

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
    # Multiple newlines to double
    |> String.replace(~r/\s*\n\s*\n\s*/, "\n\n")
    # Multiple spaces to single
    |> String.replace(~r/\s+/, " ")
    # Clean line breaks
    |> String.replace(~r/\s*\n\s*/, "\n")
  end

  defp apply_case_normalization(content) do
    # Apply smart case normalization (capitalize sentences, title case for roles/names, etc.)
    content
    |> String.replace(~r/\.\s+([a-z])/, fn match ->
      String.upcase(String.slice(match, -1..-1))
      |> then(fn upper ->
        String.slice(match, 0..-2//1) <> upper
      end)
    end)
    # Convert all-caps words to title case for better readability
    |> String.replace(~r/\b[A-Z]{2,}(?:\s+[A-Z]{2,})*\b/, fn all_caps ->
      all_caps
      |> String.split()
      |> Enum.map(fn word ->
        String.downcase(word) |> String.capitalize()
      end)
      |> Enum.join(" ")
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
