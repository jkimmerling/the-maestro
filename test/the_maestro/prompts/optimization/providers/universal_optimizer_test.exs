defmodule TheMaestro.Prompts.Optimization.Providers.UniversalOptimizerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  alias TheMaestro.Prompts.Optimization.Structs.OptimizationContext
  alias TheMaestro.Prompts.Optimization.Providers.UniversalOptimizer

  describe "apply_universal_optimizations/2" do
    test "optimizes instruction clarity by using active voice" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "The code should be written in Python.",
        metadata: %{}
      }

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should convert passive voice to active voice
      assert String.contains?(result.enhanced_prompt, "must")
    end

    test "eliminates ambiguous language" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Do some stuff with those things kinda quickly.",
        metadata: %{}
      }

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should replace vague terms
      refute String.contains?(result.enhanced_prompt, "stuff")
      refute String.contains?(result.enhanced_prompt, "things")
      refute String.contains?(result.enhanced_prompt, "kinda")
    end

    test "adds clear task boundaries for unstructured prompts" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Write a function that calculates factorial."
      }

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should add task structure
      assert String.contains?(result.enhanced_prompt, "## Primary Task")
      assert String.contains?(result.enhanced_prompt, "## Expected Deliverable")
    end

    test "preserves existing task structure" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "## Task\nWrite a function that calculates factorial."
      }

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should not duplicate task headers
      task_count =
        result.enhanced_prompt
        |> String.split("## Task")
        |> length()
        |> Kernel.-(1)

      assert task_count == 1
    end

    test "adds output structure when missing" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Do something with data.",
        metadata: %{}
      }

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should add task structure with deliverable specification
      assert String.contains?(result.enhanced_prompt, "## Expected Deliverable") or
               String.contains?(result.enhanced_prompt, "## Output Requirements")
    end

    test "preserves existing output specifications" do
      enhanced_prompt = %EnhancedPrompt{
        enhanced_prompt: "Analyze this code and provide detailed output with examples."
      }

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should not add duplicate output requirements
      refute String.contains?(result.enhanced_prompt, "## Output Requirements")
    end
  end

  describe "optimize/1" do
    test "applies universal optimizations to optimization context" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Do some analysis stuff."
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet"}
      }

      result = UniversalOptimizer.optimize(context)

      assert result.optimization_applied == true
      assert result.enhanced_prompt.metadata.universal_optimizations_applied == true
      assert result.enhanced_prompt.enhanced_prompt != context.enhanced_prompt.enhanced_prompt
    end

    test "maintains optimization context structure" do
      context = %OptimizationContext{
        enhanced_prompt: %EnhancedPrompt{
          enhanced_prompt: "Simple task."
        },
        provider_info: %{provider: :google, model: "gemini-pro"},
        optimization_targets: %{quality: :high}
      }

      result = UniversalOptimizer.optimize(context)

      assert result.provider_info == context.provider_info
      assert result.optimization_targets == context.optimization_targets
    end
  end

  describe "context organization" do
    test "adds hierarchical structure to long unstructured text" do
      long_text = String.duplicate("This is a long piece of text. ", 50)
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: long_text, metadata: %{}}

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should add structure to long text (either Context/Instructions or Primary Task/Expected Deliverable)
      structured =
        String.contains?(result.enhanced_prompt, "## Context") or
          String.contains?(result.enhanced_prompt, "## Primary Task")

      assert structured

      instructions =
        String.contains?(result.enhanced_prompt, "## Instructions") or
          String.contains?(result.enhanced_prompt, "## Expected Deliverable")

      assert instructions
    end

    test "preserves existing structure in organized text" do
      structured_text = """
      ## Background
      This is the background information.

      ## Requirements
      These are the requirements.
      """

      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: structured_text}

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should not add duplicate structure
      context_count =
        result.enhanced_prompt
        |> String.split("## Context")
        |> length()
        |> Kernel.-(1)

      assert context_count == 0
    end

    test "improves section headers and formatting" do
      text_with_lists = """
      1. First item
      2. Second item
      Important: This is important
      """

      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: text_with_lists}

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should improve formatting
      assert String.contains?(result.enhanced_prompt, "### 1.")
      assert String.contains?(result.enhanced_prompt, "#### Important:")
    end

    test "removes excessive line breaks and trailing whitespace" do
      messy_text = "Line 1   \n\n\n\nLine 2\t\n\n\n\nLine 3  "
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: messy_text}

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should clean up formatting
      refute String.contains?(result.enhanced_prompt, "\n\n\n")
      refute String.match?(result.enhanced_prompt, ~r/[ \t]+$/)
    end
  end

  describe "task decomposition and quality enhancements" do
    test "adds processing instructions for complex tasks" do
      complex_text = String.duplicate("Analyze and evaluate this complex system. ", 25)
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: complex_text}

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should add processing instructions for long, complex tasks
      assert String.contains?(result.enhanced_prompt, "## Processing Instructions")
      assert String.contains?(result.enhanced_prompt, "systematically")
    end

    test "adds reference aids for complex instructions" do
      lines = Enum.map(1..15, fn i -> "## Section #{i}\nContent for section #{i}" end)
      complex_text = Enum.join(lines, "\n\n")
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: complex_text, metadata: %{}}

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should add reference numbers to headers (numbers may vary due to processing)
      reference_numbers = Regex.scan(~r/\[\d+\] ##/, result.enhanced_prompt)
      # Should have many numbered references
      assert length(reference_numbers) >= 10
    end

    test "enhances examples with quality guidelines" do
      text_with_examples = "Here's an example of what I mean. For instance, you could do this."
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: text_with_examples}

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should add example quality guidelines
      assert String.contains?(result.enhanced_prompt, "## Example Quality Guidelines")
    end

    test "adds task decomposition for complex tasks" do
      complex_task = "Analyze, design, and implement a comprehensive solution."
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: complex_task}

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should suggest task decomposition
      assert String.contains?(result.enhanced_prompt, "## Approach Recommendation")
      assert String.contains?(result.enhanced_prompt, "logical steps")
    end

    test "adds quality validation for important tasks" do
      important_task = "This is a critical analysis that must be accurate and complete."
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: important_task}

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should add quality validation
      assert String.contains?(result.enhanced_prompt, "## Quality Validation")
    end

    test "adds output format guidelines when format is mentioned" do
      format_task = "Please format your response in a clear, structured way."
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: format_task}

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should add format guidelines
      assert String.contains?(result.enhanced_prompt, "## Output Format Guidelines")
    end

    test "preserves specific format requirements" do
      specific_format = "Please format your response as JSON with specific fields."
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: specific_format}

      result =
        UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, %{provider: :test})

      # Should not add generic format guidelines when specific format is mentioned
      refute String.contains?(result.enhanced_prompt, "## Output Format Guidelines")
    end
  end

  describe "provider integration" do
    test "adds provider-neutral enhancements" do
      enhanced_prompt = %EnhancedPrompt{enhanced_prompt: "Simple task."}
      provider_info = %{provider: :anthropic, model: "claude-3-5-sonnet"}

      result = UniversalOptimizer.apply_universal_optimizations(enhanced_prompt, provider_info)

      # Should add general guidelines
      assert String.contains?(result.enhanced_prompt, "## General Guidelines")
      assert result.metadata.provider_optimized == :anthropic
      assert is_float(result.metadata.universal_optimization_score)
      assert result.metadata.universal_optimization_score > 0.0
    end

    test "calculates universal optimization score based on features" do
      structured_prompt = %EnhancedPrompt{
        enhanced_prompt: """
        ## Task
        Analyze this example with step-by-step approach.
        Please validate your results.
        """
      }

      result =
        UniversalOptimizer.apply_universal_optimizations(structured_prompt, %{provider: :test})

      # Should have high score due to structure, examples, steps, and validation
      assert result.metadata.universal_optimization_score > 0.8
    end
  end
end
