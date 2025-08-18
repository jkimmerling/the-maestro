defmodule TheMaestroWeb.Live.Components.SecurityConfirmationDialog do
  @moduledoc """
  LiveView component for MCP security confirmation dialogs.
  
  Presents security risk assessments and collects user confirmation decisions
  for MCP tool executions. Supports different risk levels and trust management
  options.
  """
  use TheMaestroWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
      <div class="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
        <!-- Header -->
        <div class="px-6 py-4 border-b border-gray-200">
          <div class="flex items-center space-x-3">
            <.risk_icon risk_level={@confirmation_request.risk_assessment.risk_level} />
            <div>
              <h3 class="text-lg font-semibold text-gray-900">
                MCP Tool Execution Request
              </h3>
              <p class="text-sm text-gray-600">
                Confirm tool execution for security
              </p>
            </div>
          </div>
        </div>

        <!-- Content -->
        <div class="px-6 py-4 space-y-4">
          <!-- Tool Information -->
          <div class="bg-gray-50 rounded-lg p-4">
            <div class="grid grid-cols-2 gap-3 text-sm">
              <div>
                <span class="font-medium text-gray-700">Tool:</span>
                <span class="ml-2 text-gray-900"><%= @tool_name %></span>
              </div>
              <div>
                <span class="font-medium text-gray-700">Server:</span>
                <span class="ml-2 text-gray-900"><%= @context.server_id %></span>
              </div>
            </div>
            
            <%= if @tool_description do %>
              <div class="mt-2">
                <span class="font-medium text-gray-700 text-sm">Description:</span>
                <p class="text-sm text-gray-900 mt-1"><%= @tool_description %></p>
              </div>
            <% end %>
          </div>

          <!-- Risk Assessment -->
          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <span class="font-medium text-gray-700">Risk Assessment</span>
              <.risk_badge risk_level={@confirmation_request.risk_assessment.risk_level} />
            </div>
            
            <%= if length(@confirmation_request.risk_assessment.reasons) > 0 do %>
              <ul class="text-sm text-gray-600 space-y-1 ml-4">
                <%= for reason <- @confirmation_request.risk_assessment.reasons do %>
                  <li class="flex items-start space-x-2">
                    <span class="text-gray-400">•</span>
                    <span><%= reason %></span>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>

          <!-- Parameters Preview -->
          <%= if show_parameters?(@parameters) do %>
            <div class="space-y-2">
              <span class="font-medium text-gray-700">Parameters</span>
              <div class="bg-gray-100 rounded p-3 max-h-32 overflow-y-auto">
                <pre class="text-xs text-gray-800"><%= format_parameters(@parameters) %></pre>
              </div>
            </div>
          <% end %>

          <!-- Sanitization Warnings -->
          <%= if length(@sanitization_warnings) > 0 do %>
            <div class="space-y-2">
              <span class="font-medium text-yellow-700 flex items-center">
                <.icon name="hero-exclamation-triangle" class="w-4 h-4 mr-2" />
                Sanitization Warnings
              </span>
              <ul class="text-sm text-yellow-700 space-y-1 ml-6">
                <%= for warning <- @sanitization_warnings do %>
                  <li class="flex items-start space-x-2">
                    <span class="text-yellow-500">•</span>
                    <span><%= warning %></span>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </div>

        <!-- Actions -->
        <div class="px-6 py-4 border-t border-gray-200 bg-gray-50 rounded-b-lg">
          <div class="flex flex-col space-y-3">
            <!-- Primary Actions -->
            <div class="flex space-x-3">
              <button
                type="button"
                phx-click="confirm_execution"
                phx-target={@myself}
                phx-value-choice="execute_once"
                class="flex-1 bg-blue-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                Execute Once
              </button>
              <button
                type="button"
                phx-click="confirm_execution"
                phx-target={@myself}
                phx-value-choice="cancel"
                class="flex-1 bg-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm font-medium hover:bg-gray-400 focus:outline-none focus:ring-2 focus:ring-gray-500"
              >
                Cancel
              </button>
            </div>

            <!-- Trust Management Actions -->
            <%= if show_trust_options?(@confirmation_request.risk_assessment.risk_level) do %>
              <div class="flex space-x-3">
                <button
                  type="button"
                  phx-click="confirm_execution"
                  phx-target={@myself}
                  phx-value-choice="always_allow_tool"
                  class="flex-1 bg-green-100 text-green-700 px-3 py-2 rounded-md text-xs font-medium hover:bg-green-200 focus:outline-none focus:ring-2 focus:ring-green-500"
                >
                  Always Allow This Tool
                </button>
                <button
                  type="button"
                  phx-click="confirm_execution"
                  phx-target={@myself}
                  phx-value-choice="always_trust_server"
                  class="flex-1 bg-green-100 text-green-700 px-3 py-2 rounded-md text-xs font-medium hover:bg-green-200 focus:outline-none focus:ring-2 focus:ring-green-500"
                >
                  Always Trust Server
                </button>
              </div>
            <% end %>

            <!-- Block Action for High Risk -->
            <%= if @confirmation_request.risk_assessment.risk_level in [:high, :critical] do %>
              <button
                type="button"
                phx-click="confirm_execution"
                phx-target={@myself}
                phx-value-choice="block_tool"
                class="w-full bg-red-100 text-red-700 px-3 py-2 rounded-md text-xs font-medium hover:bg-red-200 focus:outline-none focus:ring-2 focus:ring-red-500"
              >
                Block This Tool
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Event Handlers

  def handle_event("confirm_execution", %{"choice" => choice}, socket) do
    confirmation_result = %TheMaestro.MCP.Security.ConfirmationEngine.ConfirmationResult{
      decision: if(choice == "cancel", do: :deny, else: :allow),
      choice: String.to_atom(choice),
      message: "User confirmed via UI dialog",
      trust_updated: choice in ["always_allow_tool", "always_trust_server", "block_tool"],
      audit_logged: true
    }

    # Send result back to parent LiveView
    send(self(), {:security_confirmation_result, confirmation_result})

    {:noreply, socket}
  end

  # Helper Functions

  defp risk_icon(assigns) do
    icon_class = case assigns.risk_level do
      :low -> "w-6 h-6 text-green-500"
      :medium -> "w-6 h-6 text-yellow-500"
      :high -> "w-6 h-6 text-red-500"
      :critical -> "w-6 h-6 text-red-600"
      _ -> "w-6 h-6 text-gray-500"
    end
    
    icon_name = case assigns.risk_level do
      :low -> "hero-shield-check"
      :medium -> "hero-exclamation-triangle"
      :high -> "hero-exclamation-triangle"
      :critical -> "hero-exclamation-circle"
      _ -> "hero-question-mark-circle"
    end

    assigns = assign(assigns, :icon_class, icon_class) |> assign(:icon_name, icon_name)

    ~H"""
    <.icon name={@icon_name} class={@icon_class} />
    """
  end

  defp risk_badge(assigns) do
    {bg_class, text_class, text} = case assigns.risk_level do
      :low -> {"bg-green-100", "text-green-800", "LOW RISK"}
      :medium -> {"bg-yellow-100", "text-yellow-800", "MEDIUM RISK"}
      :high -> {"bg-red-100", "text-red-800", "HIGH RISK"}  
      :critical -> {"bg-red-200", "text-red-900", "CRITICAL RISK"}
      _ -> {"bg-gray-100", "text-gray-800", "UNKNOWN"}
    end

    assigns = assign(assigns, :bg_class, bg_class) |> assign(:text_class, text_class) |> assign(:text, text)

    ~H"""
    <span class={["px-2 py-1 text-xs font-semibold rounded-full", @bg_class, @text_class]}>
      <%= @text %>
    </span>
    """
  end

  defp show_parameters?(parameters) when is_map(parameters) do
    map_size(parameters) > 0
  end
  defp show_parameters?(_), do: false

  defp format_parameters(parameters) when is_map(parameters) do
    parameters
    |> Jason.encode!(pretty: true)
  rescue
    _ -> inspect(parameters, pretty: true)
  end
  defp format_parameters(parameters), do: inspect(parameters, pretty: true)

  defp show_trust_options?(risk_level) do
    risk_level in [:low, :medium]
  end

  # Default assigns
  def mount(socket) do
    socket = assign(socket, 
      tool_name: "",
      tool_description: nil,
      parameters: %{},
      context: %{},
      confirmation_request: nil,
      sanitization_warnings: []
    )
    
    {:ok, socket}
  end
end