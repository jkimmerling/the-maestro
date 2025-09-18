defmodule TheMaestro.SystemPrompts.DefaultsTest do
  use ExUnit.Case, async: true

  alias TheMaestro.SystemPrompts.Defaults

  test "openai_segments returns non-empty text" do
    segments = Defaults.openai_segments()

    assert [%{"type" => "text", "text" => text}] = segments
    assert String.contains?(text, "You are a coding agent")
  end

  test "anthropic_default_blocks include identity block" do
    blocks = Defaults.anthropic_default_blocks()

    assert [%{"text" => identity} | _] = blocks
    assert identity =~ "Claude Code"
  end

  test "gemini_system_instruction returns base prompt" do
    instruction = Defaults.gemini_system_instruction()

    assert %{"role" => "user", "parts" => [%{"text" => text}]} = instruction

    assert String.contains?(
             text,
             "interactive CLI agent specializing in software engineering tasks"
           )
  end
end
