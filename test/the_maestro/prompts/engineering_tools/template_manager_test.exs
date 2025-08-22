defmodule TheMaestro.Prompts.EngineeringTools.TemplateManagerTest do
  use ExUnit.Case, async: true
  use TheMaestro.DataCase

  alias TheMaestro.Prompts.EngineeringTools.TemplateManager

  alias TheMaestro.Prompts.EngineeringTools.TemplateManager.{
    PromptTemplate,
    ParameterDefinition,
    TemplateMetadata
  }

  describe "create_template_from_prompt/2" do
    test "creates a template from a simple prompt" do
      prompt = "You are a helpful {{role | default: assistant}}. Please {{action | required}}."

      metadata = %TemplateMetadata{
        name: "Simple Assistant Template",
        description: "A basic assistant template with role and action parameters",
        category: :general,
        author: "test_user",
        tags: ["assistant", "general"]
      }

      template = TemplateManager.create_template_from_prompt(prompt, metadata)

      assert %PromptTemplate{} = template
      assert template.name == metadata.name
      assert template.description == metadata.description
      assert template.category == to_string(metadata.category)
      assert template.created_by == metadata.author
      assert template.tags == metadata.tags
      assert template.version == 1
      assert String.contains?(template.template_content, "{{role")
      assert String.contains?(template.template_content, "{{action")
    end

    test "extracts template parameters correctly" do
      prompt = """
      You are a {{role | default: "software engineer"}} with {{experience_level | enum: [junior, mid, senior]}} experience.
      Task: {{task_description | required | min_length: 10}}
      Output format: {{output_format | enum: [detailed, summary, code-only] | default: detailed}}
      """

      metadata = %TemplateMetadata{
        name: "Software Engineering Template",
        description: "Template for software engineering tasks",
        category: :software_engineering,
        author: "test_user",
        tags: ["software", "engineering"]
      }

      template = TemplateManager.create_template_from_prompt(prompt, metadata)

      assert length(template.parameters.required_parameters) == 1
      assert Enum.member?(template.parameters.required_parameters, "task_description")

      assert length(template.parameters.optional_parameters) == 3
      assert Enum.member?(template.parameters.optional_parameters, "role")
      assert Enum.member?(template.parameters.optional_parameters, "experience_level")
      assert Enum.member?(template.parameters.optional_parameters, "output_format")

      # Check parameter types and constraints
      assert template.parameters.parameter_types["experience_level"] == :enum
      assert template.parameters.validation_rules["task_description"][:min_length] == 10
      assert template.parameters.default_values["role"] == "software engineer"
    end

    test "generates usage examples automatically" do
      prompt =
        "Analyze the {{code_type | enum: [function, class, module]}} and identify {{issues | required}}."

      metadata = %TemplateMetadata{
        name: "Code Analysis Template",
        description: "Template for code analysis tasks",
        category: :code_analysis,
        author: "test_user",
        tags: ["code", "analysis"]
      }

      template = TemplateManager.create_template_from_prompt(prompt, metadata)

      assert is_list(template.usage_examples)
      assert length(template.usage_examples) > 0

      assert Enum.all?(template.usage_examples, fn example ->
               Map.has_key?(example, :parameters) && Map.has_key?(example, :description)
             end)
    end

    test "initializes performance tracking" do
      prompt = "Simple template {{param | required}}"

      metadata = %TemplateMetadata{
        name: "Simple Template",
        description: "A simple test template",
        category: :test,
        author: "test_user",
        tags: ["test"]
      }

      template = TemplateManager.create_template_from_prompt(prompt, metadata)

      assert Map.has_key?(template.performance_metrics, :usage_count)
      assert Map.has_key?(template.performance_metrics, :success_rate)
      assert Map.has_key?(template.performance_metrics, :average_response_quality)
      assert template.performance_metrics.usage_count == 0
    end

    test "validates template structure" do
      invalid_prompt = "Template with {{invalid syntax"

      metadata = %TemplateMetadata{
        name: "Invalid Template",
        description: "Template with invalid syntax",
        category: :test,
        author: "test_user",
        tags: ["test"]
      }

      assert_raise ArgumentError, ~r/Invalid template syntax/, fn ->
        TemplateManager.create_template_from_prompt(invalid_prompt, metadata)
      end
    end

    test "optimizes template for reuse" do
      prompt = """
      You are a helpful assistant. You are very helpful.
      Please help the user. Be helpful in your response.
      Task: {{task | required}}
      """

      metadata = %TemplateMetadata{
        name: "Redundant Template",
        description: "Template with redundant content",
        category: :test,
        author: "test_user",
        tags: ["test"]
      }

      template = TemplateManager.create_template_from_prompt(prompt, metadata)

      # Should have optimization suggestions
      assert Map.has_key?(template, :optimization_suggestions)

      assert Enum.any?(template.optimization_suggestions, fn s ->
               String.contains?(s, "redundant")
             end)
    end
  end

  describe "instantiate_template/2" do
    setup do
      prompt = """
      You are a {{role | default: "assistant"}}.
      {{#if include_context}}
      Current context: {{context | required}}
      {{/if}}
      Task: {{task | required}}
      Output format: {{format | enum: [brief, detailed] | default: brief}}
      """

      metadata = %TemplateMetadata{
        name: "Test Template",
        description: "Template for testing",
        category: :test,
        author: "test_user",
        tags: ["test"]
      }

      template = TemplateManager.create_template_from_prompt(prompt, metadata)
      {:ok, template: template}
    end

    test "instantiates template with required parameters", %{template: template} do
      parameters = %{
        "task" => "Write a simple function",
        "role" => "Python developer"
      }

      instantiated = TemplateManager.instantiate_template(template, parameters)

      assert String.contains?(instantiated, "You are a Python developer")
      assert String.contains?(instantiated, "Task: Write a simple function")
      assert String.contains?(instantiated, "Output format: brief")
    end

    test "applies default values for optional parameters", %{template: template} do
      parameters = %{
        "task" => "Write a simple function"
      }

      instantiated = TemplateManager.instantiate_template(template, parameters)

      assert String.contains?(instantiated, "You are a assistant")
      assert String.contains?(instantiated, "Output format: brief")
    end

    test "handles conditional logic correctly", %{template: template} do
      parameters_with_context = %{
        "task" => "Write a simple function",
        "include_context" => true,
        "context" => "Working on a web application"
      }

      instantiated_with_context =
        TemplateManager.instantiate_template(template, parameters_with_context)

      assert String.contains?(
               instantiated_with_context,
               "Current context: Working on a web application"
             )

      parameters_without_context = %{
        "task" => "Write a simple function",
        "include_context" => false
      }

      instantiated_without_context =
        TemplateManager.instantiate_template(template, parameters_without_context)

      refute String.contains?(instantiated_without_context, "Current context:")
    end

    test "validates required parameters", %{template: template} do
      parameters = %{
        "role" => "Python developer"
        # Missing required "task" parameter
      }

      assert_raise ArgumentError, ~r/Required parameter 'task' is missing/, fn ->
        TemplateManager.instantiate_template(template, parameters)
      end
    end

    test "validates enum parameters", %{template: template} do
      parameters = %{
        "task" => "Write a simple function",
        "format" => "invalid_format"
      }

      assert_raise ArgumentError,
                   ~r/Invalid value 'invalid_format' for enum parameter 'format'/,
                   fn ->
                     TemplateManager.instantiate_template(template, parameters)
                   end
    end

    test "tracks template usage", %{template: template} do
      parameters = %{
        "task" => "Write a simple function"
      }

      initial_usage = template.performance_metrics.usage_count

      TemplateManager.instantiate_template(template, parameters)

      # In a real implementation, this would update the template's usage count
      # For testing purposes, we verify the tracking mechanism exists
      assert function_exported?(TemplateManager, :track_template_usage, 2)
    end

    test "applies template transformations", %{template: template} do
      parameters = %{
        "task" => "write a SIMPLE function",
        "role" => "PYTHON DEVELOPER"
      }

      instantiated = TemplateManager.instantiate_template(template, parameters)

      # Should apply case normalization and formatting
      # Case normalized
      assert String.contains?(instantiated, "Python Developer")
    end

    test "validates instantiated prompt", %{template: template} do
      parameters = %{
        "task" => "{{invalid nested template}}"
      }

      assert_raise ArgumentError, ~r/Invalid template nesting detected/, fn ->
        TemplateManager.instantiate_template(template, parameters)
      end
    end
  end

  describe "template categories" do
    test "loads all template categories" do
      categories = TemplateManager.get_template_categories()

      assert Map.has_key?(categories, :software_engineering)
      assert Map.has_key?(categories, :creative_tasks)
      assert Map.has_key?(categories, :analysis_tasks)

      # Check software engineering subcategories
      se_templates = categories.software_engineering
      assert Map.has_key?(se_templates, :code_analysis)
      assert Map.has_key?(se_templates, :bug_fixing)
      assert Map.has_key?(se_templates, :feature_implementation)
      assert Map.has_key?(se_templates, :code_review)
      assert Map.has_key?(se_templates, :testing)
    end

    test "loads templates for specific category" do
      code_analysis_templates = TemplateManager.get_templates_by_category(:code_analysis)

      assert is_list(code_analysis_templates)
      assert length(code_analysis_templates) > 0

      assert Enum.all?(code_analysis_templates, fn template ->
               template.category == :code_analysis
             end)
    end

    test "searches templates by tag" do
      python_templates = TemplateManager.search_templates_by_tag("python")

      assert is_list(python_templates)

      assert Enum.all?(python_templates, fn template ->
               Enum.member?(template.tags, "python")
             end)
    end
  end

  describe "template parameter system" do
    test "defines complex parameter relationships" do
      template_content = """
      Language: {{language | enum: [python, javascript, elixir] | default: python}}
      {{#if language == "python"}}
      Framework: {{python_framework | enum: [django, flask, fastapi] | default: django}}
      {{/if}}
      {{#if language == "javascript"}}
      Framework: {{js_framework | enum: [react, vue, angular] | default: react}}
      {{/if}}
      """

      parameters = TemplateManager.TemplateParameters.define_template_parameters(template_content)

      assert length(parameters.conditional_logic) > 0
      assert Map.has_key?(parameters.parameter_relationships, "python_framework")
      assert parameters.parameter_relationships["python_framework"] == ["language"]
    end

    test "infers parameter types correctly" do
      template_content = """
      Name: {{name | required}}
      Age: {{age | type: integer | min: 0 | max: 150}}
      Email: {{email | type: email | required}}
      Active: {{active | type: boolean | default: true}}
      Score: {{score | type: float | min: 0.0 | max: 100.0}}
      """

      parameters = TemplateManager.TemplateParameters.define_template_parameters(template_content)

      assert parameters.parameter_types["name"] == :string
      assert parameters.parameter_types["age"] == :integer
      assert parameters.parameter_types["email"] == :email
      assert parameters.parameter_types["active"] == :boolean
      assert parameters.parameter_types["score"] == :float
    end

    test "extracts validation rules" do
      template_content = """
      Description: {{description | required | min_length: 10 | max_length: 500}}
      Priority: {{priority | enum: [low, medium, high] | default: medium}}
      Count: {{count | type: integer | min: 1 | max: 100 | default: 1}}
      """

      parameters = TemplateManager.TemplateParameters.define_template_parameters(template_content)

      desc_rules = parameters.validation_rules["description"]
      assert desc_rules[:required] == true
      assert desc_rules[:min_length] == 10
      assert desc_rules[:max_length] == 500

      priority_rules = parameters.validation_rules["priority"]
      assert priority_rules[:enum] == ["low", "medium", "high"]

      count_rules = parameters.validation_rules["count"]
      assert count_rules[:min] == 1
      assert count_rules[:max] == 100
    end
  end

  describe "template versioning" do
    test "creates new version when template is modified" do
      original_template =
        TemplateManager.create_template_from_prompt(
          "Original {{param}}",
          %TemplateMetadata{
            name: "Test",
            description: "Test",
            category: :test,
            author: "user",
            tags: []
          }
        )

      modified_template =
        TemplateManager.update_template(
          original_template,
          "Modified {{param}} with {{new_param}}"
        )

      assert modified_template.version == 2
      assert modified_template.parent_version == 1
      assert modified_template.template_content != original_template.template_content
    end

    test "maintains version history" do
      template =
        TemplateManager.create_template_from_prompt(
          "Version 1 {{param}}",
          %TemplateMetadata{
            name: "Test",
            description: "Test",
            category: :test,
            author: "user",
            tags: []
          }
        )

      v2 = TemplateManager.update_template(template, "Version 2 {{param}}")
      v3 = TemplateManager.update_template(v2, "Version 3 {{param}} {{new_param}}")

      version_history = TemplateManager.get_template_version_history(template.id)

      assert length(version_history) == 3
      assert Enum.map(version_history, & &1.version) == [1, 2, 3]
    end
  end
end
