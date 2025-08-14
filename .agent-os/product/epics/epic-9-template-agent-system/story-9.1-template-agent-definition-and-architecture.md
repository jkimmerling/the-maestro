# Story 9.1: Template Agent Definition & Architecture

## User Story

**As a** user of TheMaestro
**I want** a comprehensive and flexible template agent definition system
**so that** I can create reusable agent configurations that combine provider settings, model configurations, personas, tools, and deployment parameters into cohesive, shareable templates

## Acceptance Criteria

1. **Comprehensive Template Schema**: A complete JSON schema definition that captures all aspects of agent configuration including providers, models, personas, tools, and deployment settings
2. **Template Validation System**: Robust validation engine that ensures template integrity, dependency resolution, and configuration compatibility
3. **Multi-level Template Inheritance**: Support for template inheritance hierarchies allowing base templates to be extended and specialized
4. **Configuration Composition**: System for composing templates from multiple sources and resolving configuration conflicts
5. **Template Versioning**: Version management system with semantic versioning, migration paths, and compatibility tracking
6. **Provider Integration**: Deep integration with Epic 5's provider system for seamless provider and model configuration
7. **Persona Integration**: Seamless integration with Epic 8's persona system for persona configuration and application
8. **Tool Configuration**: Comprehensive tool configuration system leveraging Epic 6's MCP implementation
9. **Prompt Configuration**: Integration with Epic 7's prompt handling system for advanced prompt configurations
10. **Template Metadata Management**: Rich metadata system for template discovery, categorization, and organization
11. **Configuration Validation**: Real-time validation of template configurations with detailed error reporting
12. **Template Categories and Tagging**: Hierarchical categorization system with flexible tagging for template organization
13. **Template Dependencies**: System for managing template dependencies and ensuring dependency resolution
14. **Environment-specific Configurations**: Support for different configurations across development, staging, and production environments
15. **Template Security Model**: Security framework ensuring safe template sharing and execution
16. **Configuration Templating**: Support for parameterized templates with variable substitution
17. **Template Testing Framework**: Built-in testing capabilities for validating template functionality
18. **Performance Optimization**: Template configuration optimizations for fast instantiation and efficient resource usage
19. **Error Handling and Recovery**: Comprehensive error handling with graceful degradation and recovery mechanisms
20. **Template Documentation**: Embedded documentation system for template usage, parameters, and examples
21. **Backwards Compatibility**: Compatibility layer for managing template schema evolution
22. **Template Analytics Integration**: Built-in analytics hooks for tracking template usage and performance
23. **Configuration Migration Tools**: Automated tools for migrating legacy configurations to template format
24. **Template Preview System**: Preview capabilities for seeing template effects before instantiation
25. **Custom Configuration Extensions**: Extensibility framework for adding custom configuration options

## Technical Implementation

### Core Template Schema

```elixir
# lib/the_maestro/agent_templates/template.ex
defmodule TheMaestro.AgentTemplates.Template do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_templates" do
    field :name, :string
    field :display_name, :string
    field :description, :string
    field :version, :string, default: "1.0.0"
    field :category, :string
    field :tags, {:array, :string}, default: []
    field :is_public, :boolean, default: false
    field :is_featured, :boolean, default: false
    field :is_system_template, :boolean, default: false

    # Configuration fields
    field :provider_config, :map, default: %{}
    field :persona_config, :map, default: %{}
    field :tool_config, :map, default: %{}
    field :prompt_config, :map, default: %{}
    field :deployment_config, :map, default: %{}

    # Metadata and relationships
    field :usage_count, :integer, default: 0
    field :rating_average, :float, default: 0.0
    field :rating_count, :integer, default: 0
    field :last_used_at, :naive_datetime_usec
    field :schema_version, :string, default: "1.0"
    field :compatibility_matrix, :map, default: %{}

    belongs_to :author, TheMaestro.Accounts.User
    belongs_to :parent_template, __MODULE__
    belongs_to :organization, TheMaestro.Organizations.Organization
    
    has_many :child_templates, __MODULE__, foreign_key: :parent_template_id
    has_many :instantiations, TheMaestro.AgentTemplates.TemplateInstantiation
    has_many :ratings, TheMaestro.AgentTemplates.TemplateRating

    timestamps(type: :naive_datetime_usec)
  end

  @doc false
  def changeset(template, attrs) do
    template
    |> cast(attrs, [
      :name, :display_name, :description, :version, :category, :tags,
      :is_public, :is_featured, :is_system_template, :provider_config,
      :persona_config, :tool_config, :prompt_config, :deployment_config,
      :parent_template_id, :author_id, :organization_id, :schema_version
    ])
    |> validate_required([:name, :description, :author_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:display_name, max: 200)
    |> validate_length(:description, min: 10, max: 2000)
    |> validate_format(:name, ~r/^[a-z0-9_-]+$/, message: "must contain only lowercase letters, numbers, underscores, and hyphens")
    |> validate_inclusion(:category, valid_categories())
    |> validate_template_configuration()
    |> validate_template_inheritance()
    |> validate_template_dependencies()
    |> validate_version_format()
    |> unique_constraint([:name, :author_id])
    |> foreign_key_constraint(:parent_template_id)
    |> foreign_key_constraint(:author_id)
    |> foreign_key_constraint(:organization_id)
  end

  defp validate_template_configuration(changeset) do
    case get_field(changeset, :provider_config) do
      nil -> changeset
      config when is_map(config) ->
        case validate_provider_configuration(config) do
          {:ok, _} -> changeset
          {:error, errors} ->
            Enum.reduce(errors, changeset, fn {field, message}, acc ->
              add_error(acc, :provider_config, "#{field}: #{message}")
            end)
        end
    end
    |> validate_persona_configuration()
    |> validate_tool_configuration()
    |> validate_prompt_configuration()
    |> validate_deployment_configuration()
  end

  defp validate_template_inheritance(changeset) do
    parent_id = get_field(changeset, :parent_template_id)
    
    if parent_id do
      case check_inheritance_cycle(parent_id, get_field(changeset, :id)) do
        :ok -> changeset
        {:error, :inheritance_cycle} ->
          add_error(changeset, :parent_template_id, "would create inheritance cycle")
      end
    else
      changeset
    end
  end

  defp validate_template_dependencies(changeset) do
    # Validate that all referenced personas, tools, etc. exist and are accessible
    changeset
    |> validate_persona_dependencies()
    |> validate_tool_dependencies()
    |> validate_provider_dependencies()
  end

  defp validate_version_format(changeset) do
    version = get_field(changeset, :version)
    
    if version && !Regex.match?(~r/^\d+\.\d+\.\d+(-[a-zA-Z0-9-]+)?$/, version) do
      add_error(changeset, :version, "must be in semantic version format (e.g., 1.0.0)")
    else
      changeset
    end
  end

  defp valid_categories do
    [
      "development", "writing", "analysis", "research", "support",
      "education", "business", "creative", "technical", "general"
    ]
  end

  # Configuration validation functions

  defp validate_provider_configuration(config) do
    schema = %{
      "default_provider" => :string,
      "fallback_providers" => {:array, :string},
      "model_preferences" => :map,
      "provider_specific_settings" => :map
    }
    
    validate_against_schema(config, schema)
  end

  defp validate_persona_configuration(changeset) do
    config = get_field(changeset, :persona_config)
    
    if config && is_map(config) do
      case validate_persona_config_structure(config) do
        {:ok, _} -> changeset
        {:error, errors} ->
          Enum.reduce(errors, changeset, fn {field, message}, acc ->
            add_error(acc, :persona_config, "#{field}: #{message}")
          end)
      end
    else
      changeset
    end
  end

  defp validate_tool_configuration(changeset) do
    config = get_field(changeset, :tool_config)
    
    if config && is_map(config) do
      case validate_tool_config_structure(config) do
        {:ok, _} -> changeset
        {:error, errors} ->
          Enum.reduce(errors, changeset, fn {field, message}, acc ->
            add_error(acc, :tool_config, "#{field}: #{message}")
          end)
      end
    else
      changeset
    end
  end

  defp validate_prompt_configuration(changeset) do
    config = get_field(changeset, :prompt_config)
    
    if config && is_map(config) do
      case validate_prompt_config_structure(config) do
        {:ok, _} -> changeset
        {:error, errors} ->
          Enum.reduce(errors, changeset, fn {field, message}, acc ->
            add_error(acc, :prompt_config, "#{field}: #{message}")
          end)
      end
    else
      changeset
    end
  end

  defp validate_deployment_configuration(changeset) do
    config = get_field(changeset, :deployment_config)
    
    if config && is_map(config) do
      case validate_deployment_config_structure(config) do
        {:ok, _} -> changeset
        {:error, errors} ->
          Enum.reduce(errors, changeset, fn {field, message}, acc ->
            add_error(acc, :deployment_config, "#{field}: #{message}")
          end)
      end
    else
      changeset
    end
  end

  # Helper validation functions

  defp validate_persona_config_structure(config) do
    required_fields = ["primary_persona_id"]
    optional_fields = ["persona_hierarchy", "context_specific_personas", "persona_overrides"]
    
    errors = []
    
    # Check required fields
    errors = Enum.reduce(required_fields, errors, fn field, acc ->
      if Map.has_key?(config, field) do
        acc
      else
        [{field, "is required"} | acc]
      end
    end)
    
    # Validate persona references exist
    errors = if Map.has_key?(config, "primary_persona_id") do
      case validate_persona_exists(config["primary_persona_id"]) do
        true -> errors
        false -> [{"primary_persona_id", "persona does not exist"} | errors]
      end
    else
      errors
    end
    
    if errors == [] do
      {:ok, config}
    else
      {:error, errors}
    end
  end

  defp validate_tool_config_structure(config) do
    allowed_fields = ["required_tools", "optional_tools", "mcp_servers", "tool_permissions"]
    
    errors = []
    
    # Validate MCP server configurations
    errors = if Map.has_key?(config, "mcp_servers") do
      case validate_mcp_server_configs(config["mcp_servers"]) do
        {:ok, _} -> errors
        {:error, mcp_errors} -> mcp_errors ++ errors
      end
    else
      errors
    end
    
    if errors == [] do
      {:ok, config}
    else
      {:error, errors}
    end
  end

  defp validate_prompt_config_structure(config) do
    allowed_fields = [
      "system_instruction_template", "context_enhancement", "provider_optimization",
      "multi_modal_support", "prompt_templates", "context_window_management"
    ]
    
    # Validate prompt templates exist
    errors = if Map.has_key?(config, "prompt_templates") do
      case validate_prompt_templates(config["prompt_templates"]) do
        {:ok, _} -> []
        {:error, template_errors} -> template_errors
      end
    else
      []
    end
    
    if errors == [] do
      {:ok, config}
    else
      {:error, errors}
    end
  end

  defp validate_deployment_config_structure(config) do
    allowed_fields = [
      "auto_start", "session_timeout", "conversation_persistence",
      "analytics_enabled", "monitoring_level", "resource_limits"
    ]
    
    errors = []
    
    # Validate resource limits
    errors = if Map.has_key?(config, "resource_limits") do
      case validate_resource_limits(config["resource_limits"]) do
        {:ok, _} -> errors
        {:error, limit_errors} -> limit_errors ++ errors
      end
    else
      errors
    end
    
    if errors == [] do
      {:ok, config}
    else
      {:error, errors}
    end
  end

  # Dependency validation functions

  defp validate_persona_dependencies(changeset) do
    config = get_field(changeset, :persona_config)
    
    if config && is_map(config) do
      persona_ids = extract_persona_ids_from_config(config)
      
      case validate_personas_exist(persona_ids) do
        [] -> changeset
        missing_ids ->
          add_error(changeset, :persona_config, "referenced personas do not exist: #{Enum.join(missing_ids, ", ")}")
      end
    else
      changeset
    end
  end

  defp validate_tool_dependencies(changeset) do
    config = get_field(changeset, :tool_config)
    
    if config && is_map(config) do
      tool_names = extract_tool_names_from_config(config)
      
      case validate_tools_exist(tool_names) do
        [] -> changeset
        missing_tools ->
          add_error(changeset, :tool_config, "referenced tools do not exist: #{Enum.join(missing_tools, ", ")}")
      end
    else
      changeset
    end
  end

  defp validate_provider_dependencies(changeset) do
    config = get_field(changeset, :provider_config)
    
    if config && is_map(config) do
      providers = extract_providers_from_config(config)
      
      case validate_providers_available(providers) do
        [] -> changeset
        unavailable_providers ->
          add_error(changeset, :provider_config, "providers not available: #{Enum.join(unavailable_providers, ", ")}")
      end
    else
      changeset
    end
  end

  # Query helpers

  def for_user_query(query \\ __MODULE__, user_id) do
    from t in query, 
      where: t.author_id == ^user_id or t.is_public == true
  end

  def public_query(query \\ __MODULE__) do
    from t in query, where: t.is_public == true
  end

  def featured_query(query \\ __MODULE__) do
    from t in query, where: t.is_featured == true
  end

  def by_category_query(query \\ __MODULE__, category) do
    from t in query, where: t.category == ^category
  end

  def with_tags_query(query \\ __MODULE__, tags) when is_list(tags) do
    from t in query, where: fragment("? && ?", t.tags, ^tags)
  end

  def search_query(query \\ __MODULE__, search_term) do
    from t in query,
      where: ilike(t.name, ^"%#{search_term}%") or
             ilike(t.display_name, ^"%#{search_term}%") or
             ilike(t.description, ^"%#{search_term}%") or
             fragment("? && ARRAY[?]", t.tags, ^search_term)
  end

  # Utility functions

  defp check_inheritance_cycle(parent_id, child_id, visited \\ MapSet.new()) do
    if MapSet.member?(visited, parent_id) do
      {:error, :inheritance_cycle}
    else
      case TheMaestro.Repo.get(__MODULE__, parent_id) do
        nil -> :ok
        %{parent_template_id: nil} -> :ok
        %{parent_template_id: grandparent_id} ->
          check_inheritance_cycle(grandparent_id, child_id, MapSet.put(visited, parent_id))
      end
    end
  end

  defp validate_against_schema(data, schema) when is_map(data) and is_map(schema) do
    errors = Enum.reduce(schema, [], fn {key, expected_type}, acc ->
      case Map.get(data, key) do
        nil -> acc  # Optional field
        value -> 
          case validate_type(value, expected_type) do
            :ok -> acc
            {:error, message} -> [{key, message} | acc]
          end
      end
    end)
    
    if errors == [] do
      {:ok, data}
    else
      {:error, errors}
    end
  end

  defp validate_type(value, :string) when is_binary(value), do: :ok
  defp validate_type(value, :integer) when is_integer(value), do: :ok
  defp validate_type(value, :float) when is_float(value), do: :ok
  defp validate_type(value, :boolean) when is_boolean(value), do: :ok
  defp validate_type(value, :map) when is_map(value), do: :ok
  defp validate_type(value, {:array, _type}) when is_list(value), do: :ok
  defp validate_type(_value, expected_type), do: {:error, "expected #{expected_type}"}

  # Placeholder functions for external validations
  defp validate_persona_exists(_persona_id), do: true
  defp validate_personas_exist(_persona_ids), do: []
  defp validate_tools_exist(_tool_names), do: []
  defp validate_providers_available(_providers), do: []
  defp validate_mcp_server_configs(_configs), do: {:ok, []}
  defp validate_prompt_templates(_templates), do: {:ok, []}
  defp validate_resource_limits(_limits), do: {:ok, []}
  
  defp extract_persona_ids_from_config(config) do
    ids = []
    ids = if config["primary_persona_id"], do: [config["primary_persona_id"] | ids], else: ids
    ids = if config["persona_hierarchy"], do: config["persona_hierarchy"] ++ ids, else: ids
    
    if config["context_specific_personas"] do
      Map.values(config["context_specific_personas"]) ++ ids
    else
      ids
    end
  end

  defp extract_tool_names_from_config(config) do
    tools = []
    tools = if config["required_tools"], do: config["required_tools"] ++ tools, else: tools
    tools = if config["optional_tools"], do: config["optional_tools"] ++ tools, else: tools
    tools
  end

  defp extract_providers_from_config(config) do
    providers = []
    providers = if config["default_provider"], do: [config["default_provider"] | providers], else: providers
    providers = if config["fallback_providers"], do: config["fallback_providers"] ++ providers, else: providers
    providers
  end
end
```

### Template Schema Validation System

```elixir
# lib/the_maestro/agent_templates/schema_validator.ex
defmodule TheMaestro.AgentTemplates.SchemaValidator do
  @moduledoc """
  Comprehensive schema validation system for agent templates.
  """

  @current_schema_version "1.0"

  @template_schema %{
    "schema_version" => %{type: :string, required: true},
    "name" => %{type: :string, required: true, min_length: 1, max_length: 100},
    "display_name" => %{type: :string, max_length: 200},
    "description" => %{type: :string, required: true, min_length: 10, max_length: 2000},
    "category" => %{type: :string, enum: ["development", "writing", "analysis", "research", "support", "education", "business", "creative", "technical", "general"]},
    "tags" => %{type: {:array, :string}},
    "version" => %{type: :string, pattern: ~r/^\d+\.\d+\.\d+(-[a-zA-Z0-9-]+)?$/},
    "provider_config" => %{type: :map, schema: :provider_config_schema},
    "persona_config" => %{type: :map, schema: :persona_config_schema},
    "tool_config" => %{type: :map, schema: :tool_config_schema},
    "prompt_config" => %{type: :map, schema: :prompt_config_schema},
    "deployment_config" => %{type: :map, schema: :deployment_config_schema}
  }

  @provider_config_schema %{
    "default_provider" => %{type: :string, required: true, enum: ["anthropic", "openai", "gemini"]},
    "fallback_providers" => %{type: {:array, :string}},
    "model_preferences" => %{type: :map},
    "provider_specific_settings" => %{
      type: :map,
      schema: %{
        "temperature" => %{type: :float, min: 0.0, max: 2.0},
        "max_tokens" => %{type: :integer, min: 1, max: 32768},
        "top_p" => %{type: :float, min: 0.0, max: 1.0},
        "frequency_penalty" => %{type: :float, min: -2.0, max: 2.0},
        "presence_penalty" => %{type: :float, min: -2.0, max: 2.0}
      }
    }
  }

  @persona_config_schema %{
    "primary_persona_id" => %{type: :string, required: true},
    "persona_hierarchy" => %{type: {:array, :string}},
    "context_specific_personas" => %{type: :map},
    "persona_overrides" => %{type: :map}
  }

  @tool_config_schema %{
    "required_tools" => %{type: {:array, :string}},
    "optional_tools" => %{type: {:array, :string}},
    "mcp_servers" => %{
      type: {:array, :map},
      schema: %{
        "name" => %{type: :string, required: true},
        "config" => %{type: :map},
        "enabled" => %{type: :boolean, default: true}
      }
    },
    "tool_permissions" => %{type: :map}
  }

  @prompt_config_schema %{
    "system_instruction_template" => %{type: :string},
    "context_enhancement" => %{type: :boolean, default: true},
    "provider_optimization" => %{type: :boolean, default: true},
    "multi_modal_support" => %{type: :boolean, default: false},
    "prompt_templates" => %{type: :map},
    "context_window_management" => %{
      type: :map,
      schema: %{
        "strategy" => %{type: :string, enum: ["truncate", "summarize", "sliding_window"]},
        "max_context_length" => %{type: :integer, min: 1024, max: 128000}
      }
    }
  }

  @deployment_config_schema %{
    "auto_start" => %{type: :boolean, default: false},
    "session_timeout" => %{type: :integer, min: 300, max: 86400},
    "conversation_persistence" => %{type: :boolean, default: true},
    "analytics_enabled" => %{type: :boolean, default: true},
    "monitoring_level" => %{type: :string, enum: ["none", "basic", "detailed"], default: "basic"},
    "resource_limits" => %{
      type: :map,
      schema: %{
        "max_memory_mb" => %{type: :integer, min: 64, max: 2048},
        "max_cpu_percent" => %{type: :integer, min: 5, max: 100},
        "max_concurrent_requests" => %{type: :integer, min: 1, max: 100}
      }
    }
  }

  def validate_template(template_data) when is_map(template_data) do
    case validate_against_schema(template_data, @template_schema) do
      {:ok, validated_data} ->
        case validate_cross_field_constraints(validated_data) do
          :ok -> {:ok, validated_data}
          {:error, errors} -> {:error, errors}
        end
      
      {:error, errors} ->
        {:error, errors}
    end
  end

  def validate_template_config(config_type, config_data) when is_atom(config_type) and is_map(config_data) do
    schema = case config_type do
      :provider_config -> @provider_config_schema
      :persona_config -> @persona_config_schema
      :tool_config -> @tool_config_schema
      :prompt_config -> @prompt_config_schema
      :deployment_config -> @deployment_config_schema
      _ -> {:error, "Unknown config type: #{config_type}"}
    end

    case schema do
      {:error, _} = error -> error
      schema_map -> validate_against_schema(config_data, schema_map)
    end
  end

  def get_schema_version, do: @current_schema_version

  def is_compatible_schema_version(version) do
    case Version.compare(version, @current_schema_version) do
      :lt -> {:compatible, :older}
      :eq -> {:compatible, :current}
      :gt -> {:incompatible, :newer}
    end
  end

  # Private validation functions

  defp validate_against_schema(data, schema) when is_map(data) and is_map(schema) do
    errors = []
    validated_data = %{}

    {errors, validated_data} = Enum.reduce(schema, {errors, validated_data}, fn {field, field_schema}, {acc_errors, acc_data} ->
      case validate_field(field, Map.get(data, field), field_schema) do
        {:ok, validated_value} ->
          {acc_errors, Map.put(acc_data, field, validated_value)}
        
        {:error, field_errors} ->
          {acc_errors ++ field_errors, acc_data}
        
        :skip ->
          {acc_errors, acc_data}
      end
    end)

    if errors == [] do
      {:ok, validated_data}
    else
      {:error, errors}
    end
  end

  defp validate_field(field_name, nil, %{required: true}) do
    {:error, [{field_name, "is required"}]}
  end

  defp validate_field(_field_name, nil, %{default: default_value}) do
    {:ok, default_value}
  end

  defp validate_field(_field_name, nil, _schema) do
    :skip
  end

  defp validate_field(field_name, value, %{type: expected_type} = schema) do
    case validate_type(value, expected_type) do
      :ok ->
        case validate_field_constraints(field_name, value, schema) do
          :ok -> {:ok, value}
          {:error, _} = error -> error
        end
      
      {:error, type_error} ->
        {:error, [{field_name, type_error}]}
    end
  end

  defp validate_type(value, :string) when is_binary(value), do: :ok
  defp validate_type(value, :integer) when is_integer(value), do: :ok
  defp validate_type(value, :float) when is_float(value) or is_integer(value), do: :ok
  defp validate_type(value, :boolean) when is_boolean(value), do: :ok
  defp validate_type(value, :map) when is_map(value), do: :ok
  defp validate_type(value, {:array, item_type}) when is_list(value) do
    case Enum.all?(value, &(validate_type(&1, item_type) == :ok)) do
      true -> :ok
      false -> {:error, "contains invalid items"}
    end
  end
  defp validate_type(_value, expected_type) do
    {:error, "must be of type #{inspect(expected_type)}"}
  end

  defp validate_field_constraints(field_name, value, schema) do
    constraints = Map.drop(schema, [:type, :required, :default])
    
    Enum.reduce_while(constraints, :ok, fn {constraint, constraint_value}, _acc ->
      case validate_constraint(field_name, value, constraint, constraint_value) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_constraint(_field_name, value, :min_length, min_length) when is_binary(value) do
    if String.length(value) >= min_length do
      :ok
    else
      {:error, "must be at least #{min_length} characters long"}
    end
  end

  defp validate_constraint(_field_name, value, :max_length, max_length) when is_binary(value) do
    if String.length(value) <= max_length do
      :ok
    else
      {:error, "must be at most #{max_length} characters long"}
    end
  end

  defp validate_constraint(_field_name, value, :min, min_value) when is_number(value) do
    if value >= min_value do
      :ok
    else
      {:error, "must be at least #{min_value}"}
    end
  end

  defp validate_constraint(_field_name, value, :max, max_value) when is_number(value) do
    if value <= max_value do
      :ok
    else
      {:error, "must be at most #{max_value}"}
    end
  end

  defp validate_constraint(_field_name, value, :enum, allowed_values) do
    if value in allowed_values do
      :ok
    else
      {:error, "must be one of: #{Enum.join(allowed_values, ", ")}"}
    end
  end

  defp validate_constraint(_field_name, value, :pattern, pattern) when is_binary(value) do
    if Regex.match?(pattern, value) do
      :ok
    else
      {:error, "format is invalid"}
    end
  end

  defp validate_constraint(field_name, value, :schema, nested_schema) when is_map(value) do
    case validate_against_schema(value, nested_schema) do
      {:ok, _} -> :ok
      {:error, errors} ->
        nested_errors = Enum.map(errors, fn {nested_field, message} ->
          {"#{field_name}.#{nested_field}", message}
        end)
        {:error, nested_errors}
    end
  end

  defp validate_constraint(_field_name, _value, _constraint, _value) do
    :ok
  end

  defp validate_cross_field_constraints(validated_data) do
    errors = []

    # Validate provider-model compatibility
    errors = validate_provider_model_compatibility(validated_data, errors)
    
    # Validate persona accessibility
    errors = validate_persona_accessibility(validated_data, errors)
    
    # Validate tool compatibility
    errors = validate_tool_compatibility(validated_data, errors)

    if errors == [] do
      :ok
    else
      {:error, errors}
    end
  end

  defp validate_provider_model_compatibility(data, errors) do
    provider_config = Map.get(data, "provider_config", %{})
    
    case Map.get(provider_config, "model_preferences") do
      nil -> errors
      model_prefs when is_map(model_prefs) ->
        # Validate that each provider has compatible models
        Enum.reduce(model_prefs, errors, fn {provider, model}, acc ->
          case validate_provider_model_pair(provider, model) do
            :ok -> acc
            {:error, message} -> [{"provider_config.model_preferences", message} | acc]
          end
        end)
    end
  end

  defp validate_persona_accessibility(data, errors) do
    persona_config = Map.get(data, "persona_config", %{})
    
    case Map.get(persona_config, "primary_persona_id") do
      nil -> errors
      persona_id ->
        case check_persona_exists_and_accessible(persona_id) do
          :ok -> errors
          {:error, message} -> [{"persona_config.primary_persona_id", message} | errors]
        end
    end
  end

  defp validate_tool_compatibility(data, errors) do
    tool_config = Map.get(data, "tool_config", %{})
    required_tools = Map.get(tool_config, "required_tools", [])
    
    Enum.reduce(required_tools, errors, fn tool_name, acc ->
      case check_tool_available(tool_name) do
        :ok -> acc
        {:error, message} -> [{"tool_config.required_tools", "#{tool_name}: #{message}"} | acc]
      end
    end)
  end

  # Placeholder functions for external validation
  defp validate_provider_model_pair(_provider, _model), do: :ok
  defp check_persona_exists_and_accessible(_persona_id), do: :ok
  defp check_tool_available(_tool_name), do: :ok
end
```

### Template Configuration Merger

```elixir
# lib/the_maestro/agent_templates/config_merger.ex
defmodule TheMaestro.AgentTemplates.ConfigMerger do
  @moduledoc """
  Handles template inheritance and configuration merging.
  """

  def merge_template_configs(child_template, parent_template) do
    merged_config = %{}

    # Merge each configuration section
    merged_config = Map.put(merged_config, :provider_config, 
      merge_provider_config(child_template.provider_config, parent_template.provider_config))
    
    merged_config = Map.put(merged_config, :persona_config,
      merge_persona_config(child_template.persona_config, parent_template.persona_config))
    
    merged_config = Map.put(merged_config, :tool_config,
      merge_tool_config(child_template.tool_config, parent_template.tool_config))
    
    merged_config = Map.put(merged_config, :prompt_config,
      merge_prompt_config(child_template.prompt_config, parent_template.prompt_config))
    
    merged_config = Map.put(merged_config, :deployment_config,
      merge_deployment_config(child_template.deployment_config, parent_template.deployment_config))

    merged_config
  end

  defp merge_provider_config(child_config, parent_config) do
    # Child config takes precedence, but merge fallback providers
    merged = Map.merge(parent_config, child_config)
    
    # Special handling for fallback providers - merge arrays
    parent_fallbacks = Map.get(parent_config, "fallback_providers", [])
    child_fallbacks = Map.get(child_config, "fallback_providers", [])
    merged_fallbacks = (parent_fallbacks ++ child_fallbacks) |> Enum.uniq()
    
    Map.put(merged, "fallback_providers", merged_fallbacks)
  end

  defp merge_persona_config(child_config, parent_config) do
    # Build persona hierarchy by combining parent and child hierarchies
    parent_hierarchy = Map.get(parent_config, "persona_hierarchy", [])
    child_hierarchy = Map.get(child_config, "persona_hierarchy", [])
    
    # Primary persona from child, hierarchy combines both
    merged = Map.merge(parent_config, child_config)
    combined_hierarchy = (parent_hierarchy ++ child_hierarchy) |> Enum.uniq()
    
    Map.put(merged, "persona_hierarchy", combined_hierarchy)
  end

  defp merge_tool_config(child_config, parent_config) do
    merged = Map.merge(parent_config, child_config)
    
    # Merge tool arrays
    parent_required = Map.get(parent_config, "required_tools", [])
    child_required = Map.get(child_config, "required_tools", [])
    merged_required = (parent_required ++ child_required) |> Enum.uniq()
    
    parent_optional = Map.get(parent_config, "optional_tools", [])
    child_optional = Map.get(child_config, "optional_tools", [])
    merged_optional = (parent_optional ++ child_optional) |> Enum.uniq()
    
    merged
    |> Map.put("required_tools", merged_required)
    |> Map.put("optional_tools", merged_optional)
  end

  defp merge_prompt_config(child_config, parent_config) do
    # Merge prompt templates
    parent_templates = Map.get(parent_config, "prompt_templates", %{})
    child_templates = Map.get(child_config, "prompt_templates", %{})
    merged_templates = Map.merge(parent_templates, child_templates)
    
    Map.merge(parent_config, child_config)
    |> Map.put("prompt_templates", merged_templates)
  end

  defp merge_deployment_config(child_config, parent_config) do
    # Simple merge with child taking precedence
    Map.merge(parent_config, child_config)
  end
end
```

## Module Structure

```
lib/the_maestro/agent_templates/
├── template.ex                    # Core template schema
├── schema_validator.ex           # Template validation system
├── config_merger.ex             # Template inheritance and merging
├── template_builder.ex          # Template construction utilities
├── compatibility_checker.ex     # Version compatibility system
├── dependency_resolver.ex       # Template dependency resolution
├── template_migrator.ex         # Schema migration utilities
└── template_tester.ex           # Template testing framework
```

## Integration Points

1. **Epic 5 Integration**: Provider configuration validation and compatibility checking
2. **Epic 6 Integration**: MCP server and tool configuration validation
3. **Epic 7 Integration**: Prompt configuration and template validation
4. **Epic 8 Integration**: Persona configuration and dependency resolution
5. **Database Layer**: Ecto schema integration with comprehensive validation

## Performance Considerations

- Template validation caching to avoid redundant validation operations
- Lazy loading of template dependencies during validation
- Efficient inheritance resolution with cycle detection
- Background validation for large template libraries
- Database query optimization for template discovery and filtering

## Security Considerations

- Template content sanitization to prevent injection attacks
- Access control validation for template dependencies
- Secure template sharing with permission validation
- Configuration validation to prevent privilege escalation
- Audit logging for template creation and modification

## Dependencies

- Epic 5: Model Choice & Authentication System for provider configurations
- Epic 6: MCP Protocol Implementation for tool configurations
- Epic 7: Enhanced Prompt Handling System for prompt configurations
- Epic 8: Persona Management System for persona configurations
- Ecto for database operations and validation
- Jason for JSON schema handling

## Definition of Done

- [ ] Comprehensive template schema designed and implemented
- [ ] Template validation system with detailed error reporting
- [ ] Multi-level template inheritance system operational
- [ ] Configuration composition and conflict resolution working
- [ ] Template versioning with semantic version support
- [ ] Provider integration with Epic 5 systems complete
- [ ] Persona integration with Epic 8 systems functional
- [ ] Tool configuration integration with Epic 6 complete
- [ ] Prompt configuration integration with Epic 7 operational
- [ ] Template metadata management system implemented
- [ ] Real-time configuration validation functional
- [ ] Template categories and tagging system operational
- [ ] Template dependency management working correctly
- [ ] Environment-specific configuration support implemented
- [ ] Template security model enforced
- [ ] Configuration templating with variable substitution
- [ ] Template testing framework operational
- [ ] Performance optimizations implemented and benchmarked
- [ ] Error handling and recovery mechanisms functional
- [ ] Template documentation system integrated
- [ ] Backwards compatibility layer implemented
- [ ] Analytics integration hooks functional
- [ ] Configuration migration tools operational
- [ ] Template preview system implemented
- [ ] Comprehensive unit tests passing (>95% coverage)
- [ ] Integration tests with all dependent systems passing
- [ ] Performance benchmarks meeting requirements (<100ms validation)
- [ ] Security audit completed with no high-severity issues
- [ ] Documentation complete for template definition and usage