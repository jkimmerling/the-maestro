defmodule TheMaestro.SystemPrompts.SeederTest do
  use TheMaestro.DataCase

  alias TheMaestro.Repo
  alias TheMaestro.SuppliedContext
  alias TheMaestro.SuppliedContext.SuppliedContextItem
  alias TheMaestro.SystemPrompts.Defaults
  alias TheMaestro.SystemPrompts.Seeder

  @now DateTime.new!(~D[2025-09-18], ~T[12:00:00], "Etc/UTC")

  setup do
    Repo.delete_all(SuppliedContextItem)
    :ok
  end

  test "seed! inserts canonical prompts and is idempotent" do
    assert :ok == Seeder.seed!(now: @now)

    openai = SuppliedContext.list_system_prompts(:openai, only_defaults: true)
    assert [%SuppliedContextItem{text: text, metadata: %{"segments" => segments}}] = openai
    assert String.contains?(text, "You are a coding agent running in the Codex CLI")
    assert segments == Defaults.openai_segments()

    anthropic = SuppliedContext.list_system_prompts(:anthropic, only_defaults: true)
    assert length(anthropic) == 2
    assert Enum.any?(anthropic, &(&1.metadata["blocks"] == [Defaults.anthropic_identity_block()]))

    assert Enum.any?(anthropic, fn item ->
             blocks = item.metadata["blocks"]
             blocks && hd(blocks)["text"] =~ "You are an interactive CLI tool"
           end)

    gemini = SuppliedContext.list_system_prompts(:gemini, only_defaults: true)
    assert [%SuppliedContextItem{metadata: %{"parts" => parts}}] = gemini
    assert parts == Defaults.gemini_system_instruction()["parts"]

    assert :ok == Seeder.seed!(now: @now)
    assert Repo.aggregate(SuppliedContextItem, :count, :id) == 4
  end
end
