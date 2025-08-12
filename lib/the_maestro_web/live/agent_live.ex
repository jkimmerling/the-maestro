defmodule TheMaestroWeb.AgentLive do
  @moduledoc """
  LiveView for the main agent chat interface.

  This LiveView provides the main interface for users to interact with their AI agent.
  It handles both authenticated and anonymous sessions based on configuration.
  """
  use TheMaestroWeb, :live_view

  def mount(_params, session, socket) do
    current_user = Map.get(session, "current_user")

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:messages, [])
      |> assign(:authentication_enabled, authentication_enabled?())

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-white">
      <main class="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
        <div class="text-center">
          <h1 class="text-4xl font-bold tracking-tight text-gray-900 sm:text-6xl">
            AI Agent Interface
          </h1>

          <%= if @authentication_enabled do %>
            <%= if @current_user do %>
              <p class="mt-6 text-lg leading-8 text-gray-600">
                Welcome, {@current_user["name"] || @current_user["email"]}!
              </p>
              <div class="mt-8">
                <p class="text-gray-500">Agent chat interface will be implemented in Story 2.3</p>
              </div>
            <% else %>
              <p class="mt-6 text-lg leading-8 text-gray-600">
                Please log in to access your AI agent.
              </p>
            <% end %>
          <% else %>
            <p class="mt-6 text-lg leading-8 text-gray-600">
              Anonymous access - Agent chat interface will be implemented in Story 2.3
            </p>
          <% end %>
        </div>
      </main>
    </div>
    """
  end

  defp authentication_enabled? do
    Application.get_env(:the_maestro, :require_authentication, true)
  end
end
