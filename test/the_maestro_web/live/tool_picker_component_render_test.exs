defmodule TheMaestroWeb.ToolPickerComponentRenderTest do
  use TheMaestroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defmodule HostLive do
    use TheMaestroWeb, :live_view

    @impl true
    def mount(_params, _session, socket) do
      inv = %{
        openai: [
          # MCP items intentionally without :server_label to reproduce bug
          %{name: "resolve-library-id", source: :mcp, description: "Resolve library id"},
          %{name: "get-library-docs", source: :mcp, description: "Get docs"}
        ],
        anthropic: [],
        gemini: []
      }

      {:ok,
       socket
       |> Phoenix.Component.assign(:provider, :openai)
       |> Phoenix.Component.assign(:allowed, %{})
       |> Phoenix.Component.assign(:inv, inv)}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div id="host">
        <.live_component
          module={TheMaestroWeb.ToolPickerComponent}
          id="test-picker"
          provider={@provider}
          session_id="fake-session"
          allowed_by_provider={@allowed}
          inventory_by_provider={@inv}
          show_groups={[:mcp]}
          title="MCP TOOLS"
        />
      </div>
      """
    end
  end

  defmodule HostWithLabelsLive do
    use TheMaestroWeb, :live_view

    @impl true
    def mount(_params, _session, socket) do
      inv = %{
        openai: [
          %{name: "ctx7-resolve", source: :mcp, description: "desc", server_label: "Context7"},
          %{name: "ctx7-docs", source: :mcp, description: "desc", server_label: "Context7"},
          %{name: "misc", source: :mcp, description: "desc"}
        ],
        anthropic: [],
        gemini: []
      }

      {:ok,
       socket
       |> Phoenix.Component.assign(:provider, :openai)
       |> Phoenix.Component.assign(:allowed, %{})
       |> Phoenix.Component.assign(:inv, inv)}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div id="host">
        <.live_component
          module={TheMaestroWeb.ToolPickerComponent}
          id="test-picker"
          provider={@provider}
          session_id="fake-session"
          allowed_by_provider={@allowed}
          inventory_by_provider={@inv}
          show_groups={[:mcp]}
          title="MCP TOOLS"
        />
      </div>
      """
    end
  end

  test "renders MCP items lacking server_label without crashing", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, HostLive)

    assert has_element?(view, "#tool-group-openai-mcp")
    assert has_element?(view, "#tool-openai-resolve-library-id")
    assert has_element?(view, "#tool-openai-get-library-docs")

    html = render(view)
    assert html =~ "MCP TOOLS"
    # Default group label used when :server_label missing
    assert html =~ ">MCP<"
  end

  test "groups by server_label when provided", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, HostWithLabelsLive)

    html = render(view)
    assert html =~ ">Context7<"
    assert has_element?(view, "#tool-openai-ctx7-resolve")
    assert has_element?(view, "#tool-openai-ctx7-docs")
    assert has_element?(view, "#tool-openai-misc")
  end
end
