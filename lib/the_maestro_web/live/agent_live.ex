defmodule TheMaestroWeb.AgentLive do
  @moduledoc """
  LiveView for the main agent chat interface.

  This LiveView provides the main interface for users to interact with their AI agent.
  It handles both authenticated and anonymous sessions based on configuration.
  """
  use TheMaestroWeb, :live_view
  require Logger

  alias TheMaestro.Agents

  def mount(_params, session, socket) do
    require Logger
    Logger.debug("AgentLive mount session: #{inspect(Map.keys(session))}")

    current_user = Map.get(session, "current_user")
    oauth_credentials = Map.get(session, "oauth_credentials")
    provider_selection = Map.get(session, "provider_selection")
    Logger.debug("oauth_credentials from session: #{inspect(oauth_credentials)}")
    Logger.debug("provider_selection from session: #{inspect(provider_selection)}")

    authentication_enabled = authentication_enabled?()

    agent_id = determine_agent_id(authentication_enabled, current_user, session, socket)
    {llm_provider, auth_context} = get_selected_provider_and_auth(current_user, oauth_credentials)
    agent_opts = build_agent_opts(llm_provider, auth_context, provider_selection)

    case Agents.find_or_start_agent(agent_id, agent_opts) do
      {:ok, _pid} ->
        # Ensure agent has the latest auth context from session
        if auth_context do
          Agents.update_agent_auth_context(agent_id, auth_context)
        end

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
          |> assign(:show_session_modal, false)
          |> assign(:session_name_input, "")
          |> assign(:available_sessions, [])
          # :save or :restore
          |> assign(:session_action, nil)
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
          |> assign(:show_session_modal, false)
          |> assign(:session_name_input, "")
          |> assign(:available_sessions, [])
          |> assign(:session_action, nil)
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

  def handle_event("show_save_session_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_session_modal, true)
      |> assign(:session_action, :save)
      |> assign(:session_name_input, "")

    {:noreply, socket}
  end

  def handle_event("show_restore_session_modal", _params, socket) do
    # Load available sessions for this agent
    available_sessions =
      if socket.assigns.agent_id do
        TheMaestro.Agents.Agent.list_sessions(socket.assigns.agent_id)
      else
        []
      end

    socket =
      socket
      |> assign(:show_session_modal, true)
      |> assign(:session_action, :restore)
      |> assign(:available_sessions, available_sessions)
      |> assign(:session_name_input, "")

    {:noreply, socket}
  end

  def handle_event("close_session_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_session_modal, false)
      |> assign(:session_action, nil)
      |> assign(:session_name_input, "")
      |> assign(:available_sessions, [])

    {:noreply, socket}
  end

  def handle_event("save_session", %{"session_name" => session_name}, socket) do
    session_name = String.trim(session_name)

    if session_name == "" do
      {:noreply, put_flash(socket, :error, "Session name cannot be empty")}
    else
      user_id = get_user_id(socket.assigns.current_user)

      case TheMaestro.Agents.Agent.save_session(socket.assigns.agent_id, session_name, user_id) do
        {:ok, _conversation_session} ->
          socket =
            socket
            |> assign(:show_session_modal, false)
            |> assign(:session_action, nil)
            |> assign(:session_name_input, "")
            |> put_flash(:info, "Session '#{session_name}' saved successfully!")

          {:noreply, socket}

        {:error, %Ecto.Changeset{errors: errors}} ->
          error_message = format_changeset_errors(errors)
          {:noreply, put_flash(socket, :error, "Failed to save session: #{error_message}")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to save session: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("restore_session", %{"session_name" => session_name}, socket) do
    case TheMaestro.Agents.Agent.restore_session(socket.assigns.agent_id, session_name) do
      :ok ->
        socket =
          socket
          |> assign(:show_session_modal, false)
          |> assign(:session_action, nil)
          |> assign(:available_sessions, [])
          |> put_flash(:info, "Session '#{session_name}' restored successfully!")

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Session not found")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to restore session: #{inspect(reason)}")}
    end
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

  def handle_info({:session_restored, session_name}, socket) do
    # Refresh the conversation history when a session is restored
    if socket.assigns.agent_id do
      agent_state = Agents.get_agent_state(socket.assigns.agent_id)

      socket =
        socket
        |> assign(:messages, agent_state.message_history)
        |> put_flash(:info, "Session '#{session_name}' has been restored!")

      {:noreply, socket}
    else
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
            <div class="mt-3">
              <.link
                href={~p"/auth/logout"}
                class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
              >
                Logout
              </.link>
            </div>
          <% end %>

          <%= if @agent_id do %>
            <p class="mt-2 text-sm text-gray-500">
              Send a message to your AI agent
            </p>
            <!-- Session Controls -->
            <div class="mt-4 flex space-x-2 justify-center">
              <button
                phx-click="show_save_session_modal"
                class="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-blue-700 bg-blue-100 hover:bg-blue-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                💾 Save Session
              </button>
              <button
                phx-click="show_restore_session_modal"
                class="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-green-700 bg-green-100 hover:bg-green-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
              >
                📂 Restore Session
              </button>
            </div>
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
        
    <!-- Session Management Modal -->
        <%= if @show_session_modal do %>
          <div class="fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
              <!-- Modal Header -->
              <div class="px-6 py-4 border-b border-gray-200">
                <h3 class="text-lg font-medium text-gray-900">
                  <%= case @session_action do %>
                    <% :save -> %>
                      Save Conversation Session
                    <% :restore -> %>
                      Restore Conversation Session
                  <% end %>
                </h3>
              </div>
              
    <!-- Modal Body -->
              <div class="px-6 py-4">
                <%= case @session_action do %>
                  <% :save -> %>
                    <form phx-submit="save_session" class="space-y-4">
                      <div>
                        <label for="session_name" class="block text-sm font-medium text-gray-700 mb-2">
                          Session Name
                        </label>
                        <input
                          type="text"
                          name="session_name"
                          id="session_name"
                          value={@session_name_input}
                          placeholder="Enter a name for this session..."
                          class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                          required
                        />
                      </div>
                      <div class="flex justify-end space-x-2">
                        <button
                          type="button"
                          phx-click="close_session_modal"
                          class="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-200 border border-gray-300 rounded-md hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500"
                        >
                          Cancel
                        </button>
                        <button
                          type="submit"
                          class="px-4 py-2 text-sm font-medium text-white bg-blue-600 border border-transparent rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                        >
                          Save Session
                        </button>
                      </div>
                    </form>
                  <% :restore -> %>
                    <%= if Enum.empty?(@available_sessions) do %>
                      <div class="text-center py-8">
                        <p class="text-gray-500">No saved sessions found.</p>
                        <button
                          phx-click="close_session_modal"
                          class="mt-4 px-4 py-2 text-sm font-medium text-white bg-blue-600 border border-transparent rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                        >
                          Close
                        </button>
                      </div>
                    <% else %>
                      <div class="space-y-3">
                        <p class="text-sm text-gray-600 mb-4">Select a session to restore:</p>
                        <%= for session <- @available_sessions do %>
                          <div class="border border-gray-200 rounded-lg p-3 hover:bg-gray-50">
                            <div class="flex justify-between items-start">
                              <div class="flex-1">
                                <h4 class="font-medium text-gray-900">{session.session_name}</h4>
                                <p class="text-sm text-gray-500">
                                  {session.message_count} messages
                                </p>
                                <p class="text-xs text-gray-400">
                                  Saved {format_timestamp(session.updated_at)}
                                </p>
                              </div>
                              <button
                                phx-click="restore_session"
                                phx-value-session-name={session.session_name}
                                class="ml-3 px-3 py-1.5 text-sm font-medium text-white bg-green-600 border border-transparent rounded-md hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                              >
                                Restore
                              </button>
                            </div>
                          </div>
                        <% end %>
                        <div class="flex justify-end pt-4">
                          <button
                            phx-click="close_session_modal"
                            class="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-200 border border-gray-300 rounded-md hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500"
                          >
                            Cancel
                          </button>
                        </div>
                      </div>
                    <% end %>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp authentication_enabled? do
    Application.get_env(:the_maestro, :require_authentication, true)
  end

  defp format_timestamp(%DateTime{} = timestamp) do
    timestamp
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 5)
  end

  defp format_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> format_timestamp(dt)
      _ -> timestamp
    end
  end

  defp determine_agent_id(authentication_enabled, current_user, session, socket) do
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
  end

  defp create_auth_context(oauth_credentials) do
    if oauth_credentials && oauth_credentials["access_token"] do
      %{
        type: :oauth,
        credentials: %{
          access_token: oauth_credentials["access_token"],
          refresh_token: oauth_credentials["refresh_token"],
          expires_at: oauth_credentials["expires_at"],
          token_type: oauth_credentials["token_type"] || "Bearer"
        }
      }
    else
      nil
    end
  end

  defp build_agent_opts(llm_provider, auth_context, provider_selection \\ nil) do
    agent_opts = [llm_provider: llm_provider]
    
    # Add auth context if available
    agent_opts = if auth_context, do: Keyword.put(agent_opts, :auth_context, auth_context), else: agent_opts
    
    # Add model if available from provider selection
    if provider_selection && provider_selection["model"] do
      Keyword.put(agent_opts, :model, provider_selection["model"])
    else
      agent_opts
    end
  end

  defp get_user_id(nil), do: nil
  defp get_user_id(user) when is_map(user), do: user["id"]

  defp format_changeset_errors(errors) do
    errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
    |> Enum.join(", ")
  end

  defp get_selected_provider_and_auth(_current_user, _oauth_credentials) do
    # Single-user system - check for stored credentials
    case get_stored_provider_credentials() do
      {:ok, provider, credentials} ->
        {resolve_provider_module(provider), credentials}
      
      {:error, :not_found} ->
        # No stored credentials found - use fallback
        {TheMaestro.Providers.Gemini, nil}
    end
  end

  defp get_stored_provider_credentials() do
    # Check for Anthropic credentials first (since that's what user selected)
    case TheMaestro.Providers.Auth.CredentialStore.get_credentials(:anthropic, :oauth) do
      {:ok, cred_data} ->
        auth_context = %{
          type: :oauth,
          credentials: cred_data.credentials,
          config: %{provider: :anthropic}
        }
        {:ok, :anthropic, auth_context}
      
      {:error, :not_found} ->
        # Try other providers if needed
        case TheMaestro.Providers.Auth.CredentialStore.get_credentials(:google, :oauth) do
          {:ok, cred_data} ->
            auth_context = %{
              type: :oauth,
              credentials: cred_data.credentials,
              config: %{provider: :google}
            }
            {:ok, :google, auth_context}
          
          {:error, :not_found} ->
            {:error, :not_found}
        end
    end
  end

  defp resolve_provider_module(:anthropic), do: TheMaestro.Providers.Anthropic
  defp resolve_provider_module(:google), do: TheMaestro.Providers.Gemini
  defp resolve_provider_module(:openai), do: TheMaestro.Providers.OpenAI
  defp resolve_provider_module(_), do: TheMaestro.Providers.Gemini
end
