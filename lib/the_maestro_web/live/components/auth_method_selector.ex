defmodule TheMaestroWeb.Live.Components.AuthMethodSelector do
  @moduledoc """
  Component for selecting authentication method (OAuth vs API Key).
  """
  use TheMaestroWeb, :live_component

  def render(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Choose Authentication Method</h2>
      <p class="text-gray-600 mb-6">
        How would you like to authenticate with {@selected_provider |> provider_display_name()}?
      </p>

      <div class="space-y-4">
        <%= if :oauth in @available_auth_methods do %>
          <div
            class="relative rounded-lg border-2 border-gray-200 p-4 cursor-pointer hover:border-blue-300 hover:bg-blue-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-all duration-200"
            phx-click="select_auth_method"
            phx-value-method="oauth"
            tabindex="0"
            role="button"
            aria-label="Use OAuth authentication"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-4">
                <!-- OAuth Icon -->
                <div class="flex-shrink-0 w-12 h-12 rounded-lg bg-blue-100 flex items-center justify-center">
                  <.icon name="hero-shield-check" class="h-6 w-6 text-blue-600" />
                </div>
                
    <!-- OAuth Info -->
                <div class="flex-1">
                  <div class="flex items-center space-x-2">
                    <h3 class="text-lg font-medium text-gray-900">OAuth Authentication</h3>
                    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
                      Recommended
                    </span>
                  </div>
                  <p class="text-sm text-gray-600 mt-1">
                    Secure authentication through {@selected_provider |> provider_display_name()}'s official login flow.
                    No need to manage API keys.
                  </p>
                  <ul class="text-xs text-gray-500 mt-2 space-y-1">
                    <li>• Most secure authentication method</li>
                    <li>• Automatic token refresh</li>
                    <li>• Can be revoked from provider dashboard</li>
                  </ul>
                </div>
              </div>
              
    <!-- Selection Indicator -->
              <div class="flex-shrink-0">
                <.icon name="hero-chevron-right" class="h-5 w-5 text-gray-400" />
              </div>
            </div>
          </div>
        <% end %>

        <%= if :api_key in @available_auth_methods do %>
          <div
            class="relative rounded-lg border-2 border-gray-200 p-4 cursor-pointer hover:border-orange-300 hover:bg-orange-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500 transition-all duration-200"
            phx-click="select_auth_method"
            phx-value-method="api_key"
            tabindex="0"
            role="button"
            aria-label="Use API key authentication"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-4">
                <!-- API Key Icon -->
                <div class="flex-shrink-0 w-12 h-12 rounded-lg bg-orange-100 flex items-center justify-center">
                  <.icon name="hero-key" class="h-6 w-6 text-orange-600" />
                </div>
                
    <!-- API Key Info -->
                <div class="flex-1">
                  <div class="flex items-center space-x-2">
                    <h3 class="text-lg font-medium text-gray-900">API Key Authentication</h3>
                    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-orange-100 text-orange-800">
                      Alternative
                    </span>
                  </div>
                  <p class="text-sm text-gray-600 mt-1">
                    Use your {@selected_provider |> provider_display_name()} API key.
                    You'll need to get this from your provider dashboard.
                  </p>
                  <ul class="text-xs text-gray-500 mt-2 space-y-1">
                    <li>• Requires manual API key management</li>
                    <li>• Direct API access</li>
                    <li>• Stored securely in your session</li>
                  </ul>
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

      <%= if Enum.empty?(@available_auth_methods) do %>
        <div class="text-center py-8">
          <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-red-100">
            <.icon name="hero-exclamation-triangle" class="h-6 w-6 text-red-600" />
          </div>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No Authentication Methods Available</h3>
          <p class="mt-1 text-sm text-gray-500">
            The selected provider doesn't have any configured authentication methods.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp provider_display_name(:anthropic), do: "Claude (Anthropic)"
  defp provider_display_name(:google), do: "Gemini (Google)"
  defp provider_display_name(:openai), do: "ChatGPT (OpenAI)"
  defp provider_display_name(provider), do: to_string(provider)
end
