defmodule TheMaestro.Prompts.Optimization.Providers.AnthropicOptimizerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Optimization.Providers.AnthropicOptimizer
  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  alias TheMaestro.Prompts.Optimization.Structs.OptimizationContext

  describe "optimize/1" do
    test "applies Claude-specific optimizations" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Write a complex function to process data"
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        model_capabilities: %{
          reasoning_strength: :excellent,
          code_understanding: :excellent,
          context_window: 200_000
        }
      }

      result = AnthropicOptimizer.optimize(context)

      assert %OptimizationContext{} = result
      assert result.optimization_applied == true
      assert String.contains?(result.enhanced_prompt.enhanced_prompt, "systematically")
    end

    test "adds thinking framework for complex reasoning tasks" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt:
            "Analyze this complex architectural problem and provide multiple solutions"
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        model_capabilities: %{reasoning_strength: :excellent}
      }

      result = AnthropicOptimizer.optimize(context)

      prompt = result.enhanced_prompt.enhanced_prompt
      assert String.contains?(prompt, "analyze the current situation")
      assert String.contains?(prompt, "Consider multiple approaches")
      assert String.contains?(prompt, "explain your reasoning")
    end

    test "optimizes for large context when prompt exceeds threshold" do
      large_prompt = String.duplicate("This is a very long context. ", 2000)

      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{enhanced_prompt: large_prompt},
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        model_capabilities: %{context_window: 200_000}
      }

      result = AnthropicOptimizer.optimize(context)

      prompt = result.enhanced_prompt.enhanced_prompt

      assert String.contains?(prompt, "navigation aids") or
               String.contains?(prompt, "hierarchical") or
               String.contains?(prompt, "summarization")
    end

    test "enhances instruction clarity for Claude" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Do something with the code"
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        model_capabilities: %{instruction_following: :excellent}
      }

      result = AnthropicOptimizer.optimize(context)

      assert result.optimization_applied == true
      # The prompt should be more detailed and structured after optimization
      assert String.length(result.enhanced_prompt.enhanced_prompt) >
               String.length(context.enhanced_prompt.enhanced_prompt)
    end

    test "utilizes structured thinking patterns" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Help me design a system"
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        model_capabilities: %{structured_thinking: :excellent}
      }

      result = AnthropicOptimizer.optimize(context)

      assert result.optimization_applied == true
      assert result.structured_thinking_applied == true
    end

    test "optimizes safety considerations for Claude" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Generate code that handles user input"
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        model_capabilities: %{safety_awareness: :excellent}
      }

      result = AnthropicOptimizer.optimize(context)

      assert result.optimization_applied == true
      assert result.safety_optimized == true
    end

    test "formats for Claude preferences" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Simple task"
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        model_capabilities: %{}
      }

      result = AnthropicOptimizer.optimize(context)

      assert result.optimization_applied == true
      assert result.claude_formatted == true
    end
  end

  describe "leverage_reasoning_capabilities/1" do
    test "adds reasoning framework for complex tasks" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Solve this multi-step problem",
          metadata: %{}
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"}
      }

      result = AnthropicOptimizer.leverage_reasoning_capabilities(context)

      prompt = result.enhanced_prompt.enhanced_prompt
      assert String.contains?(prompt, "step by step")
      assert String.contains?(prompt, "validation")
    end

    test "skips reasoning framework for simple tasks" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "What is 2+2?",
          metadata: %{}
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"}
      }

      result = AnthropicOptimizer.leverage_reasoning_capabilities(context)

      assert result.enhanced_prompt.enhanced_prompt == context.enhanced_prompt.enhanced_prompt
    end
  end

  describe "optimize_for_large_context/1" do
    test "adds context navigation aids for very large prompts" do
      large_prompt = String.duplicate("Context section. ", 3000)

      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: large_prompt,
          metadata: %{}
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"}
      }

      result = AnthropicOptimizer.optimize_for_large_context(context)

      assert result.large_context_optimized == true
    end

    test "skips large context optimization for normal sized prompts" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Small prompt",
          metadata: %{}
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"}
      }

      result = AnthropicOptimizer.optimize_for_large_context(context)

      assert result.enhanced_prompt.enhanced_prompt == context.enhanced_prompt.enhanced_prompt
    end
  end

  describe "complex_reasoning_required?/1" do
    test "detects complex reasoning keywords" do
      complex_prompts = [
        "Analyze the architectural implications",
        "Design a system that handles multiple scenarios",
        "Compare and contrast different approaches",
        "Evaluate the trade-offs between solutions"
      ]

      for prompt <- complex_prompts do
        enhanced_prompt = %EnhancedPrompt{enhanced_prompt: prompt}
        assert AnthropicOptimizer.complex_reasoning_required?(enhanced_prompt) == true
      end
    end

    test "identifies simple tasks that don't require complex reasoning" do
      simple_prompts = [
        "What is the capital of France?",
        "Write a hello world program",
        "List the files in this directory",
        "Format this text"
      ]

      for prompt <- simple_prompts do
        enhanced_prompt = %EnhancedPrompt{enhanced_prompt: prompt}
        assert AnthropicOptimizer.complex_reasoning_required?(enhanced_prompt) == false
      end
    end
  end

  describe "exceeds_token_threshold?/2" do
    test "correctly identifies prompts exceeding token threshold" do
      large_prompt = String.duplicate("token ", 25_000)
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: large_prompt}

      assert AnthropicOptimizer.exceeds_token_threshold?(enhanced_prompt, 50_000) == true
    end

    test "correctly identifies prompts below token threshold" do
      small_prompt = "This is a small prompt"
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: small_prompt}

      assert AnthropicOptimizer.exceeds_token_threshold?(enhanced_prompt, 50_000) == false
    end
  end
end
