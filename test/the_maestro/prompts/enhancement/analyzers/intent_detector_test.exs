defmodule TheMaestro.Prompts.Enhancement.Analyzers.IntentDetectorTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Enhancement.Analyzers.IntentDetector

  describe "detect_intent/1" do
    test "detects software engineering intent" do
      prompts = [
        "Fix the authentication bug in the user module",
        "Refactor the payment processing code",
        "Add unit tests for the API endpoints",
        "Optimize the database queries for better performance",
        "Implement a new feature for user registration"
      ]

      for prompt <- prompts do
        result = IntentDetector.detect_intent(prompt)
        assert result.category == :software_engineering
        assert result.confidence > 0.5
        assert :project_structure in result.context_requirements
        assert :existing_code in result.context_requirements
      end
    end

    test "detects file operations intent" do
      prompts = [
        "Read the configuration file",
        "Create a new JSON file with user data",
        "List all files in the project directory",
        "Delete the temporary log files",
        "Find all Python files in the src folder"
      ]

      for prompt <- prompts do
        result = IntentDetector.detect_intent(prompt)
        assert result.category == :file_operations
        assert result.confidence > 0.5
        assert :current_directory in result.context_requirements
        assert :file_permissions in result.context_requirements
      end
    end

    test "detects system operations intent" do
      prompts = [
        "Install the npm dependencies",
        "Start the development server",
        "Run the test suite",
        "Execute the deployment script",
        "Stop the running processes"
      ]

      for prompt <- prompts do
        result = IntentDetector.detect_intent(prompt)
        assert result.category == :system_operations
        assert result.confidence > 0.5
        assert :operating_system in result.context_requirements
        assert :available_commands in result.context_requirements
      end
    end

    test "detects information seeking intent" do
      prompts = [
        "What is the difference between HTTP and HTTPS?",
        "How do I implement OAuth2 in Elixir?",
        "Explain the Model-View-Controller pattern",
        "Tell me about functional programming concepts",
        "Help me understand Phoenix LiveView"
      ]

      for prompt <- prompts do
        result = IntentDetector.detect_intent(prompt)
        assert result.category == :information_seeking
        assert result.confidence > 0.3
        assert :knowledge_base in result.context_requirements
        assert :documentation in result.context_requirements
      end
    end

    test "returns highest confidence intent for ambiguous prompts" do
      # This prompt could be both file operations and software engineering
      ambiguous_prompt = "Create a new module file for user authentication"

      result = IntentDetector.detect_intent(ambiguous_prompt)

      assert result.category in [:software_engineering, :file_operations]
      assert result.confidence > 0.3
      assert is_list(result.context_requirements)
      assert length(result.context_requirements) > 0
    end

    test "handles prompts with multiple intents" do
      multi_intent_prompt = "Read the config file, fix the authentication bug, and run the tests"

      result = IntentDetector.detect_intent(multi_intent_prompt)

      # Should detect the strongest intent
      assert result.category in [:software_engineering, :file_operations, :system_operations]
      assert result.confidence > 0.3
    end

    test "provides reasonable confidence scores" do
      # High confidence case
      high_confidence_prompt = "Fix the bug in the authentication function"
      result = IntentDetector.detect_intent(high_confidence_prompt)
      assert result.confidence > 0.7

      # Medium confidence case
      medium_confidence_prompt = "Update the user information"
      result = IntentDetector.detect_intent(medium_confidence_prompt)
      assert result.confidence > 0.3 and result.confidence < 0.8

      # Lower confidence case
      low_confidence_prompt = "Hello there"
      result = IntentDetector.detect_intent(low_confidence_prompt)
      assert result.confidence < 0.5
    end
  end

  describe "score_intent_category/2" do
    test "scores software engineering patterns correctly" do
      prompt = "Fix the authentication bug in the user service"

      category =
        {:software_engineering,
         %{
           patterns: [
             ~r/(?:fix|debug|refactor|optimize|improve)\s+(?:code|function|class|module)/i,
             ~r/(?:authentication|auth)/i
           ],
           confidence_boost: 0.3,
           context_requirements: [:project_structure, :existing_code]
         }}

      result = IntentDetector.score_intent_category(category, prompt)

      assert result.category == :software_engineering
      assert result.confidence > 0.3
      assert result.context_requirements == [:project_structure, :existing_code]
    end

    test "handles patterns that don't match" do
      prompt = "What's the weather like?"

      category =
        {:software_engineering,
         %{
           patterns: [~r/(?:fix|debug|refactor)/i],
           confidence_boost: 0.3,
           context_requirements: [:project_structure]
         }}

      result = IntentDetector.score_intent_category(category, prompt)

      assert result.category == :software_engineering
      # Should be low since no patterns match
      assert result.confidence < 0.2
    end
  end

  describe "intent categories configuration" do
    test "has all expected categories defined" do
      expected_categories = [
        :software_engineering,
        :file_operations,
        :system_operations,
        :information_seeking
      ]

      # Test that we can detect all expected categories
      test_prompts = %{
        software_engineering: "Fix the authentication bug",
        file_operations: "Read the config file",
        system_operations: "Install the dependencies",
        information_seeking: "What is Phoenix LiveView?"
      }

      detected_categories =
        test_prompts
        |> Enum.map(fn {_expected, prompt} ->
          IntentDetector.detect_intent(prompt).category
        end)
        |> Enum.uniq()

      for category <- expected_categories do
        assert category in detected_categories
      end
    end

    test "each category has required configuration" do
      test_prompt = "test prompt"

      [:software_engineering, :file_operations, :system_operations, :information_seeking]
      |> Enum.each(fn category ->
        # Test by trying to create a category config
        category_config =
          {category,
           %{
             patterns: [~r/test/i],
             confidence_boost: 0.1,
             context_requirements: [:test_requirement]
           }}

        result = IntentDetector.score_intent_category(category_config, test_prompt)

        assert result.category == category
        assert is_float(result.confidence)
        assert is_list(result.context_requirements)
      end)
    end
  end
end
