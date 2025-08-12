# Epic 2, Story 2.4: Real-time Streaming & Status Updates

## Overview

This tutorial explains how we implemented real-time streaming responses and transparent status updates for the AI agent interface. Users can now see the agent's responses appearing word-by-word and get visual feedback when tools are being used.

## Learning Objectives

By the end of this tutorial, you'll understand:

- How to implement streaming LLM responses in Elixir
- Using Phoenix PubSub for real-time communication between GenServer and LiveView
- Handling asynchronous status updates in Phoenix LiveView
- Creating responsive UI feedback during long-running operations

## Architecture Overview

### Components

1. **Agent GenServer** - Broadcasts streaming chunks and status updates
2. **Phoenix PubSub** - Message bus for real-time communication
3. **AgentLive** - Receives and displays streaming updates
4. **UI Components** - Visual indicators for different states

### Message Flow

```
User Input → AgentLive → Agent GenServer → LLM Provider
                ↑                ↓
           PubSub Messages ← Status Updates
```

## Implementation Details

### 1. Agent GenServer Streaming

The core streaming implementation involves broadcasting PubSub messages during LLM processing:

```elixir
# Broadcasting status updates
defp broadcast_status_update(agent_id, status) do
  Phoenix.PubSub.broadcast(
    TheMaestro.PubSub,
    "agent:#{agent_id}",
    {:status_update, status}
  )
end

# Broadcasting streaming chunks
defp broadcast_stream_chunk(agent_id, chunk) do
  Phoenix.PubSub.broadcast(
    TheMaestro.PubSub,
    "agent:#{agent_id}",
    {:stream_chunk, chunk}
  )
end
```

#### Stream Callback Pattern

We use a callback pattern to handle streaming from LLM providers:

```elixir
stream_callback = fn
  {:chunk, chunk} -> broadcast_stream_chunk(agent_id, chunk)
  :complete -> :ok
end

completion_opts = %{
  model: "gemini-2.5-flash",
  stream_callback: stream_callback
}
```

### 2. Tool Call Status Broadcasting

During tool execution, we broadcast start and end events:

```elixir
defp handle_tool_calls_with_streaming(state, auth_context, messages, tool_calls, initial_content) do
  tool_results =
    Enum.map(tool_calls, fn tool_call ->
      # Broadcast tool call start
      broadcast_tool_call_start(state.agent_id, tool_call)
      
      result = execute_tool_call(tool_call)
      
      # Broadcast tool call end
      broadcast_tool_call_end(state.agent_id, tool_call, result)
      
      result
    end)
  # ... rest of implementation
end
```

### 3. LiveView Message Handling

The AgentLive handles various streaming events:

```elixir
def handle_info({:status_update, status}, socket) do
  status_message = case status do
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
```

### 4. UI State Management

The LiveView tracks multiple UI states:

```elixir
socket =
  socket
  |> assign(:streaming_content, "")  # Current streaming text
  |> assign(:current_status, "")     # Status message
  |> assign(:loading, false)         # General loading state
```

### 5. Template Updates

The HEEx template displays different states conditionally:

```heex
<!-- Streaming content display -->
<%= if @streaming_content != "" do %>
  <div class="message assistant justify-start">
    <div class="max-w-xs lg:max-w-md px-4 py-2 rounded-lg bg-gray-200 text-gray-900">
      <div class="whitespace-pre-wrap">{@streaming_content}</div>
      <div class="flex items-center space-x-2 mt-2">
        <div class="animate-pulse flex space-x-1">
          <div class="h-1 w-1 bg-gray-400 rounded-full animate-bounce"></div>
          <div class="h-1 w-1 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.1s"></div>
          <div class="h-1 w-1 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.2s"></div>
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
        <span class="text-sm text-blue-600">{@current_status}</span>
      </div>
    </div>
  </div>
<% end %>
```

## Testing Strategy

### Unit Tests

We test the streaming functionality with asynchronous message assertions:

```elixir
test "sends stream_chunk messages during processing", %{agent_id: agent_id} do
  # Subscribe to PubSub for this agent
  Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agent:#{agent_id}")

  # Send message to trigger streaming
  task = Task.async(fn -> Agent.send_message(agent_id, "Stream test message") end)

  # Should receive streaming status messages
  assert_receive {:status_update, :thinking}, 1000
  assert_receive {:stream_chunk, chunk} when is_binary(chunk), 2000

  # Wait for completion
  assert {:ok, response} = Task.await(task, 5000)
  assert response.type == :assistant
end
```

### TestProvider Streaming Simulation

The TestProvider simulates streaming for testing:

```elixir
defp simulate_streaming(content, stream_callback) do
  # Split content into words and stream them
  words = String.split(content, " ")
  
  Enum.each(words, fn word ->
    # Small delay to simulate real streaming
    Process.sleep(50)
    stream_callback.({:chunk, word <> " "})
  end)
  
  # Send completion signal
  stream_callback.(:complete)
end
```

## Key Patterns and Best Practices

### 1. Asynchronous Processing with Synchronous API

The Agent GenServer maintains a synchronous public API while performing asynchronous streaming internally:

```elixir
def handle_call({:send_message, message}, _from, state) do
  # Update state immediately
  thinking_state = %{state | loop_state: :thinking}
  
  # Broadcast status update
  broadcast_status_update(state.agent_id, :thinking)
  
  # Process with streaming (but return synchronously)
  case get_llm_response_with_streaming(thinking_state, message) do
    {:ok, response} -> {:reply, {:ok, response}, final_state}
    {:error, reason} -> {:reply, {:error, reason}, error_state}
  end
end
```

### 2. State Cleanup

Always clean up streaming state when processing completes:

```elixir
def handle_info({:processing_complete, _final_response}, socket) do
  socket =
    socket
    |> assign(:streaming_content, "")
    |> assign(:current_status, "")
    |> assign(:loading, false)
    
  {:noreply, socket}
end
```

### 3. PubSub Topic Naming

Use consistent topic naming for agent-specific channels:

```elixir
# Subscribe to agent updates
Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agent:#{agent_id}")

# Broadcast to agent channel
Phoenix.PubSub.broadcast(TheMaestro.PubSub, "agent:#{agent_id}", message)
```

## Benefits Achieved

1. **Real-time Feedback** - Users see responses as they're generated
2. **Transparent Operations** - Clear indicators when tools are being used
3. **Better UX** - No more waiting in silence for responses
4. **Responsive Interface** - UI updates immediately reflect agent state

## Next Steps

In the next story (2.5), we'll implement the CLI Device Authorization Flow Backend to support terminal-based authentication.

## Further Reading

- [Phoenix PubSub Documentation](https://hexdocs.pm/phoenix_pubsub/)
- [Phoenix LiveView Streams](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#stream/3)
- [GenServer Patterns in OTP](https://hexdocs.pm/elixir/GenServer.html)
- [Phoenix LiveView Handle Info](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#c:handle_info/2)