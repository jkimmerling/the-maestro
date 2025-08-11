# Story 1.3: Agent State Management & ReAct Loop Stub

## Overview

In this tutorial, we'll explore how to implement stateful GenServer processes for managing AI agent conversations in Elixir. This story builds the foundation for a ReAct (Reason and Act) loop by establishing proper state management and message handling patterns.

## Learning Objectives

By the end of this tutorial, you'll understand:
- How to design state structures for GenServer processes
- Best practices for message handling in OTP applications
- How to implement a placeholder ReAct loop
- Type specifications and documentation patterns in Elixir

## State Structure Design

### The Agent State

The core of our Agent GenServer is its state structure. We define this as a proper struct with clear type specifications:

```elixir
@type t :: %__MODULE__{
  agent_id: String.t(),
  message_history: list(message()),
  loop_state: atom(),
  created_at: DateTime.t()
}

defstruct [:agent_id, :message_history, :loop_state, :created_at]
```

**Key Design Decisions:**

1. **`agent_id`**: Unique identifier allowing multiple agent instances
2. **`message_history`**: Chronological list of conversation messages
3. **`loop_state`**: Track the current phase of the ReAct loop (`:idle`, `:thinking`, `:acting`)
4. **`created_at`**: Timestamp for debugging and analytics

### Message Structure

Messages in our conversation history follow a consistent structure:

```elixir
@type message :: %{
  type: :user | :assistant,
  content: String.t(),
  timestamp: DateTime.t()
}
```

This allows us to maintain a clear conversation thread while preserving metadata.

## GenServer Implementation Patterns

### Client API Design

Our public API follows Elixir conventions with clear function signatures:

```elixir
@spec send_message(String.t(), String.t()) :: {:ok, message()} | {:error, term()}
def send_message(agent_id, message) do
  GenServer.call(via_tuple(agent_id), {:send_message, message})
end
```

**Key Patterns:**
- Type specifications for all public functions
- Error handling with tagged tuples (`{:ok, result}` or `{:error, reason}`)
- Registry-based process naming for multiple agent instances

### Server Callback Patterns

The GenServer callbacks handle state transitions systematically:

```elixir
@impl true
def handle_call({:send_message, message}, _from, state) do
  # 1. Create user message with metadata
  user_message = %{
    type: :user,
    content: message,
    timestamp: DateTime.utc_now()
  }
  
  # 2. Generate response (placeholder for now)
  assistant_response = %{
    type: :assistant,
    content: "I received your message: \"#{message}\". This is a placeholder response.",
    timestamp: DateTime.utc_now()
  }
  
  # 3. Update state immutably
  updated_history = state.message_history ++ [user_message, assistant_response]
  updated_state = %{state | 
    message_history: updated_history,
    loop_state: :idle
  }
  
  # 4. Return response and new state
  {:reply, {:ok, assistant_response}, updated_state}
end
```

## The ReAct Loop Foundation

### Current Implementation

Our placeholder ReAct loop follows this pattern:

1. **Receive**: Accept user input
2. **Reason**: Process the input (placeholder logic)
3. **Act**: Generate a response (hardcoded for now)
4. **Update**: Store conversation state

### Future Extension Points

The current implementation provides hooks for future enhancements:

- **`loop_state`**: Will track `:thinking`, `:acting`, `:tool_use` phases
- **Message history**: Foundation for context-aware responses
- **State management**: Proper OTP patterns for fault tolerance

## Process Management

### Registry-Based Naming

We use a Registry to manage multiple agent instances:

```elixir
defp via_tuple(agent_id) do
  {:via, Registry, {TheMaestro.Agents.Registry, agent_id}}
end
```

This allows:
- Multiple concurrent agent conversations
- Process discovery by agent ID
- Automatic cleanup when processes terminate

### Supervision Integration

The Agent GenServer integrates with OTP supervision trees, providing:
- Automatic restart on crashes
- Isolated failures (one agent crash doesn't affect others)
- Resource management and monitoring

## Testing Patterns

Our tests verify key behaviors:

```elixir
test "send_message updates state correctly" do
  agent_id = "test-agent-#{System.unique_integer()}"
  {:ok, _pid} = DynamicSupervisor.start_child(
    TheMaestro.Agents.DynamicSupervisor,
    {TheMaestro.Agents.Agent, [agent_id: agent_id]}
  )
  
  # Send message and verify response
  {:ok, response} = Agent.send_message(agent_id, "Hello!")
  assert response.type == :assistant
  assert String.contains?(response.content, "Hello!")
  
  # Verify state was updated
  state = Agent.get_state(agent_id)
  assert length(state.message_history) == 2
  assert state.loop_state == :idle
end
```

## Best Practices Demonstrated

1. **Type Specifications**: Every public function has a `@spec`
2. **Documentation**: Comprehensive `@doc` and `@moduledoc` 
3. **Immutable State**: State updates create new state structures
4. **Error Handling**: Consistent return patterns
5. **Process Isolation**: Each conversation is an independent process

## Next Steps

Future stories will extend this foundation to:
- Connect to actual LLM providers
- Implement tool usage capabilities
- Add streaming response handling
- Enhance the ReAct reasoning loop

## Key Takeaways

- GenServer state should be designed as proper structs with type specs
- Message handling patterns should be consistent and predictable
- Process naming strategies enable scalable multi-user systems
- Placeholder implementations provide clear extension points for future features

The Agent GenServer now provides a solid foundation for building sophisticated AI agent interactions while maintaining Elixir's core principles of fault tolerance and concurrent processing.