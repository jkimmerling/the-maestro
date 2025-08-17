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

          <div class="mt-10 flex items-center justify-center gap-x-6">
            <.link
              navigate={~p"/setup"}
              class="rounded-md bg-indigo-600 px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
            >
              Setup Provider & Chat
            </.link>
            <.link
              href="https://github.com/your-org/the-maestro"
              class="text-sm font-semibold leading-6 text-gray-900 hover:text-gray-700"
            >
              View on GitHub <span aria-hidden="true">→</span>
            </.link>
          </div>
        </div>
      </main>
    </div>
    """
  end
end
