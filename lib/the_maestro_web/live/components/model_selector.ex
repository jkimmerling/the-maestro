defmodule TheMaestroWeb.Live.Components.ModelSelector do
  @moduledoc """
  Component for dynamic model selection with capability indicators.
  """
  use TheMaestroWeb, :live_component

  alias TheMaestro.Models.Model

  def render(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Choose Your Model</h2>
      <p class="text-gray-600 mb-6">
        Select the specific AI model you'd like to use with {@selected_provider
        |> provider_display_name()}.
      </p>

      <%= if @loading_models do %>
        <div class="text-center py-8">
          <div class="inline-flex items-center space-x-2">
            <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600"></div>
            <span class="text-gray-600">Loading available models...</span>
          </div>
        </div>
      <% else %>
        <%= if Enum.empty?(@available_models) do %>
          <div class="text-center py-8">
            <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-yellow-100">
              <.icon name="hero-exclamation-triangle" class="h-6 w-6 text-yellow-600" />
            </div>
            <h3 class="mt-2 text-sm font-medium text-gray-900">No Models Found</h3>
            <p class="mt-1 text-sm text-gray-500">
              Unable to load models for this provider. Please check your authentication.
            </p>
          </div>
        <% else %>
          <div class="space-y-4">
            <%= for model <- @available_models do %>
              <div
                class="relative rounded-lg border-2 border-gray-200 p-4 cursor-pointer hover:border-blue-300 hover:bg-blue-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-all duration-200"
                phx-click="select_model"
                phx-value-model={model.id}
                tabindex="0"
                role="button"
                aria-label={"Select #{model.name}"}
              >
                <div class="flex items-center justify-between">
                  <div class="flex items-center space-x-4">
                    <!-- Model Icon -->
                    <div class="flex-shrink-0 w-12 h-12 rounded-lg bg-blue-100 flex items-center justify-center">
                      <.icon name="hero-cpu-chip" class="h-6 w-6 text-blue-600" />
                    </div>
                    
    <!-- Model Info -->
                    <div class="flex-1">
                      <div class="flex items-center space-x-2">
                        <h3 class="text-lg font-medium text-gray-900">{model.name}</h3>
                        <.model_badges model={model} />
                      </div>
                      <p class="text-sm text-gray-600 mt-1">{model.description}</p>
                      <.model_capabilities model={model} />
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
        <% end %>
      <% end %>
    </div>
    """
  end

  def model_badges(assigns) do
    ~H"""
    <div class="flex items-center space-x-1">
      <%= if recommended_model?(@model) do %>
        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
          Recommended
        </span>
      <% end %>

      <%= if latest_model?(@model) do %>
        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
          Latest
        </span>
      <% end %>

      <%= if fast_model?(@model) do %>
        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
          Fast
        </span>
      <% end %>
    </div>
    """
  end

  def model_capabilities(assigns) do
    ~H"""
    <div class="flex items-center space-x-4 mt-2 text-xs text-gray-500">
      <div class="flex items-center space-x-1">
        <.icon name="hero-chat-bubble-left-ellipsis" class="h-3 w-3" />
        <span>{get_context_length(@model)} context</span>
      </div>

      <%= if supports_multimodal?(@model) do %>
        <div class="flex items-center space-x-1">
          <.icon name="hero-photo" class="h-3 w-3" />
          <span>Multimodal</span>
        </div>
      <% end %>

      <%= if supports_function_calling?(@model) do %>
        <div class="flex items-center space-x-1">
          <.icon name="hero-cog-6-tooth" class="h-3 w-3" />
          <span>Function calling</span>
        </div>
      <% end %>

      <div class="flex items-center space-x-1">
        <.icon name="hero-currency-dollar" class="h-3 w-3" />
        <span>{get_cost_indicator(@model)}</span>
      </div>
    </div>
    """
  end

  defp provider_display_name(:anthropic), do: "Claude (Anthropic)"
  defp provider_display_name(:google), do: "Gemini (Google)"
  defp provider_display_name(:openai), do: "ChatGPT (OpenAI)"
  defp provider_display_name(provider), do: to_string(provider)

  defp recommended_model?(model) do
    model.id in [
      "claude-3-5-sonnet-20241022",
      "gemini-1.5-pro",
      "gpt-4"
    ]
  end

  defp latest_model?(model) do
    model.id in [
      "claude-3-5-sonnet-20241022",
      "gemini-1.5-pro",
      "gpt-4"
    ]
  end

  defp fast_model?(model) do
    model.id in [
      "claude-3-haiku-20240307",
      "gemini-1.5-flash",
      "gpt-3.5-turbo"
    ]
  end

  defp get_context_length(%Model{context_length: context_length})
       when not is_nil(context_length) do
    cond do
      context_length >= 1_000_000 -> "#{div(context_length, 1_000_000)}M"
      context_length >= 1_000 -> "#{div(context_length, 1_000)}K"
      true -> "#{context_length}"
    end
  end

  defp get_context_length(_), do: "Unknown"

  defp supports_multimodal?(%Model{multimodal: multimodal}), do: multimodal == true
  defp supports_multimodal?(_), do: false

  defp supports_function_calling?(%Model{function_calling: function_calling}),
    do: function_calling == true

  defp supports_function_calling?(_), do: false

  defp get_cost_indicator(%Model{cost_tier: cost_tier}) do
    case cost_tier do
      :premium -> "Premium"
      :balanced -> "Balanced"
      :economy -> "Economy"
      _ -> "Variable"
    end
  end

  defp get_cost_indicator(_), do: "Variable"
end
