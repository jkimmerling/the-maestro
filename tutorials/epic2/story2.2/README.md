# Epic 2, Story 2.2: Configurable Web User Authentication

## Overview

This tutorial explains how we implemented configurable authentication in The Maestro project, supporting both secure multi-user and simple single-user modes. The authentication system uses Google OAuth via Ueberauth and can be completely disabled for development or single-user deployments.

## What We Built

In this story, we implemented a flexible authentication system that:

1. **Added Ueberauth dependencies** for OAuth integration
2. **Created configurable authentication settings** that can be enabled/disabled
3. **Implemented a complete OAuth flow** with Google authentication
4. **Added route protection** that respects the configuration
5. **Updated UI components** to show appropriate login/logout controls
6. **Built comprehensive tests** covering all authentication scenarios

## Technical Implementation

### Dependencies Added

We added the following authentication-related dependencies to `mix.exs`:

```elixir
# Authentication Dependencies
{:ueberauth, "~> 0.10"},
{:ueberauth_google, "~> 0.12"}
```

### Configuration System

The authentication system is controlled by a single configuration setting in `config/config.exs`:

```elixir
config :the_maestro,
  ecto_repos: [TheMaestro.Repo],
  generators: [timestamp_type: :utc_datetime],
  # Authentication configuration - set to false to disable authentication requirement
  require_authentication: true
```

We also configured Ueberauth for Google OAuth:

```elixir
# Configure Ueberauth for OAuth authentication
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, []}
  ]

# Configure Ueberauth Google strategy
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: {:system, "GOOGLE_CLIENT_ID"},
  client_secret: {:system, "GOOGLE_CLIENT_SECRET"}
```

### Authentication Controller

We created `lib/the_maestro_web/controllers/auth_controller.ex` to handle OAuth flows:

```elixir
defmodule TheMaestroWeb.AuthController do
  use TheMaestroWeb, :controller
  plug Ueberauth

  # Successful OAuth callback
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_info = %{
      "id" => auth.uid,
      "email" => auth.info.email,
      "name" => auth.info.name,
      "avatar" => auth.info.image
    }
    
    conn
    |> put_session(:current_user, user_info)
    |> put_flash(:info, "Successfully authenticated!")
    |> redirect(to: ~p"/agent")
  end

  # OAuth failure callback
  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate. Please try again.")
    |> redirect(to: ~p"/")
  end

  # Logout functionality
  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/")
  end
end
```

Key features of our implementation:
- **Secure session management**: User data is stored in encrypted Phoenix sessions
- **Error handling**: Graceful handling of OAuth failures and edge cases
- **Flash messages**: Clear feedback to users about authentication status
- **Clean logout**: Properly clears all session data

### Route Protection Plug

We created a reusable plug at `lib/the_maestro_web/plugs/require_auth.ex`:

```elixir
defmodule TheMaestroWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  def call(conn, _opts) do
    if authentication_required?() do
      case get_session(conn, :current_user) do
        nil -> 
          conn
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: "/")
          |> halt()
        _user -> 
          conn
      end
    else
      # Authentication is disabled, allow access
      conn
    end
  end

  defp authentication_required? do
    Application.get_env(:the_maestro, :require_authentication, true)
  end
end
```

This plug provides:
- **Configuration-aware protection**: Only enforces authentication when enabled
- **Graceful fallback**: Clear error messages and redirects
- **Session validation**: Checks for valid user sessions

### Router Configuration

We updated `lib/the_maestro_web/router.ex` with authentication routes and protection:

```elixir
# New pipeline for protected routes
pipeline :auth_required do
  plug :browser
  plug TheMaestroWeb.Plugs.RequireAuth
end

# Authentication routes
scope "/auth", TheMaestroWeb do
  pipe_through :browser

  get "/logout", AuthController, :logout
  get "/:provider", AuthController, :request
  get "/:provider/callback", AuthController, :callback
end

# Protected routes (require authentication if enabled)
scope "/", TheMaestroWeb do
  pipe_through :auth_required

  live "/agent", AgentLive, :index
end
```

### LiveView Integration

#### Home Page with Conditional UI

We updated `HomeLive` to show appropriate authentication controls:

```elixir
def mount(_params, session, socket) do
  current_user = Map.get(session, "current_user")
  authentication_enabled = authentication_enabled?()
  
  socket =
    socket
    |> assign(:current_user, current_user)
    |> assign(:authentication_enabled, authentication_enabled)

  {:ok, socket}
end
```

The template renders different buttons based on authentication state:

```heex
<%= if @authentication_enabled do %>
  <%= if @current_user do %>
    <!-- Logged in user: Show agent access + logout -->
    <.link navigate={~p"/agent"}>Open Agent Chat</.link>
    <.link href={~p"/auth/logout"}>Logout</.link>
  <% else %>
    <!-- Not logged in: Show login button -->
    <.link href={~p"/auth/google"}>Login with Google</.link>
  <% end %>
<% else %>
  <!-- Authentication disabled: Direct access -->
  <.link navigate={~p"/agent"}>Open Agent Chat</.link>
<% end %>
```

#### Agent Page with Session Handling

The `AgentLive` page handles both authenticated and anonymous access:

```elixir
def mount(_params, session, socket) do
  current_user = Map.get(session, "current_user")
  
  socket =
    socket
    |> assign(:current_user, current_user)
    |> assign(:authentication_enabled, authentication_enabled?())

  {:ok, socket}
end
```

## Key Design Decisions

### 1. Configuration-Driven Architecture

Instead of hardcoding authentication requirements, we made it configurable:

```elixir
# Easy to disable for development
config :the_maestro, require_authentication: false

# Easy to enable for production
config :the_maestro, require_authentication: true
```

**Benefits:**
- Single toggle for entire authentication system
- Simplifies development and testing
- Supports both single-user and multi-user deployments

### 2. Session-Based Authentication

We chose Phoenix sessions over JWT tokens:

**Advantages:**
- Built into Phoenix with encryption
- Automatic CSRF protection
- Simpler to implement and debug
- No token expiration complexity for web UI

**Trade-offs:**
- Server-side session storage
- Not suitable for API-only access (will be addressed in later stories)

### 3. Plug-Based Route Protection

Using a custom plug for route protection provides:

- **Reusability**: Single plug protects multiple routes
- **Configuration awareness**: Respects global authentication settings
- **Clean separation**: Authentication logic separate from business logic
- **Testability**: Easy to test in isolation

### 4. Graceful Degradation

When authentication is disabled:
- No authentication checks are performed
- UI shows direct access buttons
- Users can access all features immediately
- No confusing authentication prompts

## Environment Variables

For Google OAuth to work, you need to set these environment variables:

```bash
export GOOGLE_CLIENT_ID="your-google-oauth-client-id"
export GOOGLE_CLIENT_SECRET="your-google-oauth-client-secret"
```

To obtain these:
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Enable the Google+ API
4. Create OAuth 2.0 credentials
5. Add your redirect URI: `http://localhost:4000/auth/google/callback`

## Testing Strategy

Our comprehensive test suite covers:

### Controller Tests (`auth_controller_test.exs`)
```elixir
# Test successful OAuth callback
test "stores user info in session and redirects to agent" do
  auth = %Ueberauth.Auth{uid: "123", info: %{email: "test@example.com"}}
  conn = conn |> assign(:ueberauth_auth, auth) |> get("/auth/google/callback")
  
  assert redirected_to(conn) == "/agent"
  assert get_session(conn, :current_user)["email"] == "test@example.com"
end
```

### Plug Tests (`require_auth_test.exs`)
```elixir
# Test authentication enforcement
test "redirects when user not logged in and auth enabled" do
  Application.put_env(:the_maestro, :require_authentication, true)
  conn = conn |> init_test_session(%{}) |> RequireAuth.call(%{})
  
  assert conn.halted
  assert redirected_to(conn) == "/"
end
```

### LiveView Tests
```elixir
# Test conditional UI rendering
test "shows login button when authentication enabled and user not logged in" do
  {:ok, _view, html} = live(conn, "/")
  assert html =~ "Login with Google"
end
```

## Security Considerations

### 1. CSRF Protection
- Phoenix's built-in CSRF protection covers our forms
- OAuth state parameter provides additional protection
- Session encryption prevents tampering

### 2. Session Security
- Sessions are encrypted and signed by Phoenix
- Sensitive data (passwords, tokens) not stored in sessions
- Session timeout handled by Phoenix configuration

### 3. OAuth Security
- Proper redirect URI validation
- State parameter validation (basic implementation)
- Error handling prevents information disclosure

### 4. Configuration Security
- OAuth secrets loaded from environment variables
- No secrets hardcoded in configuration files
- Development vs. production separation

## Usage Examples

### Enable Authentication (Production Mode)
```bash
# config/config.exs
config :the_maestro, require_authentication: true

# Set environment variables
export GOOGLE_CLIENT_ID="your-client-id"
export GOOGLE_CLIENT_SECRET="your-client-secret"

# Start server
mix phx.server
```

User flow:
1. Visit `http://localhost:4000`
2. Click "Login with Google" 
3. Complete OAuth flow in browser
4. Redirected back to agent page
5. Access agent features

### Disable Authentication (Development Mode)
```bash
# config/config.exs  
config :the_maestro, require_authentication: false

# Start server (no OAuth setup needed)
mix phx.server
```

User flow:
1. Visit `http://localhost:4000`
2. Click "Open Agent Chat" directly
3. Immediate access to agent features

## Future Enhancements

This authentication foundation prepares us for:

1. **Story 2.3**: Agent LiveView will use session data to create user-specific agent processes
2. **Story 2.5**: CLI device authorization flow will extend this OAuth implementation
3. **Epic 3**: Multiple authentication methods (API keys, service accounts)
4. **Epic 4**: TUI will reuse the same configuration system

## Running the Code

To test the authentication implementation:

```bash
# Run authentication-specific tests
mix test test/the_maestro_web/controllers/auth_controller_test.exs
mix test test/the_maestro_web/plugs/require_auth_test.exs
mix test test/the_maestro_web/live/home_live_test.exs

# Test with authentication enabled (requires OAuth setup)
mix phx.server
# Visit: http://localhost:4000

# Test with authentication disabled
# Edit config/config.exs: require_authentication: false
mix phx.server
# Visit: http://localhost:4000
```

The authentication system provides a solid foundation for both development ease and production security, with clean separation between authenticated and anonymous usage modes.

## Next Steps

With configurable authentication in place, Story 2.3 will build the main agent interface that works with both authenticated and anonymous users, leveraging the session management system we've built here.