defmodule TheMaestro.MCP.Config.TemplateParser do
  @moduledoc """
  Template processing for MCP server configurations.

  Supports variable substitution in configuration templates using `{variable}` syntax,
  with comprehensive error handling and validation.
  """

  require Logger

  @type template :: map()
  @type variables :: map()
  @type validation_result :: {:ok, template()} | {:error, [String.t()]}

  @doc """
  Apply template variables to a configuration template.

  Recursively processes the template structure, replacing `{variable}` placeholders
  with values from the variables map.

  ## Examples

      iex> template = %{"command" => "{command}", "args" => ["-m", "{module}"]}
      iex> variables = %{"command" => "python", "module" => "server"}
      iex> TemplateParser.apply_template(template, variables)
      %{"command" => "python", "args" => ["-m", "server"]}
  """
  @spec apply_template(template(), variables()) :: template()
  def apply_template(template, variables) do
    apply_template_recursive(template, variables)
  end

  @doc """
  Extract all variable references from a template.

  Returns a list of unique variable names found in the template.

  ## Examples

      iex> template = %{"cmd" => "{command}", "env" => %{"{var}" => "{value}"}}
      iex> TemplateParser.extract_variables(template)
      ["command", "var", "value"]
  """
  @spec extract_variables(template()) :: [String.t()]
  def extract_variables(template) do
    template
    |> extract_variables_recursive([])
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Validate template structure and variable usage.

  Performs comprehensive validation of template syntax and structure.
  """
  @spec validate_template(template()) :: validation_result()
  def validate_template(template) do
    errors = []

    errors =
      errors
      |> validate_template_structure(template)
      |> validate_variable_syntax(template)
      |> validate_required_template_fields(template)

    case errors do
      [] -> {:ok, template}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Validate that all template variables have corresponding values.

  Returns errors for any variables referenced in the template but not
  provided in the variables map.
  """
  @spec validate_template_variables(template(), variables()) :: validation_result()
  def validate_template_variables(template, variables) do
    template_vars = extract_variables(template)
    provided_vars = Map.keys(variables) |> Enum.map(&to_string/1)
    missing_vars = template_vars -- provided_vars

    case missing_vars do
      [] ->
        {:ok, template}

      missing ->
        errors = Enum.map(missing, &"Missing template variable: #{&1}")
        {:error, errors}
    end
  end

  @doc """
  Create a template from an existing configuration by replacing values with variables.

  Useful for creating reusable templates from working configurations.
  """
  @spec create_template_from_config(map(), variables()) :: template()
  def create_template_from_config(config, variable_mappings) do
    create_template_recursive(config, variable_mappings)
  end

  @doc """
  Merge template with partial variables, leaving unresolved variables as-is.

  Useful for multi-stage template processing where some variables are resolved
  at different times.
  """
  @spec partial_apply_template(template(), variables()) :: template()
  def partial_apply_template(template, variables) do
    partial_apply_recursive(template, variables)
  end

  @doc """
  Get template metadata including variable information and validation status.
  """
  @spec get_template_metadata(template()) :: map()
  def get_template_metadata(template) do
    variables = extract_variables(template)

    %{
      variables: variables,
      variable_count: length(variables),
      validation: validate_template(template),
      complexity: calculate_template_complexity(template)
    }
  end

  ## Private Functions

  defp apply_template_recursive(template, variables) when is_map(template) do
    Enum.into(template, %{}, fn {key, value} ->
      resolved_key = apply_template_recursive(key, variables)
      resolved_value = apply_template_recursive(value, variables)
      {resolved_key, resolved_value}
    end)
  end

  defp apply_template_recursive(template, variables) when is_list(template) do
    Enum.map(template, fn item ->
      apply_template_recursive(item, variables)
    end)
  end

  defp apply_template_recursive(template, variables) when is_binary(template) do
    substitute_variables(template, variables)
  end

  defp apply_template_recursive(template, _variables), do: template

  defp substitute_variables(string, variables) do
    # Replace {variable} patterns
    Regex.replace(~r/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/, string, fn
      _full_match, var_name ->
        case Map.get(variables, var_name) || Map.get(variables, String.to_atom(var_name)) do
          nil ->
            Logger.warning("Template variable #{var_name} not found, leaving unchanged")
            "{#{var_name}}"

          value ->
            to_string(value)
        end
    end)
  end

  defp extract_variables_recursive(template, acc) when is_map(template) do
    Enum.reduce(template, acc, fn {key, value}, acc ->
      key_vars = extract_variables_recursive(key, [])
      value_vars = extract_variables_recursive(value, [])
      acc ++ key_vars ++ value_vars
    end)
  end

  defp extract_variables_recursive(template, acc) when is_list(template) do
    Enum.reduce(template, acc, fn item, acc ->
      extract_variables_recursive(item, acc)
    end)
  end

  defp extract_variables_recursive(template, acc) when is_binary(template) do
    vars =
      Regex.scan(~r/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/, template)
      |> Enum.map(fn [_, var_name] -> var_name end)

    acc ++ vars
  end

  defp extract_variables_recursive(_template, acc), do: acc

  defp validate_template_structure(errors, template) do
    case template do
      template when is_map(template) ->
        if map_size(template) == 0 do
          ["Template cannot be empty" | errors]
        else
          errors
        end

      _ ->
        ["Template must be a map" | errors]
    end
  end

  defp validate_variable_syntax(errors, template) do
    variables = extract_variables(template)

    Enum.reduce(variables, errors, fn var, acc_errors ->
      if Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, var) do
        acc_errors
      else
        ["Invalid variable name syntax: #{var}" | acc_errors]
      end
    end)
  end

  defp validate_required_template_fields(errors, template) do
    # Check for transport configuration - must have at least one transport type
    # Allow templates with variable keys that could resolve to transport fields
    has_transport =
      Map.has_key?(template, "command") ||
        Map.has_key?(template, "url") ||
        Map.has_key?(template, "httpUrl") ||
        template_has_transport_variables(template)

    if has_transport do
      errors
    else
      ["Template must specify at least one transport method (command, url, or httpUrl)" | errors]
    end
  end

  defp template_has_transport_variables(template) do
    # Check if any keys are variables that might resolve to transport fields
    Enum.any?(Map.keys(template), fn key ->
      is_binary(key) && String.contains?(key, "{")
    end)
  end

  defp create_template_recursive(config, mappings) when is_map(config) do
    Enum.into(config, %{}, fn {key, value} ->
      template_key = create_template_key(key, mappings)
      template_value = create_template_recursive(value, mappings)
      {template_key, template_value}
    end)
  end

  defp create_template_recursive(config, mappings) when is_list(config) do
    Enum.map(config, fn item ->
      create_template_recursive(item, mappings)
    end)
  end

  defp create_template_recursive(config, mappings) when is_binary(config) do
    create_template_value(config, mappings)
  end

  defp create_template_recursive(config, _mappings), do: config

  defp create_template_key(key, mappings) do
    case Map.get(mappings, key) do
      nil -> key
      var_name -> "{#{var_name}}"
    end
  end

  defp create_template_value(value, mappings) do
    case Map.get(mappings, value) do
      nil -> value
      var_name -> "{#{var_name}}"
    end
  end

  defp partial_apply_recursive(template, variables) when is_map(template) do
    Enum.into(template, %{}, fn {key, value} ->
      resolved_key = partial_apply_recursive(key, variables)
      resolved_value = partial_apply_recursive(value, variables)
      {resolved_key, resolved_value}
    end)
  end

  defp partial_apply_recursive(template, variables) when is_list(template) do
    Enum.map(template, fn item ->
      partial_apply_recursive(item, variables)
    end)
  end

  defp partial_apply_recursive(template, variables) when is_binary(template) do
    partial_substitute_variables(template, variables)
  end

  defp partial_apply_recursive(template, _variables), do: template

  defp partial_substitute_variables(string, variables) do
    # Only replace variables that have values, leave others unchanged
    Regex.replace(~r/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/, string, fn
      full_match, var_name ->
        case Map.get(variables, var_name) || Map.get(variables, String.to_atom(var_name)) do
          # Leave unchanged if no value provided
          nil -> full_match
          value -> to_string(value)
        end
    end)
  end

  defp calculate_template_complexity(template) do
    variables = extract_variables(template)

    %{
      variable_count: length(variables),
      depth: calculate_structure_depth(template),
      branching_factor: calculate_branching_factor(template)
    }
  end

  defp calculate_structure_depth(template, current_depth \\ 0)

  defp calculate_structure_depth(template, current_depth) when is_map(template) do
    if map_size(template) == 0 do
      current_depth
    else
      template
      |> Map.values()
      |> Enum.map(&calculate_structure_depth(&1, current_depth + 1))
      |> Enum.max()
    end
  end

  defp calculate_structure_depth(template, current_depth) when is_list(template) do
    if length(template) == 0 do
      current_depth
    else
      template
      |> Enum.map(&calculate_structure_depth(&1, current_depth + 1))
      |> Enum.max()
    end
  end

  defp calculate_structure_depth(_template, current_depth), do: current_depth

  defp calculate_branching_factor(template, max_branching \\ 0)

  defp calculate_branching_factor(template, max_branching) when is_map(template) do
    current_branching = map_size(template)

    child_branching =
      template
      |> Map.values()
      |> Enum.map(&calculate_branching_factor(&1, 0))
      |> Enum.max(fn -> 0 end)

    max(max_branching, max(current_branching, child_branching))
  end

  defp calculate_branching_factor(template, max_branching) when is_list(template) do
    current_branching = length(template)

    child_branching =
      template
      |> Enum.map(&calculate_branching_factor(&1, 0))
      |> Enum.max(fn -> 0 end)

    max(max_branching, max(current_branching, child_branching))
  end

  defp calculate_branching_factor(_template, max_branching), do: max_branching

  @doc """
  Validate template against a schema definition.

  Ensures that the template structure conforms to expected patterns
  and contains required elements.
  """
  @spec validate_template_schema(template(), map()) :: validation_result()
  def validate_template_schema(template, schema) do
    errors = validate_against_schema(template, schema, [])

    case errors do
      [] -> {:ok, template}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp validate_against_schema(template, schema, errors)
       when is_map(template) and is_map(schema) do
    # Validate required fields
    errors = validate_required_fields(errors, template, schema)

    # Validate field types and values
    Enum.reduce(template, errors, fn {key, value}, acc_errors ->
      case Map.get(schema, key) do
        nil ->
          if Map.get(schema, "_allow_extra", false) do
            acc_errors
          else
            ["Unexpected field in template: #{key}" | acc_errors]
          end

        field_schema ->
          validate_against_schema(value, field_schema, acc_errors)
      end
    end)
  end

  defp validate_against_schema(template, %{"type" => "string"}, errors)
       when is_binary(template) do
    errors
  end

  defp validate_against_schema(template, %{"type" => "string"}, errors) do
    ["Expected string value, got: #{inspect(template)}" | errors]
  end

  defp validate_against_schema(template, %{"type" => "array", "items" => item_schema}, errors)
       when is_list(template) do
    Enum.with_index(template)
    |> Enum.reduce(errors, fn {item, index}, acc_errors ->
      item_errors = validate_against_schema(item, item_schema, [])
      Enum.map(item_errors, &"Array item #{index}: #{&1}") ++ acc_errors
    end)
  end

  defp validate_against_schema(template, %{"type" => "array"}, errors) do
    ["Expected array value, got: #{inspect(template)}" | errors]
  end

  defp validate_against_schema(_template, _schema, errors) do
    # Default case - assume valid for now
    errors
  end

  defp validate_required_fields(errors, template, schema) do
    required_fields = Map.get(schema, "required", [])

    Enum.reduce(required_fields, errors, fn field, acc_errors ->
      if Map.has_key?(template, field) do
        acc_errors
      else
        ["Missing required field in template: #{field}" | acc_errors]
      end
    end)
  end
end
