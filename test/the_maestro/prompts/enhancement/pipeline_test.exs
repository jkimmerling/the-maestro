defmodule TheMaestro.Prompts.Enhancement.PipelineTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Enhancement.Pipeline
  alias TheMaestro.Prompts.Enhancement.Structs.EnhancementContext

  describe "enhance_prompt/2" do
    setup do
      original_prompt = "Fix the authentication bug in the user service"
      
      user_context = %{
        user_id: "test-user",
        session_id: "test-session",
        working_directory: "/Users/test/project",
        environment: %{
          operating_system: "Darwin",
          current_date: "2025-01-19",
          timezone: "America/New_York"
        },
        project_context: %{
          project_type: "elixir_phoenix",
          languages: ["elixir"],
          frameworks: ["phoenix"],
          has_git: true
        },
        available_tools: [:read_file, :write_file, :execute_command],
        mcp_servers: [:sequential]
      }

      %{original_prompt: original_prompt, user_context: user_context}
    end

    test "returns enhanced prompt structure", %{original_prompt: prompt, user_context: context} do
      result = Pipeline.enhance_prompt(prompt, context)

      assert %{
        original: ^prompt,
        pre_context: pre_context,
        enhanced_prompt: enhanced_prompt,
        post_context: post_context,
        metadata: metadata,
        total_tokens: token_count,
        relevance_scores: scores
      } = result

      assert is_binary(pre_context)
      assert is_binary(enhanced_prompt)
      assert is_binary(post_context)
      assert is_map(metadata)
      assert is_integer(token_count) and token_count > 0
      assert is_list(scores)
    end

    test "includes environmental information in pre-context", %{original_prompt: prompt, user_context: context} do
      result = Pipeline.enhance_prompt(prompt, context)
      
      assert String.contains?(result.pre_context, "Darwin")
      assert String.contains?(result.pre_context, "2025-01-19")
      assert String.contains?(result.pre_context, "/Users/test/project")
    end

    test "includes project information in context", %{original_prompt: prompt, user_context: context} do
      result = Pipeline.enhance_prompt(prompt, context)
      
      assert String.contains?(result.pre_context, "elixir_phoenix") or
             String.contains?(result.pre_context, "Phoenix") or
             String.contains?(result.pre_context, "Elixir")
    end

    test "enhances prompt based on context", %{original_prompt: prompt, user_context: context} do
      result = Pipeline.enhance_prompt(prompt, context)
      
      # The enhanced prompt should contain the original but be expanded
      assert String.contains?(result.enhanced_prompt, prompt)
      assert String.length(result.enhanced_prompt) > String.length(prompt)
    end

    test "provides metadata about enhancement process", %{original_prompt: prompt, user_context: context} do
      result = Pipeline.enhance_prompt(prompt, context)
      
      assert %{
        processing_time: time,
        context_items_used: items_count,
        average_relevance_score: avg_score,
        quality_score: quality
      } = result.metadata

      assert is_integer(time) and time > 0
      assert is_integer(items_count) and items_count > 0
      assert is_float(avg_score) and avg_score > 0.0 and avg_score <= 1.0
      assert is_float(quality) and quality > 0.0 and quality <= 1.0
    end

    test "handles minimal context gracefully" do
      minimal_context = %{user_id: "test"}
      prompt = "Hello world"
      
      result = Pipeline.enhance_prompt(prompt, minimal_context)
      
      assert result.original == prompt
      assert is_binary(result.enhanced_prompt)
      assert String.contains?(result.enhanced_prompt, prompt)
    end
  end

  describe "run_enhancement_pipeline/2" do
    test "executes all pipeline stages in order" do
      context = %EnhancementContext{
        original_prompt: "Test prompt",
        user_context: %{},
        enhancement_config: %{},
        pipeline_state: %{}
      }

      stages = [
        :context_analysis,
        :intent_detection,
        :context_gathering,
        :relevance_scoring,
        :context_integration,
        :optimization,
        :validation,
        :formatting
      ]

      result = Pipeline.run_enhancement_pipeline(context, stages)

      # Verify all stages were executed by checking pipeline_state
      assert Map.has_key?(result.pipeline_state, :context_analysis)
      assert Map.has_key?(result.pipeline_state, :intent_detection)
      assert Map.has_key?(result.pipeline_state, :context_gathering)
      assert Map.has_key?(result.pipeline_state, :relevance_scoring)
      assert Map.has_key?(result.pipeline_state, :context_integration)
      assert Map.has_key?(result.pipeline_state, :optimization)
      assert Map.has_key?(result.pipeline_state, :validation)
      assert Map.has_key?(result.pipeline_state, :formatting)
    end
  end
end