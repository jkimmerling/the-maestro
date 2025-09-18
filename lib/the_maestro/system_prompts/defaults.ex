defmodule TheMaestro.SystemPrompts.Defaults do
  @moduledoc false

  @openai_prompt_path Path.expand("../../../source/codex/codex-rs/core/prompt.md", __DIR__)
  @external_resource @openai_prompt_path
  @openai_prompt File.read!(@openai_prompt_path)

  @anthropic_identity_path Path.expand(
                             "../../../priv/system_prompts/anthropic_identity.txt",
                             __DIR__
                           )
  @external_resource @anthropic_identity_path
  @anthropic_identity_text @anthropic_identity_path |> File.read!() |> String.trim()

  @anthropic_guidance_path Path.expand(
                             "../../../priv/system_prompts/anthropic_guidance.txt",
                             __DIR__
                           )
  @external_resource @anthropic_guidance_path
  @anthropic_guidance_text File.read!(@anthropic_guidance_path)

  @gemini_base_path Path.expand("../../../priv/system_prompts/gemini_base_prompt.txt", __DIR__)
  @external_resource @gemini_base_path
  @gemini_base_instruction File.read!(@gemini_base_path)

  @anthropic_identity_block %{
    "type" => "text",
    "text" => @anthropic_identity_text,
    "cache_control" => %{"type" => "ephemeral"}
  }

  def openai_segments do
    [%{"type" => "text", "text" => @openai_prompt}]
  end

  def anthropic_identity_block do
    deep_copy(@anthropic_identity_block)
  end

  def anthropic_guidance_block do
    %{"type" => "text", "text" => @anthropic_guidance_text}
  end

  def anthropic_default_blocks do
    [anthropic_identity_block(), anthropic_guidance_block()]
  end

  def gemini_system_instruction do
    %{"role" => "user", "parts" => [%{"text" => @gemini_base_instruction}]}
  end

  def openai_prompt, do: @openai_prompt

  defp deep_copy(term) when is_map(term) do
    term
    |> Enum.map(fn {k, v} -> {deep_copy(k), deep_copy(v)} end)
    |> Enum.into(%{})
  end

  defp deep_copy(term) when is_list(term), do: Enum.map(term, &deep_copy/1)
  defp deep_copy(term), do: term
end
