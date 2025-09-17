defmodule TheMaestroWeb.MCPHubLiveTest do
  use TheMaestroWeb.ConnCase

  import Phoenix.LiveViewTest
  import TheMaestro.MCPFixtures
  import TheMaestro.ConversationsFixtures

  alias TheMaestro.MCP

  describe "index view" do
    test "renders server cards with definition label and toggles state", %{conn: conn} do
      server =
        server_fixture(%{
          display_name: "Context7",
          name: "context7",
          transport: "stdio",
          command: "./bin/context7",
          args: ["--flag"],
          definition_source: "cli",
          description: "Context7 CLI server"
        })

      {:ok, view, html} = live(conn, ~p"/mcp/servers")

      assert html =~ "Context7"
      assert html =~ "Definition: COMMAND / CLI"

      toggle = element(view, "button[phx-value-id=\"#{server.id}\"]", "Disable")
      render_click(toggle)

      refute MCP.get_server!(server.id).is_enabled
      assert has_element?(view, "button[phx-value-id=\"#{server.id}\"]", "Enable")
    end

    test "imports server via CLI payload", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/mcp/servers/new?mode=cli")

      payload = "mcp add imported --command ./bin/imported --arg=--debug"

      form = form(view, "#mcp-import-form", %{"payload" => payload})

      render_change(form)
      render_submit(form)

      assert view |> element("button[phx-click=\"save_import\"]", "Apply") |> render_click()

      assert MCP.get_server_by_name("imported")

      {:ok, _, html} = live(conn, ~p"/mcp/servers")
      assert html =~ "imported"
    end

    test "creates server via manual form", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/mcp/servers/new")

      params = %{
        "server" => %{
          "display_name" => "Manual Hub",
          "name" => "manual-hub",
          "transport" => "stdio",
          "command" => "./bin/manual",
          "is_enabled" => "true",
          "args_raw" => "",
          "headers_raw" => "",
          "env_raw" => "",
          "tags_raw" => "edge",
          "metadata_raw" => "{\"region\": \"iad\"}"
        }
      }

      view
      |> form("#mcp-server-form", params)
      |> render_submit()

      assert MCP.get_server_by_name("manual-hub")

      {:ok, _, html} = live(conn, ~p"/mcp/servers")
      assert html =~ "Manual Hub"
      assert html =~ "edge"
    end

    test "shows validation error for invalid CLI payload", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/mcp/servers/new?mode=cli")

      form = form(view, "#mcp-import-form", %{"payload" => "mcp add"})

      render_change(form)
      html = render_submit(form)

      assert html =~ "missing server name"
    end

    test "imports server via JSON payload", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/mcp/servers/new?mode=json")

      payload = ~s({"mcp": {"servers": [{"name": "json-api", "command": "./bin/json"}]}})

      form = form(view, "#mcp-import-form", %{"payload" => payload})

      render_change(form)
      render_submit(form)

      assert view |> element("button[phx-click=\"save_import\"]", "Apply") |> render_click()

      assert MCP.get_server_by_name("json-api")
    end

    test "test button surfaces error when transport missing config", %{conn: conn} do
      server =
        server_fixture(%{
          display_name: "Broken",
          name: "broken",
          transport: "stream-http",
          url: "http://localhost:8080"
        })

      {:ok, view, _} = live(conn, ~p"/mcp/servers")

      view
      |> element(~s(button[phx-click="test"][phx-value-id="#{server.id}"]), "Test")
      |> render_click()

      assert render(view) =~ "Broken: Test failed"
    end
  end

  describe "show view" do
    test "displays formatted metadata and timestamps", %{conn: conn} do
      server =
        server_fixture(%{
          display_name: "Vector API",
          name: "vector-api",
          transport: "stream-http",
          url: "https://api.example.com",
          headers: %{"Authorization" => "Bearer token"},
          env: %{"API_KEY" => "secret"},
          metadata: %{"team" => "platform"},
          args: ["--trace"],
          definition_source: "json"
        })

      {:ok, _view, html} = live(conn, ~p"/mcp/servers/#{server.id}")

      assert html =~ "Definition"
      assert html =~ "JSON"
      assert html =~ "Authorization=Bearer token"
      assert html =~ "API_KEY=secret"
      assert html =~ "&quot;team&quot;"
      assert html =~ "Inserted"
      assert html =~ "Updated"
    end
  end

  describe "navigation" do
    test "includes hamburger menu markup", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/mcp/servers")

      assert html =~ "global-nav-toggle"
      assert html =~ "global-nav-dropdown"
      assert html =~ "MCP Hub"
      assert html =~ "Context Library"
    end
  end

  describe "session MCP modal" do
    test "creates a server from session edit modal and auto-selects it", %{conn: conn} do
      session = session_fixture()

      {:ok, view, _} = live(conn, ~p"/sessions/#{session.id}/edit")

      assert view
             |> element("button[phx-click=\"open_mcp_modal\"]", "New MCP Server")
             |> render_click()

      assert has_element?(view, "#session-edit-mcp")

      form_params = %{
        "server" => %{
          "display_name" => "New CLI",
          "name" => "new-cli",
          "transport" => "stdio",
          "command" => "./bin/new-cli",
          "is_enabled" => "true",
          "args_raw" => "",
          "headers_raw" => "",
          "env_raw" => "",
          "tags_raw" => "",
          "metadata_raw" => ""
        }
      }

      view
      |> form("#mcp-server-form", form_params)
      |> render_submit()

      created = MCP.get_server_by_name("new-cli")
      assert created

      html = render(view)
      assert html =~ "New CLI"

      assert has_element?(
               view,
               "select[name=\"session[mcp_server_ids][]\"] option[selected][value=\"#{created.id}\"]"
             )
    end
  end
end
