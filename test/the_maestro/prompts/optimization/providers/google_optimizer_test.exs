defmodule TheMaestro.Prompts.Optimization.Providers.GoogleOptimizerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Optimization.Providers.GoogleOptimizer
  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  alias TheMaestro.Prompts.Optimization.Structs.OptimizationContext

  describe "optimize/1" do
    test "applies Gemini-specific optimizations" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Generate a UI component with multiple functions"
        },
        provider_info: %{provider: :google, model: "gemini-1.5-pro"},
        model_capabilities: %{
          multimodal: :excellent,
          function_calling: :excellent,
          code_generation: :excellent
        }
      }

      result = GoogleOptimizer.optimize(context)

      assert %OptimizationContext{} = result
      assert result.optimization_applied == true
      assert result.gemini_optimized == true
    end

    test "optimizes for multimodal capabilities when visual elements present" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Analyze this image and describe the user interface elements",
          metadata: %{has_images: true}
        },
        provider_info: %{provider: :google, model: "gemini-1.5-pro"},
        model_capabilities: %{multimodal: :excellent}
      }

      result = GoogleOptimizer.optimize(context)

      assert result.multimodal_optimized == true
      prompt = result.enhanced_prompt.enhanced_prompt
      assert String.contains?(prompt, "visual") or String.contains?(prompt, "image")
    end

    test "enhances function calling integration when tools available" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Help me manage files and run commands"
        },
        provider_info: %{provider: :google, model: "gemini-1.5-pro"},
        available_tools: [
          %{name: "read_file", description: "Read file contents"},
          %{name: "execute_command", description: "Run shell commands"}
        ],
        model_capabilities: %{function_calling: :excellent}
      }

      result = GoogleOptimizer.optimize(context)

      assert result.function_calling_optimized == true
      prompt = result.enhanced_prompt.enhanced_prompt
      assert String.contains?(prompt, "tool") or String.contains?(prompt, "function")
    end

    test "optimizes for code generation tasks" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Write a Python class for data processing"
        },
        provider_info: %{provider: :google, model: "gemini-1.5-pro"},
        model_capabilities: %{code_generation: :excellent}
      }

      result = GoogleOptimizer.optimize(context)

      assert result.code_generation_optimized == true
    end

    test "leverages large context window for comprehensive tasks" do
      large_context_prompt = String.duplicate("Context data: ", 5000)

      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{enhanced_prompt: large_context_prompt},
        provider_info: %{provider: :google, model: "gemini-1.5-pro"},
        model_capabilities: %{context_window: 2_000_000}
      }

      result = GoogleOptimizer.optimize(context)

      assert result.large_context_leveraged == true
    end

    test "integrates Google services context when relevant" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Help me with Google Drive integration"
        },
        provider_info: %{provider: :google, model: "gemini-1.5-pro"},
        model_capabilities: %{integration_capabilities: :excellent}
      }

      result = GoogleOptimizer.optimize(context)

      assert result.google_services_integrated == true
    end

    test "formats for Gemini preferences" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Simple task"
        },
        provider_info: %{provider: :google, model: "gemini-1.5-pro"},
        model_capabilities: %{}
      }

      result = GoogleOptimizer.optimize(context)

      assert result.optimization_applied == true
      assert result.gemini_formatted == true
    end
  end

  describe "optimize_for_multimodal_capabilities/1" do
    test "adds visual analysis instructions when visual elements present" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Analyze this chart",
          metadata: %{has_images: true}
        },
        provider_info: %{provider: :google, model: "gemini-1.5-pro"}
      }

      result = GoogleOptimizer.optimize_for_multimodal_capabilities(context)

      prompt = result.enhanced_prompt.enhanced_prompt

      assert String.contains?(prompt, "visual") or
               String.contains?(prompt, "analysis") or
               String.contains?(prompt, "image")
    end

    test "skips multimodal optimization when no visual elements" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Write a text summary",
          metadata: %{}
        },
        provider_info: %{provider: :google, model: "gemini-1.5-pro"}
      }

      result = GoogleOptimizer.optimize_for_multimodal_capabilities(context)

      assert result.enhanced_prompt.enhanced_prompt == context.enhanced_prompt.enhanced_prompt
    end
  end

  describe "enhance_function_calling_integration/1" do
    test "optimizes tool usage when tools are available" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{enhanced_prompt: "Help with file operations"},
        provider_info: %{provider: :google, model: "gemini-1.5-pro"},
        available_tools: [
          %{name: "read_file", description: "Read file contents"},
          %{name: "write_file", description: "Write file contents"}
        ]
      }

      result = GoogleOptimizer.enhance_function_calling_integration(context)

      prompt = result.enhanced_prompt.enhanced_prompt

      assert String.contains?(prompt, "tool") or
               String.contains?(prompt, "function") or
               String.contains?(prompt, "parameter")
    end

    test "skips function calling optimization when no tools available" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{enhanced_prompt: "Write a summary"},
        provider_info: %{provider: :google, model: "gemini-1.5-pro"},
        available_tools: []
      }

      result = GoogleOptimizer.enhance_function_calling_integration(context)

      assert result.enhanced_prompt.enhanced_prompt == context.enhanced_prompt.enhanced_prompt
    end
  end

  describe "has_visual_elements?/1" do
    test "detects visual elements in prompt metadata" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Analyze this",
        metadata: %{has_images: true}
      }

      assert GoogleOptimizer.has_visual_elements?(enhanced_prompt) == true
    end

    test "detects visual keywords in prompt text" do
      visual_prompts = [
        "Look at this image and describe it",
        "Analyze this chart data",
        "What do you see in this screenshot?",
        "Describe the visual elements"
      ]

      for prompt_text <- visual_prompts do
        enhanced_prompt = %EnhancedPrompt{enhanced_prompt: prompt_text}
        assert GoogleOptimizer.has_visual_elements?(enhanced_prompt) == true
      end
    end

    test "returns false when no visual elements present" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Write a text summary",
        metadata: %{}
      }

      assert GoogleOptimizer.has_visual_elements?(enhanced_prompt) == false
    end
  end

  describe "extract_available_tools/1" do
    test "extracts tools from optimization context" do
      tools = [
        %{name: "read_file", description: "Read file contents"},
        %{name: "write_file", description: "Write file contents"}
      ]

      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{enhanced_prompt: "Test context"},
        provider_info: %{provider: :google, model: "gemini-1.5-pro"},
        available_tools: tools
      }

      result = GoogleOptimizer.extract_available_tools(context)

      assert result == tools
    end

    test "returns empty list when no tools available" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{enhanced_prompt: "Test context"},
        provider_info: %{provider: :google, model: "gemini-1.5-pro"},
        available_tools: []
      }

      result = GoogleOptimizer.extract_available_tools(context)

      assert result == []
    end
  end
end
