defmodule TheMaestro.Prompts.EngineeringTools.InteractiveBuilderTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.EngineeringTools.InteractiveBuilder

  alias TheMaestro.Prompts.EngineeringTools.InteractiveBuilder.{
    PromptBuilderSession,
    PromptModification
  }

  describe "create_prompt_builder_session/1" do
    test "creates a new builder session with default empty prompt" do
      session = InteractiveBuilder.create_prompt_builder_session()

      assert %PromptBuilderSession{} = session
      assert session.current_prompt == ""
      assert is_map(session.prompt_structure)
      assert is_list(session.available_components)
      assert is_map(session.real_time_preview)
      assert is_map(session.validation_engine)
      assert is_map(session.suggestion_engine)
      assert is_map(session.collaboration_state)
    end

    test "creates a new builder session with initial prompt" do
      initial_prompt = "You are a helpful assistant."
      session = InteractiveBuilder.create_prompt_builder_session(initial_prompt)

      assert session.current_prompt == initial_prompt
      assert session.prompt_structure.content_length == String.length(initial_prompt)
      assert session.prompt_structure.sections_count > 0
    end

    test "initializes all required session components" do
      session = InteractiveBuilder.create_prompt_builder_session()

      # Check that all essential components are initialized
      assert Map.has_key?(session.validation_engine, :rules)
      assert Map.has_key?(session.suggestion_engine, :enabled)
      assert Map.has_key?(session.real_time_preview, :provider)
      assert Map.has_key?(session.collaboration_state, :participants)
    end
  end

  describe "apply_prompt_modification/2" do
    setup do
      session = InteractiveBuilder.create_prompt_builder_session("Initial prompt")
      {:ok, session: session}
    end

    test "applies text replacement modification", %{session: session} do
      modification = %PromptModification{
        type: :text_replacement,
        target: "Initial",
        replacement: "Modified",
        position: 0
      }

      updated_session = InteractiveBuilder.apply_prompt_modification(session, modification)

      assert updated_session.current_prompt == "Modified prompt"
      assert updated_session.prompt_structure.content_length == String.length("Modified prompt")
    end

    test "applies text insertion modification", %{session: session} do
      modification = %PromptModification{
        type: :text_insertion,
        target: "prompt",
        insertion: " text",
        position: 13
      }

      updated_session = InteractiveBuilder.apply_prompt_modification(session, modification)

      assert updated_session.current_prompt == "Initial prompt text"
    end

    test "applies section addition modification", %{session: session} do
      modification = %PromptModification{
        type: :section_addition,
        section_type: :constraint,
        content: "You must be concise.",
        position: :end
      }

      updated_session = InteractiveBuilder.apply_prompt_modification(session, modification)

      assert String.contains?(updated_session.current_prompt, "You must be concise.")

      assert updated_session.prompt_structure.sections_count >
               session.prompt_structure.sections_count
    end

    test "updates validation results after modification", %{session: session} do
      modification = %PromptModification{
        type: :text_insertion,
        insertion: "Invalid {{unclosed_template",
        position: 0
      }

      updated_session = InteractiveBuilder.apply_prompt_modification(session, modification)

      assert updated_session.validation_results.has_errors == true
      assert length(updated_session.validation_results.errors) > 0
    end

    test "generates performance prediction after modification", %{session: session} do
      modification = %PromptModification{
        type: :text_insertion,
        insertion: "Be very detailed and comprehensive in your response. ",
        position: 0
      }

      updated_session = InteractiveBuilder.apply_prompt_modification(session, modification)

      assert updated_session.performance_prediction.estimated_tokens >
               session.performance_prediction.estimated_tokens

      assert updated_session.performance_prediction.complexity_score >= 0
    end

    test "generates improvement suggestions after modification", %{session: session} do
      modification = %PromptModification{
        type: :text_replacement,
        target: "Initial prompt",
        replacement: "prompt prompt prompt prompt prompt",
        position: 0
      }

      updated_session = InteractiveBuilder.apply_prompt_modification(session, modification)

      suggestions = updated_session.improvement_suggestions
      assert is_list(suggestions)
      assert Enum.any?(suggestions, fn s -> s.type == :reduce_repetition end)
    end

    test "triggers auto-save after modification", %{session: session} do
      modification = %PromptModification{
        type: :text_insertion,
        insertion: " modified",
        position: 13
      }

      updated_session = InteractiveBuilder.apply_prompt_modification(session, modification)

      assert updated_session.auto_save_triggered == true
      assert updated_session.last_save_timestamp != nil
    end

    test "updates collaboration state when other users present", %{session: session} do
      # Setup collaboration state with other participants
      collaborative_session = %{
        session
        | collaboration_state: %{
            participants: ["user1", "user2"],
            active_editors: ["user1"],
            requires_sync: false
          }
      }

      modification = %PromptModification{
        type: :text_insertion,
        insertion: " collaborative edit",
        position: 13
      }

      updated_session =
        InteractiveBuilder.apply_prompt_modification(collaborative_session, modification)

      assert updated_session.collaboration_state.requires_sync == true
      assert updated_session.collaboration_state.last_edit_by == "current_user"
    end
  end

  describe "real-time validation" do
    test "validates template syntax" do
      session = InteractiveBuilder.create_prompt_builder_session()

      modification = %PromptModification{
        type: :text_insertion,
        insertion: "Hello {{name}}, please {{action | required}}",
        position: 0
      }

      updated_session = InteractiveBuilder.apply_prompt_modification(session, modification)

      assert updated_session.validation_results.template_syntax_valid == true
      assert length(updated_session.validation_results.template_parameters) == 2
    end

    test "detects invalid template syntax" do
      session = InteractiveBuilder.create_prompt_builder_session()

      modification = %PromptModification{
        type: :text_insertion,
        insertion: "Hello {{unclosed_template and {{nested {{invalid}}",
        position: 0
      }

      updated_session = InteractiveBuilder.apply_prompt_modification(session, modification)

      assert updated_session.validation_results.has_errors == true

      assert Enum.any?(updated_session.validation_results.errors, fn e ->
               e.type == :template_syntax_error
             end)
    end

    test "validates prompt length constraints" do
      session = InteractiveBuilder.create_prompt_builder_session()

      # Create a very long prompt
      long_text = String.duplicate("This is a very long prompt. ", 1000)

      modification = %PromptModification{
        type: :text_insertion,
        insertion: long_text,
        position: 0
      }

      updated_session = InteractiveBuilder.apply_prompt_modification(session, modification)

      assert updated_session.validation_results.length_warnings != []

      assert Enum.any?(updated_session.validation_results.length_warnings, fn w ->
               w.type == :excessive_length
             end)
    end
  end

  describe "suggestion engine" do
    test "suggests structure improvements for unstructured prompt" do
      unstructured_prompt = "Do something with the data and make it good and useful"
      session = InteractiveBuilder.create_prompt_builder_session(unstructured_prompt)

      suggestions = session.improvement_suggestions

      assert Enum.any?(suggestions, fn s -> s.type == :add_structure end)
      assert Enum.any?(suggestions, fn s -> s.type == :clarify_instructions end)
    end

    test "suggests parameter extraction for repeated patterns" do
      parametrizable_prompt =
        "You are a Python developer. Write Python code using Python best practices."

      session = InteractiveBuilder.create_prompt_builder_session(parametrizable_prompt)

      suggestions = session.improvement_suggestions

      assert Enum.any?(suggestions, fn s -> s.type == :extract_parameter end)
      assert Enum.any?(suggestions, fn s -> String.contains?(s.description, "Python") end)
    end

    test "suggests performance optimizations" do
      verbose_prompt = """
      You are an extremely helpful, very detailed, comprehensively thorough, 
      meticulously careful, exceptionally precise assistant that always provides 
      complete, exhaustive, fully comprehensive responses with extensive detail.
      """

      session = InteractiveBuilder.create_prompt_builder_session(verbose_prompt)

      suggestions = session.improvement_suggestions

      assert Enum.any?(suggestions, fn s -> s.type == :reduce_verbosity end)
      assert Enum.any?(suggestions, fn s -> s.type == :optimize_length end)
    end
  end

  describe "component integration" do
    test "loads available prompt components" do
      session = InteractiveBuilder.create_prompt_builder_session()

      components = session.available_components

      assert is_list(components)
      assert length(components) > 0

      assert Enum.all?(components, fn c ->
               Map.has_key?(c, :name) && Map.has_key?(c, :template) && Map.has_key?(c, :category)
             end)
    end

    test "components include standard categories" do
      session = InteractiveBuilder.create_prompt_builder_session()

      component_categories = Enum.map(session.available_components, & &1.category)

      assert Enum.member?(component_categories, :role_definition)
      assert Enum.member?(component_categories, :task_specification)
      assert Enum.member?(component_categories, :output_format)
      assert Enum.member?(component_categories, :constraints)
    end

    test "can insert component into prompt" do
      session = InteractiveBuilder.create_prompt_builder_session()

      role_component =
        Enum.find(session.available_components, fn c ->
          c.category == :role_definition
        end)

      modification = %PromptModification{
        type: :component_insertion,
        component: role_component,
        position: 0
      }

      updated_session = InteractiveBuilder.apply_prompt_modification(session, modification)

      assert String.contains?(updated_session.current_prompt, role_component.template)
    end
  end
end
