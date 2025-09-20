defmodule TheMaestroWeb.SessionToolPickerTest do
  use TheMaestroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TheMaestro.ConversationsFixtures

  alias TheMaestro.{Chat, Conversations}

  setup do
    s = session_fixture(%{working_dir: "."})
    {:ok, {s, _}} = Conversations.ensure_seeded_snapshot(s)
    %{session: s}
  end

  test "toggle OpenAI tool and save persists allowed list", %{conn: conn, session: s} do
    {:ok, view, _html} = live(conn, ~p"/sessions/#{s.id}/chat")

    # Open config modal
    view |> element("button", "Config") |> render_click()
    assert has_element?(view, "#session-config-modal")

    # By default, all tools selected (no persisted allowed set). Toggle apply_patch off.
    view
    |> element("#tool-openai-apply_patch input[phx-click='tool_picker:toggle']")
    |> render_click()

    # Save
    render_submit(element(view, "#session-config-form"), %{apply: "defer"})

    # Reload session and assert allowed map set
    s2 = Conversations.get_session!(s.id)
    allowed = get_in(s2.tools, ["allowed", "openai"]) || []
    assert "apply_patch" not in allowed
    # shell should still be present by default
    assert "shell" in allowed
  end

  test "edit session modal has MCP container with correct structure", %{conn: conn, session: s} do
    {:ok, view, _html} = live(conn, ~p"/sessions/#{s.id}/chat")

    # Open config modal
    view |> element("button", "Config") |> render_click()
    assert has_element?(view, "#session-config-modal")

    html = render(view)

    # Parent MCPs heading exists
    assert html =~ ">MCPs<"

    # Servers subheading exists
    servers_idx =
      case :binary.match(html, ">Servers<") do
        {pos, _} -> pos
        _ -> nil
      end

    assert is_integer(servers_idx), "Servers subheading not found"

    # MCP server checkboxes container exists under Servers section
    assert html =~ ~r/id=\"mcp-server-checkboxes\"/

    # New button exists under the selector and helper text
    new_button_idx =
      case :binary.match(html, "phx-click=\"open_mcp_modal\"") do
        {pos, _} -> pos
        _ -> nil
      end

    assert is_integer(new_button_idx), "New MCP button not found"

    # Helper text appears under selector
    assert html =~ "Select one or more connectors to use for this session"
  end

  test "telemetry tools_count reflects allowed filter (OpenAI)", %{session: s} do
    # Set allowed to only shell
    {:ok, _} =
      Conversations.update_session(s, %{
        tools: %{"allowed" => %{"openai" => ["shell"]}}
      })

    Chat.subscribe(s.id)

    # Capture telemetry
    {:ok, cap} = Agent.start_link(fn -> nil end)
    id = attach_openai_handler(cap)

    # Use a stub adapter to avoid real HTTP
    defmodule StubAdapter do
      def stream_request(_req, _opts), do: {:ok, Stream.take(Stream.iterate(0, & &1), 0)}
    end

    {:ok, _} = Chat.start_turn(s.id, nil, "hello", streaming_adapter: StubAdapter)

    meta = wait_for_meta(cap)
    assert is_map(meta)
    assert Map.get(meta, :tools_count) == 1

    :telemetry.detach(id)
  end

  defp attach_openai_handler(agent) do
    h = "test-openai-tools-" <> Integer.to_string(System.unique_integer([:positive]))

    :telemetry.attach(
      h,
      [:providers, :openai, :request_built],
      fn _e, _m, meta, a ->
        Agent.update(a, fn _ -> meta end)
      end,
      agent
    )

    h
  end

  defp wait_for_meta(agent, deadline_ms \\ 5000) do
    t0 = System.monotonic_time(:millisecond)
    do_wait_meta(agent, t0 + deadline_ms)
  end

  defp do_wait_meta(agent, deadline) do
    meta = Agent.get(agent, & &1)

    cond do
      is_map(meta) ->
        meta

      System.monotonic_time(:millisecond) >= deadline ->
        %{}

      true ->
        Process.sleep(50)
        do_wait_meta(agent, deadline)
    end
  end
end
