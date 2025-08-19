defmodule TheMaestro.Prompts.Optimization.Providers.OpenAIOptimizerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Optimization.Providers.OpenAIOptimizer
  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  alias TheMaestro.Prompts.Optimization.Structs.OptimizationContext

  describe "optimize/1" do
    test "applies OpenAI-specific optimizations" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Create a detailed analysis report"
        },
        provider_info: %{provider: :openai, model: "gpt-4o"},
        model_capabilities: %{
          general_reasoning: :excellent,
          language_understanding: :excellent,
          consistency: :excellent
        }
      }

      result = OpenAIOptimizer.optimize(context)

      assert %OptimizationContext{} = result
      assert result.optimization_applied == true
      assert result.openai_optimized == true
    end

    test "optimizes for consistent reasoning" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Solve this logical problem"
        },
        provider_info: %{provider: :openai, model: "gpt-4o"},
        model_capabilities: %{consistency: :excellent}
      }

      result = OpenAIOptimizer.optimize(context)

      assert result.consistent_reasoning_optimized == true
    end

    test "enhances structured output requests when needed" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Generate a JSON response with user data"
        },
        provider_info: %{provider: :openai, model: "gpt-4o"},
        model_capabilities: %{structured_output: :good}
      }

      result = OpenAIOptimizer.optimize(context)

      assert result.structured_output_enhanced == true
      prompt = result.enhanced_prompt.enhanced_prompt

      assert String.contains?(prompt, "JSON") or
               String.contains?(prompt, "schema") or
               String.contains?(prompt, "format")
    end

    test "optimizes for API reliability" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Process this complex request"
        },
        provider_info: %{provider: :openai, model: "gpt-4o"},
        model_capabilities: %{api_reliability: :excellent}
      }

      result = OpenAIOptimizer.optimize(context)

      assert result.api_reliability_optimized == true
    end

    test "leverages strong language capabilities" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Write a comprehensive documentation"
        },
        provider_info: %{provider: :openai, model: "gpt-4o"},
        model_capabilities: %{language_understanding: :excellent}
      }

      result = OpenAIOptimizer.optimize(context)

      assert result.language_capabilities_leveraged == true
    end

    test "optimizes creative and analytical balance" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Create a unique solution to this technical problem"
        },
        provider_info: %{provider: :openai, model: "gpt-4o"},
        model_capabilities: %{creative_tasks: :excellent}
      }

      result = OpenAIOptimizer.optimize(context)

      assert result.creative_analytical_balanced == true
    end

    test "formats for OpenAI preferences" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Simple task"
        },
        provider_info: %{provider: :openai, model: "gpt-4o"},
        model_capabilities: %{}
      }

      result = OpenAIOptimizer.optimize(context)

      assert result.optimization_applied == true
      assert result.openai_formatted == true
    end
  end

  describe "optimize_for_consistent_reasoning/1" do
    test "adds consistency checks for reasoning tasks" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Analyze this complex scenario"
        },
        provider_info: %{provider: :openai, model: "gpt-4o"}
      }

      result = OpenAIOptimizer.optimize_for_consistent_reasoning(context)

      prompt = result.enhanced_prompt.enhanced_prompt

      assert String.contains?(prompt, "consistency") or
               String.contains?(prompt, "validation") or
               String.contains?(prompt, "reasoning")
    end
  end

  describe "enhance_structured_output_requests/1" do
    test "adds JSON schema specifications for structured output" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Return user information as JSON"
        },
        provider_info: %{provider: :openai, model: "gpt-4o"}
      }

      result = OpenAIOptimizer.enhance_structured_output_requests(context)

      prompt = result.enhanced_prompt.enhanced_prompt

      assert String.contains?(prompt, "schema") or
               String.contains?(prompt, "format") or
               String.contains?(prompt, "JSON")
    end

    test "skips structured output enhancement for non-structured requests" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Write a casual email"
        },
        provider_info: %{provider: :openai, model: "gpt-4o"}
      }

      result = OpenAIOptimizer.enhance_structured_output_requests(context)

      # Should not modify prompt significantly for non-structured output
      assert String.length(result.enhanced_prompt.enhanced_prompt) <=
               String.length(context.enhanced_prompt.enhanced_prompt) * 1.2
    end
  end

  describe "requires_structured_output?/1" do
    test "detects structured output requirements" do
      structured_prompts = [
        "Return the result as JSON",
        "Generate XML output with schema",
        "Format the response as YAML",
        "Create a structured data response",
        "Output in table format"
      ]

      for prompt_text <- structured_prompts do
        enhanced_prompt = %EnhancedPrompt{enhanced_prompt: prompt_text}
        assert OpenAIOptimizer.requires_structured_output?(enhanced_prompt) == true
      end
    end

    test "identifies non-structured output requests" do
      non_structured_prompts = [
        "Write a story about adventure",
        "Explain the concept of gravity",
        "Give me advice on career choices",
        "Summarize this article"
      ]

      for prompt_text <- non_structured_prompts do
        enhanced_prompt = %EnhancedPrompt{enhanced_prompt: prompt_text}
        assert OpenAIOptimizer.requires_structured_output?(enhanced_prompt) == false
      end
    end
  end

  describe "optimize_gpt_token_usage/2" do
    test "compresses content when approaching token limit" do
      long_prompt = String.duplicate("This is repetitive content. ", 1000)
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: long_prompt}

      model_info = %{model: "gpt-4o", token_limit: 128_000}

      result = OpenAIOptimizer.optimize_gpt_token_usage(enhanced_prompt, model_info)

      # Should be compressed when near token limit
      assert String.length(result.enhanced_prompt) < String.length(long_prompt)
    end

    test "preserves content when well under token limit" do
      short_prompt = "This is a short prompt"
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: short_prompt}

      model_info = %{model: "gpt-4o", token_limit: 128_000}

      result = OpenAIOptimizer.optimize_gpt_token_usage(enhanced_prompt, model_info)

      # Should remain unchanged when well under limit
      assert result.enhanced_prompt == short_prompt
    end

    test "applies multiple optimization strategies for high token usage" do
      very_long_prompt = String.duplicate("Repetitive example content with common terms. ", 2000)
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: very_long_prompt}

      model_info = %{model: "gpt-3.5-turbo", token_limit: 16_000}

      result = OpenAIOptimizer.optimize_gpt_token_usage(enhanced_prompt, model_info)

      # Should apply aggressive compression
      assert String.length(result.enhanced_prompt) < String.length(very_long_prompt) * 0.8
    end
  end

  describe "get_gpt_token_limit/1" do
    test "returns correct token limits for different GPT models" do
      assert OpenAIOptimizer.get_gpt_token_limit("gpt-4o") == 128_000
      assert OpenAIOptimizer.get_gpt_token_limit("gpt-4-turbo") == 128_000
      assert OpenAIOptimizer.get_gpt_token_limit("gpt-3.5-turbo") == 16_385
    end

    test "returns default limit for unknown models" do
      assert OpenAIOptimizer.get_gpt_token_limit("unknown-model") == 8_000
    end
  end

  describe "estimate_gpt_tokens/1" do
    test "estimates token count for typical prompts" do
      prompt = "This is a test prompt with about ten words"
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: prompt}

      token_count = OpenAIOptimizer.estimate_gpt_tokens(enhanced_prompt)

      # Should estimate roughly 10-15 tokens for this prompt
      assert token_count >= 8 and token_count <= 20
    end

    test "estimates higher token count for longer prompts" do
      long_prompt = String.duplicate("word ", 1000)
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: long_prompt}

      token_count = OpenAIOptimizer.estimate_gpt_tokens(enhanced_prompt)

      # Should estimate roughly 1000+ tokens
      assert token_count >= 900
    end
  end
end
