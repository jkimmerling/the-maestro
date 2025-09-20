defmodule TheMaestro.SystemPrompts.RendererTest do
  use ExUnit.Case, async: true

  doctest TheMaestro.SystemPrompts.Renderer.OpenAI
  doctest TheMaestro.SystemPrompts.Renderer.Anthropic
  doctest TheMaestro.SystemPrompts.Renderer.Gemini
end
