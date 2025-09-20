defmodule TheMaestro.SystemPrompts.Seeder do
  @moduledoc """
  Seeds canonical system prompts for each provider with deterministic identifiers.
  """

  alias Ecto.Multi
  alias TheMaestro.{Repo, SuppliedContext}
  alias TheMaestro.SuppliedContext.SuppliedContextItem
  alias TheMaestro.SystemPrompts.Defaults

  @openai_prompt_id "1f0c2a62-2d67-4410-b8c4-3db9b24e7b3e"
  @openai_family_id "0f0f8de3-6c74-4a3d-92d3-8b3b177bb435"

  @anthropic_identity_id "8c6e4c7f-4e97-4999-b6ff-285a6c4cb47f"
  @anthropic_identity_family "cae6a19a-89f0-4c37-91bf-4a6b2d61a4ff"

  @anthropic_guidance_id "1e27b42e-9223-4c2f-9a41-3a67de78dfa1"
  @anthropic_guidance_family "25ac0904-8d24-4a1d-a659-53e3eb8edbaa"

  @gemini_prompt_id "3f5a4dde-96d5-4deb-a9f9-6fa2b1c2c934"
  @gemini_family_id "7f9823a0-0f0e-4c58-9ad0-64f5b3bc1f6b"

  @labels %{"version" => "2025-09-18"}

  @doc """
  Seed canonical prompts. Accepts `:now` option to control timestamps in tests.
  """
  def seed!(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now() |> DateTime.truncate(:second))

    Multi.new()
    |> Multi.run(:seed_openai, fn _repo, _changes ->
      upsert_prompt(openai_prompt_spec(), now)
    end)
    |> Multi.run(:seed_anthropic_identity, fn _repo, _changes ->
      upsert_prompt(anthropic_identity_spec(), now)
    end)
    |> Multi.run(:seed_anthropic_guidance, fn _repo, _changes ->
      upsert_prompt(anthropic_guidance_spec(), now)
    end)
    |> Multi.run(:seed_gemini, fn _repo, _changes ->
      upsert_prompt(gemini_prompt_spec(), now)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        SuppliedContext.invalidate_prompt_cache()
        :ok

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp upsert_prompt(attrs, now) do
    base = %SuppliedContextItem{id: attrs.id}
    changeset = SuppliedContextItem.changeset(base, Map.delete(attrs, :id))

    set_map =
      attrs
      |> Map.take([
        :text,
        :metadata,
        :labels,
        :position,
        :is_default,
        :immutable,
        :render_format,
        :source_ref,
        :version,
        :change_note,
        :editor
      ])
      |> Map.put(:updated_at, now)
      |> Enum.into([])

    Repo.insert(changeset,
      on_conflict: [set: set_map],
      conflict_target: :id,
      returning: true,
      timeout: :infinity
    )
  end

  defp openai_prompt_spec do
    segments = Defaults.openai_segments()

    text =
      segments
      |> Enum.map(&Map.get(&1, "text", ""))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    %{
      id: @openai_prompt_id,
      family_id: @openai_family_id,
      type: :system_prompt,
      provider: :openai,
      render_format: :text,
      name: "openai.codex_cli.base",
      text: text,
      version: 1,
      labels: @labels,
      position: 0,
      is_default: true,
      immutable: true,
      source_ref: "source/codex/codex-rs/core/prompt.md",
      metadata: %{"segments" => segments},
      editor: "system",
      change_note: "Canonical seed"
    }
  end

  defp anthropic_identity_spec do
    block = Defaults.anthropic_identity_block()

    %{
      id: @anthropic_identity_id,
      family_id: @anthropic_identity_family,
      type: :system_prompt,
      provider: :anthropic,
      render_format: :anthropic_blocks,
      name: "anthropic.claude_code.identity",
      text: block["text"],
      version: 1,
      labels: @labels,
      position: 0,
      is_default: true,
      immutable: true,
      source_ref: "anthropic_api_flow__read_file.log#L1183",
      metadata: %{"blocks" => [block]},
      editor: "system",
      change_note: "Canonical seed"
    }
  end

  defp anthropic_guidance_spec do
    block = Defaults.anthropic_guidance_block()
    text = block["text"] |> String.trim_leading()
    updated_block = Map.put(block, "text", text)

    %{
      id: @anthropic_guidance_id,
      family_id: @anthropic_guidance_family,
      type: :system_prompt,
      provider: :anthropic,
      render_format: :anthropic_blocks,
      name: "anthropic.claude_code.guidance",
      text: text,
      version: 1,
      labels: @labels,
      position: 1,
      is_default: true,
      immutable: false,
      source_ref: "anthropic_api_flow__read_file.log#L1190",
      metadata: %{"blocks" => [updated_block]},
      editor: "system",
      change_note: "Canonical seed"
    }
  end

  defp gemini_prompt_spec do
    instruction = Defaults.gemini_system_instruction()
    parts = instruction["parts"] || []

    text =
      parts
      |> Enum.map(&Map.get(&1, "text", ""))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    %{
      id: @gemini_prompt_id,
      family_id: @gemini_family_id,
      type: :system_prompt,
      provider: :gemini,
      render_format: :gemini_parts,
      name: "gemini.code_assist.base",
      text: text,
      version: 1,
      labels: @labels,
      position: 0,
      is_default: true,
      immutable: true,
      source_ref: "gemini_api_flow__mcp_use.log#L333",
      metadata: %{"parts" => parts},
      editor: "system",
      change_note: "Canonical seed"
    }
  end
end
