defmodule TheMaestro.Prompts.Enhancement.PromptFormatter do
  @moduledoc """
  Final formatting system for enhanced prompts.
  """

  @doc """
  Formats the enhanced prompt for delivery to the LLM provider.
  """
  @spec format_enhanced_prompt(map(), map(), map()) :: map()
  def format_enhanced_prompt(optimized_prompt, validation_result, enhancement_config) do
    formatted = %{
      pre_context: format_pre_context(optimized_prompt),
      enhanced_prompt: format_main_prompt(optimized_prompt),
      post_context: format_post_context(optimized_prompt),
      metadata: build_formatting_metadata(optimized_prompt, validation_result)
    }

    if Map.get(enhancement_config, :provider_optimization, false) do
      apply_provider_formatting(formatted, enhancement_config)
    else
      formatted
    end
  end

  defp format_pre_context(prompt) do
    Map.get(prompt, :pre_context, "")
  end

  defp format_main_prompt(prompt) do
    Map.get(prompt, :enhanced_prompt, "")
  end

  defp format_post_context(prompt) do
    Map.get(prompt, :post_context, "")
  end

  defp build_formatting_metadata(prompt, validation) do
    %{
      formatted_at: DateTime.utc_now(),
      quality_passed: Map.get(validation, :pass, false),
      final_token_count: Map.get(prompt, :total_tokens, 0)
    }
  end

  defp apply_provider_formatting(formatted, _config) do
    # Placeholder for provider-specific formatting
    formatted
  end
end
