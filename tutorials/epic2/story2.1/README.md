# Epic 2, Story 2.1: Phoenix Project Integration & Basic Layout

## Overview

This tutorial explains how we integrated Phoenix LiveView into The Maestro project and created a basic application layout with a LiveView-powered home page.

## What We Built

In this story, we completed the foundation for the web interface by:
1. Adding Phoenix and LiveView dependencies 
2. Creating a proper root layout with header and main content areas
3. Implementing a basic Home LiveView that replaces the default Phoenix controller
4. Setting up testing infrastructure for LiveView components

## Technical Implementation

### Dependencies Added

We added `lazy_html` to support LiveView testing:

```elixir
# mix.exs
{:lazy_html, ">= 0.1.0", only: :test}
```

### Root Layout Updates

We enhanced the root layout (`lib/the_maestro_web/components/layouts/root.html.heex`) to provide proper structure for LiveViews:

```heex
<body class="bg-white">
  <header class="bg-white shadow">
    <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <div class="flex items-center justify-between">
        <h1 class="text-3xl font-bold tracking-tight text-gray-900">The Maestro</h1>
        <nav class="flex space-x-4">
          <a href="/" class="text-gray-600 hover:text-gray-900">Home</a>
        </nav>
      </div>
    </div>
  </header>
  <main class="min-h-screen bg-gray-50">
    {@inner_content}
  </main>
</body>
```

This gives us:
- A consistent header across all pages with The Maestro branding
- A navigation area ready for future menu items
- A main content area where LiveViews will render
- Proper Tailwind CSS styling for a clean, professional look

### Home LiveView Implementation

We created `lib/the_maestro_web/live/home_live.ex`:

```elixir
defmodule TheMaestroWeb.HomeLive do
  use TheMaestroWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-white">
      <main class="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
        <div class="text-center">
          <h1 class="text-4xl font-bold tracking-tight text-gray-900 sm:text-6xl">
            Welcome to The Maestro
          </h1>
          <p class="mt-6 text-lg leading-8 text-gray-600">
            AI Agent System - Robust, fault-tolerant AI agents built with Elixir/OTP
          </p>
        </div>
      </main>
    </div>
    """
  end
end
```

### Router Configuration

We updated the router to use LiveView instead of a traditional controller:

```elixir
# lib/the_maestro_web/router.ex
scope "/", TheMaestroWeb do
  pipe_through :browser
  
  live "/", HomeLive, :index
end
```

### Testing Setup

We created comprehensive tests for the LiveView in `test/the_maestro_web/live/home_live_test.exs`:

```elixir
defmodule TheMaestroWeb.HomeLiveTest do
  use TheMaestroWeb.ConnCase
  import Phoenix.LiveViewTest

  test "disconnected and connected render", %{conn: conn} do
    {:ok, page_live, disconnected_html} = live(conn, ~p"/")

    assert disconnected_html =~ "Welcome to The Maestro"
    assert render(page_live) =~ "Welcome to The Maestro"
  end

  test "displays basic navigation and layout", %{conn: conn} do
    {:ok, _page_live, html} = live(conn, ~p"/")

    assert html =~ "The Maestro"
    assert html =~ "AI Agent System"
  end
end
```

## Key Learnings

### LiveView vs Controller
- LiveViews provide stateful, real-time interactions over WebSocket connections
- They render both server-side (for initial page load) and client-side (for updates)
- Testing requires the `lazy_html` dependency for DOM parsing

### Layout Strategy
- Phoenix uses a two-layer layout system: `root.html.heex` and `app.html.heex`
- We modified the root layout to provide consistent structure across all pages
- The main content area is where individual LiveViews will render their content

### Test-Driven Development
- We wrote tests first to define expected behavior
- Tests verify both disconnected (initial server render) and connected (LiveView) modes
- Comprehensive testing ensures our LiveView works correctly in both scenarios

## Next Steps

This foundation prepares us for Epic 2, Story 2.2, where we'll add configurable authentication. The layout provides space for user authentication controls, and the LiveView architecture supports the stateful interactions needed for login flows.

## Running the Code

To see this implementation in action:

```bash
# Run the tests
mix test test/the_maestro_web/live/home_live_test.exs

# Start the server (after ensuring database is set up)
mix phx.server
```

Visit `http://localhost:4000` to see the new LiveView-powered home page with the updated layout.