defmodule TheMaestroWeb.AgentLive do
  @moduledoc """
  LiveView for the main agent chat interface.

  This LiveView provides the main interface for users to interact with their AI agent.
  It handles both authenticated and anonymous sessions based on configuration.
  """
  use TheMaestroWeb, :live_view

  alias TheMaestro.Agents

  def mount(_params, session, socket) do
    current_user = Map.get(session, "current_user")
    authentication_enabled = authentication_enabled?()

    # Determine agent_id based on authentication mode
    agent_id =
      if authentication_enabled && current_user do
        "user_#{current_user["id"]}"
      else
        # For anonymous sessions, create session-based agent ID
        csrf_token =
          session["_csrf_token"] ||
            get_connect_params(socket)["_csrf_token"] ||
            :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()

        # Use a truncated version for cleaner agent IDs
        truncated_token = csrf_token |> String.slice(0, 8)
        "session_#{truncated_token}"
      end

    # Get LLM provider from configuration
    llm_provider = Application.get_env(:the_maestro, :llm_provider, TheMaestro.Providers.Gemini)

    # Find or start the agent process
    case Agents.find_or_start_agent(agent_id, llm_provider: llm_provider) do
      {:ok, _pid} ->
        # Subscribe to PubSub updates for this agent
        Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agent:#{agent_id}")

        # Get current conversation history
        agent_state = Agents.get_agent_state(agent_id)

        socket =
          socket
          |> assign(:current_user, current_user)
          |> assign(:agent_id, agent_id)
          |> assign(:messages, agent_state.message_history)
          |> assign(:authentication_enabled, authentication_enabled)
          |> assign(:input_message, "")
          |> assign(:loading, false)
          |> assign(:streaming_content, "")
          |> assign(:current_status, "")
          |> stream(:message_stream, [])

        {:ok, socket}

      {:error, reason} ->
        require Logger
        Logger.error("Failed to start agent for #{agent_id}: #{inspect(reason)}")

        socket =
          socket
          |> assign(:current_user, current_user)
          |> assign(:agent_id, nil)
          |> assign(:messages, [])
          |> assign(:authentication_enabled, authentication_enabled)
          |> assign(:input_message, "")
          |> assign(:loading, false)
          |> assign(:streaming_content, "")
          |> assign(:current_status, "")
          |> stream(:message_stream, [])
          |> put_flash(:error, "Failed to initialize agent. Please refresh the page.")

        {:ok, socket}
    end
  end

  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      # Add user message to local state immediately for responsive UI
      user_message = %{
        type: :user,
        role: :user,
        content: message,
        timestamp: DateTime.utc_now()
      }

      updated_messages = socket.assigns.messages ++ [user_message]

      socket =
        socket
        |> assign(:messages, updated_messages)
        |> assign(:input_message, "")
        |> assign(:loading, true)

      # Send message to agent process asynchronously
      if socket.assigns.agent_id do
        send(self(), {:send_to_agent, message})
      end

      {:noreply, socket}
    end
  end

  def handle_event("clear_message", _params, socket) do
    {:noreply, assign(socket, :input_message, "")}
  end

  def handle_info({:send_to_agent, message}, socket) do
    case Agents.send_message(socket.assigns.agent_id, message) do
      {:ok, response} ->
        # Get updated agent state to ensure we have the complete history
        agent_state = Agents.get_agent_state(socket.assigns.agent_id)

        socket =
          socket
          |> assign(:messages, agent_state.message_history)
          |> assign(:loading, false)

        # Broadcast message update for real-time updates
        Phoenix.PubSub.broadcast(
          TheMaestro.PubSub,
          "agent:#{socket.assigns.agent_id}",
          {:message_added, response}
        )

        {:noreply, socket}

      {:error, reason} ->
        require Logger
        Logger.error("Failed to send message to agent: #{inspect(reason)}")

        socket =
          socket
          |> assign(:loading, false)
          |> put_flash(:error, "Failed to send message. Please try again.")

        {:noreply, socket}
    end
  end

  def handle_info({:message_added, _response}, socket) do
    # Refresh the conversation history when a new message is added
    if socket.assigns.agent_id do
      agent_state = Agents.get_agent_state(socket.assigns.agent_id)
      socket = assign(socket, :messages, agent_state.message_history)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:status_update, status}, socket) do
    status_message =
      case status do
        :thinking -> "Thinking..."
        :idle -> ""
        _ -> "Processing..."
      end

    socket = assign(socket, :current_status, status_message)
    {:noreply, socket}
  end

  def handle_info({:stream_chunk, chunk}, socket) do
    current_content = socket.assigns.streaming_content
    updated_content = current_content <> chunk

    socket = assign(socket, :streaming_content, updated_content)
    {:noreply, socket}
  end

  def handle_info({:tool_call_start, %{name: tool_name}}, socket) do
    status_message = "Using tool: #{tool_name}..."
    socket = assign(socket, :current_status, status_message)
    {:noreply, socket}
  end

  def handle_info({:tool_call_end, %{name: _tool_name, result: _result}}, socket) do
    # Tool call completed, status will be updated by the next message or stream
    {:noreply, socket}
  end

  def handle_info({:processing_complete, _final_response}, socket) do
    # Clear streaming content and status, refresh messages
    if socket.assigns.agent_id do
      agent_state = Agents.get_agent_state(socket.assigns.agent_id)

      socket =
        socket
        |> assign(:messages, agent_state.message_history)
        |> assign(:streaming_content, "")
        |> assign(:current_status, "")
        |> assign(:loading, false)

      {:noreply, socket}
    else
      socket =
        socket
        |> assign(:streaming_content, "")
        |> assign(:current_status, "")
        |> assign(:loading, false)

      {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="mx-auto max-w-4xl px-4 py-8">
        <!-- Header -->
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-gray-900">
            <%= if @authentication_enabled do %>
              <%= if @current_user do %>
                AI Agent Chat
              <% else %>
                Please Log In
              <% end %>
            <% else %>
              Anonymous Agent Chat
            <% end %>
          </h1>

          <%= if @authentication_enabled && @current_user do %>
            <p class="mt-2 text-gray-600">
              Welcome, {@current_user["name"] || @current_user["email"]}!
            </p>
          <% end %>

          <%= if @agent_id do %>
            <p class="mt-2 text-sm text-gray-500">
              Send a message to your AI agent
            </p>
          <% end %>
        </div>

        <%= if @agent_id do %>
          <!-- Chat Container -->
          <div class="bg-white rounded-lg shadow-sm border">
            <!-- Message History -->
            <div
              class="message-history h-96 overflow-y-auto p-4 space-y-4 border-b"
              id="message-container"
            >
              <%= if Enum.empty?(@messages) do %>
                <div class="text-center text-gray-500 py-8">
                  <p>No messages yet. Start a conversation!</p>
                </div>
              <% else %>
                <%= for message <- @messages do %>
                  <div class={[
                    "message flex",
                    (message.type == :user && "user justify-end") || "assistant justify-start"
                  ]}>
                    <div class={[
                      "max-w-xs lg:max-w-md px-4 py-2 rounded-lg break-words",
                      (message.type == :user && "bg-blue-600 text-white") ||
                        "bg-gray-200 text-gray-900"
                    ]}>
                      <div class="whitespace-pre-wrap">{message.content}</div>
                      <div class={[
                        "text-xs mt-1 opacity-75",
                        (message.type == :user && "text-blue-100") || "text-gray-500"
                      ]}>
                        {format_timestamp(message.timestamp)}
                      </div>
                    </div>
                  </div>
                <% end %>
              <% end %>
              
    <!-- Streaming content display -->
              <%= if @streaming_content != "" do %>
                <div class="message assistant justify-start">
                  <div class="max-w-xs lg:max-w-md px-4 py-2 rounded-lg bg-gray-200 text-gray-900">
                    <div class="whitespace-pre-wrap">{@streaming_content}</div>
                    <div class="flex items-center space-x-2 mt-2">
                      <div class="animate-pulse flex space-x-1">
                        <div class="h-1 w-1 bg-gray-400 rounded-full animate-bounce"></div>
                        <div
                          class="h-1 w-1 bg-gray-400 rounded-full animate-bounce"
                          style="animation-delay: 0.1s"
                        >
                        </div>
                        <div
                          class="h-1 w-1 bg-gray-400 rounded-full animate-bounce"
                          style="animation-delay: 0.2s"
                        >
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
              
    <!-- Status indicator -->
              <%= if @current_status != "" && @streaming_content == "" do %>
                <div class="message assistant justify-start">
                  <div class="max-w-xs lg:max-w-md px-4 py-2 rounded-lg bg-blue-100 text-blue-900">
                    <div class="flex items-center space-x-2">
                      <div class="animate-pulse flex space-x-1">
                        <div class="h-2 w-2 bg-blue-400 rounded-full animate-bounce"></div>
                        <div
                          class="h-2 w-2 bg-blue-400 rounded-full animate-bounce"
                          style="animation-delay: 0.1s"
                        >
                        </div>
                        <div
                          class="h-2 w-2 bg-blue-400 rounded-full animate-bounce"
                          style="animation-delay: 0.2s"
                        >
                        </div>
                      </div>
                      <span class="text-sm text-blue-600">{@current_status}</span>
                    </div>
                  </div>
                </div>
              <% end %>
              
    <!-- Loading indicator -->
              <%= if @loading && @current_status == "" && @streaming_content == "" do %>
                <div class="message assistant justify-start">
                  <div class="max-w-xs lg:max-w-md px-4 py-2 rounded-lg bg-gray-200 text-gray-900">
                    <div class="flex items-center space-x-2">
                      <div class="animate-pulse flex space-x-1">
                        <div class="h-2 w-2 bg-gray-400 rounded-full animate-bounce"></div>
                        <div
                          class="h-2 w-2 bg-gray-400 rounded-full animate-bounce"
                          style="animation-delay: 0.1s"
                        >
                        </div>
                        <div
                          class="h-2 w-2 bg-gray-400 rounded-full animate-bounce"
                          style="animation-delay: 0.2s"
                        >
                        </div>
                      </div>
                      <span class="text-sm text-gray-600">Connecting...</span>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
            
    <!-- Message Input Form -->
            <div class="p-4">
              <form phx-submit="send_message" class="flex space-x-2">
                <textarea
                  name="message"
                  value={@input_message}
                  placeholder="Type your message..."
                  rows="2"
                  class="flex-1 resize-none rounded-lg border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                  disabled={@loading}
                  phx-hook="AutoSubmit"
                  id="message-input"
                ></textarea>
                <button
                  type="submit"
                  disabled={@loading}
                  class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <%= if @loading do %>
                    <div class="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full">
                    </div>
                  <% else %>
                    Send
                  <% end %>
                </button>
              </form>
            </div>
          </div>
        <% else %>
          <div class="text-center text-red-600">
            <p>Unable to initialize agent. Please refresh the page.</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp authentication_enabled? do
    Application.get_env(:the_maestro, :require_authentication, true)
  end

  defp format_timestamp(timestamp) do
    timestamp
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 5)
  end
end
