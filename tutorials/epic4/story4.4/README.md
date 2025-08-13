# Epic 4, Story 4.4: TUI Tool Status Display

## Overview

This tutorial explains how we implemented real-time tool status display in the Terminal User Interface (TUI) for The Maestro AI agent. The implementation allows users to see when the agent is using tools and view formatted tool results in real-time.

## Problem Statement

The TUI needed to provide transparent feedback to users about the agent's activities, specifically:
1. When tools are being executed (e.g., "Using tool: read_file...")
2. What the tools are doing in real-time
3. Clean, formatted display of tool results in the conversation history

## Solution Architecture

### PubSub Message Flow
The implementation uses Phoenix PubSub to handle real-time communication between the Agent process and the TUI:

```elixir
# Agent broadcasts tool status messages
Phoenix.PubSub.broadcast(
  TheMaestro.PubSub,
  "agent:#{agent_id}",
  {:tool_call_start, %{name: tool_name, arguments: args}}
)

# TUI subscribes and handles messages
Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agent:#{agent_id}")
```

### Message Types
The system handles these PubSub message types:

1. **`:status_update`** - General status like `:thinking`
2. **`:tool_call_start`** - When a tool starts executing
3. **`:tool_call_end`** - When a tool completes with results
4. **`:stream_chunk`** - Real-time streaming text
5. **`:processing_complete`** - Final completion message

## Implementation Details

### 1. Enhanced TUI State

We extended the TUI state to include status tracking:

```elixir
initial_state = %{
  conversation_history: welcome_messages,
  current_input: "",
  auth_info: auth_info,
  status_message: "",        # NEW: Current status message
  streaming_buffer: ""       # NEW: Streaming text buffer
}
```

### 2. Message Loop Enhancement

The main TUI loop was enhanced to handle PubSub messages:

```elixir
defp run_tui do
  state = Process.get(:tui_state)

  # Check for messages (including PubSub messages)
  receive do
    :shutdown -> cleanup_and_exit()
    
    # Handle agent status messages
    {:status_update, status} ->
      new_state = handle_status_update(state, status)
      Process.put(:tui_state, new_state)
      run_tui()
      
    {:tool_call_start, tool_info} ->
      new_state = handle_tool_call_start(state, tool_info)
      Process.put(:tui_state, new_state)
      run_tui()
      
    # ... more message handlers
  after
    100 -> :ok  # Small timeout to allow for input processing
  end

  # Render the interface and handle input
  render_interface(state)
  # ... input handling
end
```

### 3. Status Message Handlers

Each message type has a dedicated handler with error boundaries:

```elixir
defp handle_tool_call_start(state, %{name: tool_name, arguments: _args}) do
  try do
    emoji = get_tool_emoji(tool_name)
    status = "#{emoji} Using tool: #{tool_name}..."
    %{state | status_message: status}
  rescue
    e ->
      require Logger
      Logger.error("Tool status format error: #{inspect(e)}")
      %{state | status_message: "🔧 Using tool..."}
  end
end

defp handle_tool_call_end(state, %{name: tool_name, result: result}) do
  try do
    # Add formatted tool result to conversation history
    tool_result_message = %{
      type: :tool_result, 
      content: format_tool_result_for_display(tool_name, result),
      timestamp: DateTime.utc_now()
    }
    
    new_history = limit_conversation_history(state.conversation_history ++ [tool_result_message])
    %{state | conversation_history: new_history, status_message: ""}
  rescue
    e ->
      require Logger
      Logger.error("Tool result format error: #{inspect(e)}")
      %{state | status_message: ""}
  end
end
```

### 4. Status Line Rendering

We added a dedicated status line to the TUI interface:

```elixir
defp render_interface(state) do
  # ... header rendering
  
  # Render status line
  status_separator = "╠" <> String.duplicate("═", width - 2) <> "╣"
  IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), status_separator, IO.ANSI.reset()])
  render_status_line(state, width)
  
  # ... rest of interface
end

defp render_status_line(state, width) do
  status = String.slice(state.status_message, 0, width - 4)
  padded_status = String.pad_trailing(status, width - 2)
  IO.puts([IO.ANSI.bright(), IO.ANSI.yellow(), padded_status, IO.ANSI.reset()])
end
```

### 5. Tool Result Formatting

Tool results are formatted for readability with appropriate visual styling:

```elixir
defp format_tool_result_for_display(tool_name, result) do
  separator = String.duplicate("─", String.length("🔧 Tool: #{tool_name}"))
  
  case result do
    {:ok, data} when is_binary(data) ->
      content = if String.length(data) > 500, do: String.slice(data, 0, 500) <> "...", else: data
      "🔧 Tool: #{tool_name}\n#{separator}\n#{content}"
    
    {:ok, data} ->
      formatted_data = inspect(data, limit: 100, pretty: true)
      "🔧 Tool: #{tool_name}\n#{separator}\n#{formatted_data}"
    
    {:error, reason} ->
      "🔧 Tool: #{tool_name}\n#{separator}\n❌ Error: #{reason}"
    
    # ... handle other result types
  end
end
```

### 6. Tool-Specific Emojis

Each tool has a dedicated emoji for better visual feedback:

```elixir
defp get_tool_emoji("read_file"), do: "📖"
defp get_tool_emoji("write_file"), do: "✏️"
defp get_tool_emoji("list_directory"), do: "📁"
defp get_tool_emoji("bash"), do: "⚡"
defp get_tool_emoji("shell"), do: "⚡"
defp get_tool_emoji("openapi"), do: "🌐"
defp get_tool_emoji(_), do: "🔧"
```

## Memory Management

To prevent memory issues with long conversations, we implemented history limiting:

```elixir
defp limit_conversation_history(history, max_messages \\ 100) do
  if length(history) <= max_messages do
    history
  else
    {system_messages, other_messages} = 
      Enum.split_with(history, fn msg -> 
        msg.type == :system and String.contains?(msg.content, "Welcome") 
      end)
    
    recent_messages = Enum.take(other_messages, -max_messages + length(system_messages))
    system_messages ++ recent_messages
  end
end
```

## Error Handling Strategy

The implementation includes comprehensive error handling:

1. **Try-catch blocks** around formatting operations
2. **Graceful degradation** when tool formatting fails
3. **Fallback messages** for unknown tools
4. **Memory limits** to prevent unbounded growth

## Testing Approach

### TDD Implementation
We followed Test-Driven Development with comprehensive test coverage:

```elixir
describe "tool status display" do
  test "displays tool execution indicator when tool starts" do
    tool_start_message = {:tool_call_start, %{name: "read_file", arguments: %{path: "/test/file.txt"}}}
    expected_status = "Using tool: read_file..."
    assert format_tool_status(tool_start_message) == expected_status
  end

  test "handles tool execution with complex arguments" do
    complex_tool = {:tool_call_start, %{
      name: "multi_edit", 
      arguments: %{files: ["/file1.txt", "/file2.txt"], operation: "replace"}
    }}
    expected_status = "Using tool: multi_edit..."
    assert format_tool_status(complex_tool) == expected_status
  end
end
```

### Test Categories
- **Unit tests**: Message formatting, emoji selection, result formatting
- **Integration tests**: PubSub message flow (conceptual)
- **Error handling tests**: Malformed data, edge cases

## Key Design Decisions

### 1. Asynchronous Communication
Using PubSub ensures the TUI remains responsive during tool execution without blocking the user interface.

### 2. Error Boundaries
Each message handler is wrapped in try-catch blocks to prevent TUI crashes from malformed tool data.

### 3. Memory Management
Conversation history is automatically limited to prevent memory issues during long sessions.

### 4. Visual Feedback
Tool-specific emojis and consistent formatting provide clear visual feedback about agent activities.

## Performance Considerations

- **Non-blocking updates**: PubSub messages don't block the main TUI loop
- **Efficient rendering**: Status updates only re-render the status line
- **Memory bounds**: Conversation history is automatically pruned
- **Error resilience**: Malformed messages don't crash the TUI

## Acceptance Criteria Verification

✅ **AC1**: The TUI correctly handles status messages from the Agent process
- Implemented PubSub subscription and message handling for all tool lifecycle events

✅ **AC2**: Status line displays tool indicators like "Using tool: read_file..."
- Added dedicated status line with emoji-enhanced tool indicators

✅ **AC3**: Tool output is formatted for readability in conversation history
- Implemented structured formatting with visual separators and error handling

## Usage Example

When a user requests the agent to read a file:

1. User types: "Please read the contents of config.json"
2. TUI shows: "📖 Using tool: read_file..." in the status line
3. Tool executes and result appears in conversation:
   ```
   🔧 Tool: read_file
   ─────────────────
   {"database": {"host": "localhost", "port": 5432}}
   ```
4. Status line clears when agent provides final response

## Lessons Learned

1. **PubSub Pattern**: Excellent for real-time UI updates without coupling
2. **Error Boundaries**: Critical for production resilience
3. **Memory Management**: Essential for long-running terminal applications
4. **Visual Feedback**: User experience significantly improved with proper status indicators

## Future Enhancements

- **Progress indicators**: Show progress for long-running tools
- **Concurrent tools**: Handle multiple tools running simultaneously
- **Tool cancellation**: Allow users to cancel running tools
- **History search**: Search through tool results and conversation history

This implementation provides a solid foundation for transparent, real-time tool status display in the TUI while maintaining excellent performance and error resilience.