# Epic 2, Story 2.3: Main Agent LiveView Interface for All Users

## Overview

This tutorial explains how the main agent chat interface was implemented in Phoenix LiveView. The interface provides a real-time chat experience that works with both authenticated and anonymous users, handling asynchronous message processing and maintaining conversation history.

## Key Components

### 1. AgentLive LiveView Module

The `TheMaestroWeb.AgentLive` module is the core component that handles:
- User authentication detection
- Agent GenServer process management
- Real-time message handling
- Conversation history display

```elixir
defmodule TheMaestroWeb.AgentLive do
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
        csrf_token = session["_csrf_token"] ||
                    get_connect_params(socket)["_csrf_token"] ||
                    :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
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

        {:ok, socket}
        
      {:error, reason} ->
        # Handle agent initialization errors gracefully
        socket =
          socket
          |> assign(:agent_id, nil)
          |> put_flash(:error, "Failed to initialize agent. Please refresh the page.")
          
        {:ok, socket}
    end
  end
end
```

### 2. Dual Authentication Mode Support

The implementation supports both authenticated and anonymous modes:

**Authenticated Mode:**
- Uses user ID to create unique agent processes: `"user_#{user_id}"`
- Conversation history is tied to the logged-in user
- Multiple browser sessions for the same user share the same agent

**Anonymous Mode:**
- Uses session-based agent IDs: `"session_#{csrf_token}"`
- Each browser session gets its own agent process
- No cross-session history sharing

### 3. Agent GenServer Integration

The LiveView communicates with Agent GenServer processes through the `TheMaestro.Agents` context:

```elixir
# Find or start an agent process
case Agents.find_or_start_agent(agent_id, llm_provider: llm_provider) do
  {:ok, _pid} -> # Agent available
  {:error, reason} -> # Handle initialization failure
end

# Send message to agent
case Agents.send_message(agent_id, message) do
  {:ok, response} -> # Process successful response
  {:error, reason} -> # Handle send failure
end

# Get agent state for conversation history
agent_state = Agents.get_agent_state(agent_id)
```

### 4. Real-time Message Handling

The interface provides immediate UI feedback and asynchronous processing:

```elixir
def handle_event("send_message", %{"message" => message}, socket) do
  if message != "" do
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
```

### 5. PubSub Integration for Real-time Updates

The LiveView subscribes to PubSub updates to handle real-time message broadcasting:

```elixir
# Subscribe to agent-specific updates
Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agent:#{agent_id}")

# Handle broadcasted message updates
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
```

### 6. UI Components

The interface includes several key UI elements:

**Chat Container:**
- Message history with scrollable area
- User and assistant message styling
- Loading indicators for agent responses
- Timestamps for each message

**Input Form:**
- Textarea for message composition
- Send button with loading states
- Form submission handling

**Authentication State Display:**
- Welcome messages for authenticated users
- Anonymous mode indicators
- Error state handling

## Key Features Implemented

### ✅ Configurable Authentication
The LiveView works seamlessly with both authentication enabled and disabled modes, automatically detecting the configuration and adjusting behavior.

### ✅ Agent Process Management
Each user (authenticated) or session (anonymous) gets its own dedicated Agent GenServer process for isolated conversation management.

### ✅ Real-time Message Processing
Messages are processed asynchronously with immediate UI feedback, providing a responsive chat experience.

### ✅ Conversation History
Full conversation history is maintained and displayed, with proper message ordering and timestamps.

### ✅ Error Handling
Graceful error handling for agent initialization failures, message sending errors, and authentication issues.

### ✅ Responsive UI
Clean, accessible chat interface with proper loading states and user feedback.

## Testing Strategy

The implementation includes comprehensive tests covering:

1. **Authentication Modes**: Both enabled and disabled authentication scenarios
2. **Agent Process Integration**: Verification that correct agent processes are started
3. **Message Handling**: Form submission and message processing
4. **Conversation History**: Message persistence and display
5. **Error Scenarios**: Graceful handling of various error conditions

## Architecture Benefits

This implementation provides several architectural benefits:

1. **Separation of Concerns**: UI logic is separated from agent business logic
2. **Scalability**: Each user gets their own isolated agent process
3. **Real-time Updates**: PubSub integration enables real-time message broadcasting
4. **Flexibility**: Works with both authenticated and anonymous users
5. **Fault Tolerance**: Graceful error handling and recovery

## Future Enhancements

The current implementation provides a solid foundation for future enhancements:

- Streaming text responses (Story 2.4)
- Tool usage indicators
- Message editing and deletion
- File upload support
- Message search and filtering
- Conversation export functionality

This tutorial demonstrates how Phoenix LiveView can be used to create sophisticated real-time chat interfaces that integrate with OTP-based backend systems while maintaining clean separation between UI and business logic.