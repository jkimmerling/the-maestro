defmodule TheMaestroWeb.Live.Components.ConnectionStatus do
  @moduledoc """
  Component for displaying real-time provider connection status.
  """
  use TheMaestroWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="inline-flex items-center space-x-2">
      <.status_indicator status={@status} />
      <span class={[
        "text-sm font-medium",
        case @status do
          :connected -> "text-green-700"
          :connecting -> "text-yellow-700"
          :disconnected -> "text-red-700"
          :error -> "text-red-700"
          _ -> "text-gray-700"
        end
      ]}>
        {status_text(@status)}
      </span>

      <%= if @show_details and @last_check do %>
        <span class="text-xs text-gray-500">
          (Last checked: {format_time(@last_check)})
        </span>
      <% end %>
    </div>
    """
  end

  def status_indicator(assigns) do
    ~H"""
    <div class={[
      "w-2 h-2 rounded-full",
      case @status do
        :connected -> "bg-green-400"
        :connecting -> "bg-yellow-400 animate-pulse"
        :disconnected -> "bg-red-400"
        :error -> "bg-red-500"
        _ -> "bg-gray-400"
      end
    ]}>
    </div>
    """
  end

  defp status_text(:connected), do: "Connected"
  defp status_text(:connecting), do: "Connecting..."
  defp status_text(:disconnected), do: "Disconnected"
  defp status_text(:error), do: "Connection Error"
  defp status_text(_), do: "Unknown"

  defp format_time(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 5)
  end

  defp format_time(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} -> format_time(dt)
      _ -> time
    end
  end

  defp format_time(_), do: "Unknown"
end
