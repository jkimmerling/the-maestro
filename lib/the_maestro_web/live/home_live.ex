defmodule TheMaestroWeb.HomeLive do
  use TheMaestroWeb, :live_view

  def mount(_params, session, socket) do
    current_user = Map.get(session, "current_user")
    authentication_enabled = authentication_enabled?()
    
    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:authentication_enabled, authentication_enabled)

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
          
          <div class="mt-10 flex items-center justify-center gap-x-6">
            <%= if @authentication_enabled do %>
              <%= if @current_user do %>
                <!-- User is logged in -->
                <.link 
                  navigate={~p"/agent"} 
                  class="rounded-md bg-indigo-600 px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
                >
                  Open Agent Chat
                </.link>
                <.link 
                  href={~p"/auth/logout"} 
                  class="text-sm font-semibold leading-6 text-gray-900 hover:text-gray-700"
                >
                  Logout <span aria-hidden="true">→</span>
                </.link>
              <% else %>
                <!-- User is not logged in -->
                <.link 
                  href={~p"/auth/google"} 
                  class="rounded-md bg-indigo-600 px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
                >
                  Login with Google
                </.link>
                <.link 
                  navigate={~p"/agent"} 
                  class="text-sm font-semibold leading-6 text-gray-900 hover:text-gray-700"
                >
                  Learn more <span aria-hidden="true">→</span>
                </.link>
              <% end %>
            <% else %>
              <!-- Authentication is disabled -->
              <.link 
                navigate={~p"/agent"} 
                class="rounded-md bg-indigo-600 px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
              >
                Open Agent Chat
              </.link>
              <.link 
                href="https://github.com/your-org/the-maestro" 
                class="text-sm font-semibold leading-6 text-gray-900 hover:text-gray-700"
              >
                View on GitHub <span aria-hidden="true">→</span>
              </.link>
            <% end %>
          </div>
        </div>
      </main>
    </div>
    """
  end

  defp authentication_enabled? do
    Application.get_env(:the_maestro, :require_authentication, true)
  end
end
