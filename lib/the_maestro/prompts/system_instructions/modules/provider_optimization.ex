defmodule TheMaestro.Prompts.SystemInstructions.Modules.ProviderOptimization do
  @moduledoc """
  Provider-specific optimization instructions module for system instructions.
  """

  @doc """
  Generates provider-specific optimization instructions.
  """
  def generate(provider, model) do
    case {provider, model} do
      {:anthropic, "claude-" <> _} ->
        generate_claude_optimizations()

      {:google, "gemini-" <> _} ->
        generate_gemini_optimizations()

      {:openai, "gpt-" <> _} ->
        generate_gpt_optimizations()

      _ ->
        ""
    end
  end

  defp generate_claude_optimizations do
    """
    ## Claude-Specific Optimizations
    - Utilize Claude's strong reasoning capabilities for complex problem analysis
    - Leverage excellent code understanding for software engineering tasks
    - Take advantage of large context window for comprehensive code analysis
    - Use structured thinking for complex multi-step problems
    - Benefit from Claude's careful attention to instructions and safety
    - Utilize strong natural language understanding for requirement analysis
    """
  end

  defp generate_gemini_optimizations do
    """
    ## Gemini-Specific Optimizations
    - Leverage multimodal capabilities when images or visual content is involved
    - Utilize strong code generation and understanding capabilities
    - Take advantage of integrated search capabilities when appropriate
    - Use function calling effectively for tool integration
    - Benefit from strong mathematical and analytical reasoning
    - Utilize efficient token usage and processing speed
    """
  end

  defp generate_gpt_optimizations do
    """
    ## GPT-Specific Optimizations
    - Utilize strong general reasoning and problem-solving capabilities
    - Leverage excellent natural language understanding and generation
    - Take advantage of consistent API behavior for reliable operations
    - Use structured outputs when supported by the model version
    - Benefit from extensive training on code and technical documentation
    - Utilize strong pattern recognition for code analysis
    """
  end
end