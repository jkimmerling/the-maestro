defmodule TheMaestroWeb.AgentLiveTest do
  use TheMaestroWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    # Ensure agents use TestProvider for all tests
    Application.put_env(:the_maestro, :llm_provider, TheMaestro.Providers.TestProvider)
    :ok
  end

  describe "when authentication is enabled" do
    setup do
      Application.put_env(:the_maestro, :require_authentication, true)
      on_exit(fn -> Application.put_env(:the_maestro, :require_authentication, true) end)
      :ok
    end

    test "displays user info and chat interface when logged in", %{conn: conn} do
      user_info = %{"id" => "123", "email" => "test@example.com", "name" => "Test User"}

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user_info)

      {:ok, view, html} = live(conn, ~p"/agent")

      assert html =~ "Welcome, Test User!"
      assert html =~ "Send a message to your AI agent"
      assert has_element?(view, "form[phx-submit='send_message']")
      assert has_element?(view, "textarea[name='message']")
      assert has_element?(view, "button[type='submit']", "Send")
      assert has_element?(view, ".message-history")
    end

    test "starts agent genserver for authenticated user", %{conn: conn} do
      user_info = %{"id" => "123", "email" => "test@example.com", "name" => "Test User"}

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user_info)

      {:ok, view, _html} = live(conn, ~p"/agent")

      # Verify agent process exists for this user
      agent_id = "user_123"
      assert {:ok, _pid} = TheMaestro.Agents.find_or_start_agent(agent_id)
      
      # Check that the view has the correct agent_id by checking internal state
      assert :sys.get_state(view.pid).socket.assigns.agent_id == agent_id
    end

    test "can send message and receive response", %{conn: conn} do
      user_info = %{"id" => "123", "email" => "test@example.com", "name" => "Test User"}

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user_info)

      {:ok, view, _html} = live(conn, ~p"/agent")

      # Submit a message
      view
      |> form("form", message: "Hello, agent!")
      |> render_submit()

      # Should see the user message in history
      assert has_element?(view, ".message.user", "Hello, agent!")
      
      # Wait for async processing and check for agent response
      Process.sleep(100)  # Give time for async message processing
      html = render(view)
      assert html =~ "I received your message"
    end

    test "redirects to home when not logged in", %{conn: conn} do
      conn = init_test_session(conn, %{})

      # When authentication is enabled and no user is logged in,
      # the RequireAuth plug should redirect to home
      assert {:error,
              {:redirect, %{to: "/", flash: %{"error" => "You must log in to access this page."}}}} =
               live(conn, ~p"/agent")
    end
  end

  describe "when authentication is disabled" do
    setup do
      Application.put_env(:the_maestro, :require_authentication, false)
      on_exit(fn -> Application.put_env(:the_maestro, :require_authentication, true) end)
      :ok
    end

    test "allows anonymous access with chat interface", %{conn: conn} do
      conn = init_test_session(conn, %{})

      {:ok, view, html} = live(conn, ~p"/agent")

      assert html =~ "Anonymous Agent Chat"
      assert html =~ "Send a message to your AI agent"
      assert has_element?(view, "form[phx-submit='send_message']")
      assert has_element?(view, "textarea[name='message']")
      assert has_element?(view, "button[type='submit']", "Send")
      assert has_element?(view, ".message-history")
    end

    test "starts agent genserver for anonymous session", %{conn: conn} do
      conn = init_test_session(conn, %{})

      {:ok, view, _html} = live(conn, ~p"/agent")
      
      # The view should have assigned an agent_id
      agent_id = :sys.get_state(view.pid).socket.assigns.agent_id
      assert agent_id
      assert String.starts_with?(agent_id, "session_")
    end

    test "can send message in anonymous mode", %{conn: conn} do
      conn = init_test_session(conn, %{})

      {:ok, view, _html} = live(conn, ~p"/agent")

      # Submit a message
      view
      |> form("form", message: "Hello from anonymous!")
      |> render_submit()

      # Should see the user message in history
      assert has_element?(view, ".message.user", "Hello from anonymous!")
      
      # Wait for async processing and check for agent response
      Process.sleep(100)  # Give time for async message processing
      html = render(view)
      assert html =~ "I received your message"
    end
  end

  describe "conversation history" do
    setup do
      Application.put_env(:the_maestro, :require_authentication, false)
      on_exit(fn -> Application.put_env(:the_maestro, :require_authentication, true) end)
      :ok
    end

    test "maintains conversation history within same LiveView session", %{conn: conn} do
      conn = init_test_session(conn, %{})

      {:ok, view, _html} = live(conn, ~p"/agent")

      # Send multiple messages to create history
      view
      |> form("form", message: "First message")
      |> render_submit()

      Process.sleep(100)

      view
      |> form("form", message: "Second message")
      |> render_submit()

      Process.sleep(100)

      # Should see both messages in the conversation history
      assert has_element?(view, ".message.user", "First message")
      assert has_element?(view, ".message.user", "Second message")
      assert has_element?(view, ".message.assistant", "I received your message: \"First message\"")
      assert has_element?(view, ".message.assistant", "I received your message: \"Second message\"")
    end
  end
end
