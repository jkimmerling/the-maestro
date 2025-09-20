defmodule TheMaestroWeb.DashboardPromptPickerTest do
  use TheMaestroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TheMaestro.SuppliedContextFixtures, only: [supplied_context_item_fixture: 1]

  alias TheMaestro.SuppliedContext
  alias TheMaestro.SystemPrompts

  setup do
    SystemPrompts.Seeder.seed!(now: DateTime.utc_now())
    :ok
  end

  test "session prompt picker loads default stacks", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view
    |> element("button[phx-click='open_session_modal']")
    |> render_click()

    # Verify defaults by checking presence of known default prompt entries by id
    openai_base =
      SuppliedContext.get_default_prompt!(:openai, "openai.codex_cli.base", include_shared: false)

    assert has_element?(view, "#session-prompt-picker-openai-#{openai_base.id}")

    view
    |> element("button[phx-click='prompt_picker:tab'][phx-value-provider='anthropic']")
    |> render_click()

    anthropic_identity =
      SuppliedContext.get_default_prompt!(
        :anthropic,
        "anthropic.claude_code.identity",
        include_shared: false
      )

    assert has_element?(view, "#session-prompt-picker-anthropic-#{anthropic_identity.id}")

    view
    |> element("button[phx-click='prompt_picker:tab'][phx-value-provider='gemini']")
    |> render_click()

    gemini_base =
      SuppliedContext.get_default_prompt!(:gemini, "gemini.code_assist.base",
        include_shared: false
      )

    assert has_element?(view, "#session-prompt-picker-gemini-#{gemini_base.id}")
  end

  test "disabling optional prompt updates assigns while immutable stays enabled", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view
    |> element("button[phx-click='open_session_modal']")
    |> render_click()

    view
    |> element("button[phx-click='prompt_picker:tab'][phx-value-provider='anthropic']")
    |> render_click()

    guidance =
      SuppliedContext.get_default_prompt!(
        :anthropic,
        "anthropic.claude_code.guidance",
        include_shared: false
      )

    identity =
      SuppliedContext.get_default_prompt!(
        :anthropic,
        "anthropic.claude_code.identity",
        include_shared: false
      )

    view
    |> element("button[phx-click='prompt_picker:toggle'][phx-value-id='#{guidance.id}']")
    |> render_click()

    # Optional prompt now shows "Enable" (disabled state)
    assert has_element?(
             view,
             "#session-prompt-picker-anthropic-#{guidance.id} button[phx-click='prompt_picker:toggle']",
             "Enable"
           )

    # Immutable identity remains enabled and its toggle is disabled in the UI
    assert has_element?(
             view,
             "#session-prompt-picker-anthropic-#{identity.id} button[phx-click='prompt_picker:toggle'][disabled]"
           )
  end

  test "adding a prompt appends to the openai stack", %{conn: conn} do
    new_prompt =
      supplied_context_item_fixture(%{
        type: :system_prompt,
        provider: :openai,
        render_format: :text,
        text: "Additional openai prompt",
        name: "openai.custom.extra",
        version: 1,
        position: 5,
        metadata: %{"segments" => ["Additional openai prompt"]}
      })

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view
    |> element("button[phx-click='open_session_modal']")
    |> render_click()

    # Use with_target to scope the change event to the picker form
    view
    |> with_target("#session-prompt-picker-openai-add")
    |> render_change("prompt_picker:add", %{"prompt_id" => new_prompt.id})

    # The new prompt entry appears in the OpenAI list
    assert has_element?(view, "#session-prompt-picker-openai-#{new_prompt.id}")
  end
end
