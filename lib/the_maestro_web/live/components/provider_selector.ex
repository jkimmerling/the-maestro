defmodule TheMaestroWeb.Live.Components.ProviderSelector do
  @moduledoc """
  Component for provider selection with branding and status indicators.
  """
  use TheMaestroWeb, :live_component

  def render(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Choose Your AI Provider</h2>
      <p class="text-gray-600 mb-6">
        Select the AI provider you'd like to use for your conversations.
      </p>

      <div class="space-y-4">
        <%= for provider <- @available_providers do %>
          <div 
            class={[
              "relative rounded-lg border-2 p-4 cursor-pointer transition-all duration-200",
              "hover:border-#{provider.color}-300 hover:bg-#{provider.color}-50",
              "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-#{provider.color}-500"
            ]}
            phx-click="select_provider"
            phx-value-provider={provider.id}
            tabindex="0"
            role="button"
            aria-label={"Select #{provider.name}"}
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-4">
                <!-- Provider Icon -->
                <div class={[
                  "flex-shrink-0 w-12 h-12 rounded-lg flex items-center justify-center text-2xl",
                  "bg-#{provider.color}-100"
                ]}>
                  {provider.icon}
                </div>

                <!-- Provider Info -->
                <div class="flex-1">
                  <div class="flex items-center space-x-2">
                    <h3 class="text-lg font-medium text-gray-900">{provider.name}</h3>
                    <.provider_status_badge status={Map.get(@provider_status, provider.id, :unknown)} />
                  </div>
                  <p class="text-sm text-gray-600 mt-1">{provider.description}</p>
                </div>
              </div>

              <!-- Selection Indicator -->
              <div class="flex-shrink-0">
                <.icon name="hero-chevron-right" class="h-5 w-5 text-gray-400" />
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def provider_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-1 rounded-full text-xs font-medium",
      case @status do
        :available -> "bg-green-100 text-green-800"
        :unavailable -> "bg-red-100 text-red-800"
        :degraded -> "bg-yellow-100 text-yellow-800"
        _ -> "bg-gray-100 text-gray-800"
      end
    ]}>
      <span class={[
        "w-1.5 h-1.5 rounded-full mr-1",
        case @status do
          :available -> "bg-green-400"
          :unavailable -> "bg-red-400"
          :degraded -> "bg-yellow-400"
          _ -> "bg-gray-400"
        end
      ]}></span>
      {status_text(@status)}
    </span>
    """
  end

  defp status_text(:available), do: "Available"
  defp status_text(:unavailable), do: "Unavailable"
  defp status_text(:degraded), do: "Issues"
  defp status_text(_), do: "Unknown"
end