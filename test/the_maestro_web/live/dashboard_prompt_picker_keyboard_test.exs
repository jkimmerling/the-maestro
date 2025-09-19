defmodule TheMaestroWeb.DashboardPromptPickerKeyboardTest do
  use TheMaestroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TheMaestro.SuppliedContextFixtures, only: [supplied_context_item_fixture: 1]

  alias TheMaestro.SystemPrompts

  setup do
    SystemPrompts.Seeder.seed!(now: DateTime.utc_now())
    :ok
  end

  test "move_up/move_down reorder mutable prompts under OpenAI tab", %{conn: conn} do
    p1 =
      supplied_context_item_fixture(%{
        type: :system_prompt,
        provider: :openai,
        render_format: :text,
        text: "Prompt A",
        name: "openai.custom.A",
        version: 1,
        position: 5,
        metadata: %{"segments" => ["Prompt A"]}
      })

    p2 =
      supplied_context_item_fixture(%{
        type: :system_prompt,
        provider: :openai,
        render_format: :text,
        text: "Prompt B",
        name: "openai.custom.B",
        version: 1,
        position: 6,
        metadata: %{"segments" => ["Prompt B"]}
      })

    {:ok, view, _} = live(conn, ~p"/dashboard")

    view |> element("button[phx-click='open_session_modal']") |> render_click()

    # Add both prompts to ensure we have two mutable entries below the pinned default
    view
    |> with_target("#session-prompt-picker-openai-add")
    |> render_change("prompt_picker:add", %{"prompt_id" => p1.id})

    view
    |> with_target("#session-prompt-picker-openai-add")
    |> render_change("prompt_picker:add", %{"prompt_id" => p2.id})

    # Move the second custom prompt up (B above A)
    view
    |> element("#session-prompt-picker-openai-#{p2.id} button[phx-click='prompt_picker:move_up']")
    |> render_click()

    html = render(view)
    idx_a = html_pos(html, p1.id)
    idx_b = html_pos(html, p2.id)
    assert idx_b < idx_a

    # Move it back down (A above B again)
    view
    |> element(
      "#session-prompt-picker-openai-#{p2.id} button[phx-click='prompt_picker:move_down']"
    )
    |> render_click()

    html2 = render(view)
    idx_a2 = html_pos(html2, p1.id)
    idx_b2 = html_pos(html2, p2.id)
    assert idx_a2 < idx_b2
  end

  defp html_pos(html, id) do
    case :binary.match(html, "session-prompt-picker-openai-" <> id) do
      {pos, _len} -> pos
      :nomatch -> flunk("element not found: #{id}")
    end
  end
end
