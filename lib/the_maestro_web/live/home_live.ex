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
