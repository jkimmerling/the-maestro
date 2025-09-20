defmodule TheMaestro.ConversationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.Conversations` context.
  """

  import Ecto.Query

  alias TheMaestro.Repo
  alias TheMaestro.SuppliedContext.SuppliedContextItem

  import TheMaestro.SuppliedContextFixtures, only: [supplied_context_item_fixture: 1]

  @doc """
  Generate a session.
  """
  def session_fixture(attrs \\ %{}) do
    ensure_default_prompt(:openai)

    # Ensure a Saved Auth exists
    {:ok, sa} =
      TheMaestro.Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name:
          "test_openai_api_key_session_fixture-" <>
            Integer.to_string(System.unique_integer([:positive])),
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    base = %{
      last_used_at: ~U[2025-09-01 15:30:00Z],
      name: "some name",
      auth_id: sa.id
    }

    {:ok, session} =
      attrs
      |> Enum.into(base)
      |> TheMaestro.Conversations.create_session()

    session
  end

  defp ensure_default_prompt(provider) when provider in [:openai, :anthropic, :gemini] do
    existing =
      Repo.one(
        from i in SuppliedContextItem,
          where: i.type == :system_prompt and i.provider == ^provider and i.is_default == true,
          limit: 1
      )

    existing ||
      supplied_context_item_fixture(%{
        type: :system_prompt,
        provider: provider,
        render_format: default_render_format(provider),
        version: 1,
        name: "default-" <> Atom.to_string(provider),
        text: default_text(provider),
        is_default: true,
        position: 0,
        labels: %{},
        metadata: default_metadata(provider)
      })
  end

  defp default_render_format(:anthropic), do: :anthropic_blocks
  defp default_render_format(:gemini), do: :gemini_parts
  defp default_render_format(_), do: :text

  defp default_text(:anthropic), do: "Anthropic default system prompt"
  defp default_text(:gemini), do: "Gemini default system instruction"
  defp default_text(_), do: "OpenAI default system prompt"

  defp default_metadata(:anthropic),
    do: %{"blocks" => [%{"type" => "text", "text" => "Anthropic default system prompt"}]}

  defp default_metadata(:gemini),
    do: %{"parts" => [%{"text" => "Gemini default system instruction"}]}

  defp default_metadata(_), do: %{}
end
