# Epic 3 Story 3.5: Conversation Checkpointing (Save/Restore)

This tutorial demonstrates how to implement conversation session persistence in an Elixir/Phoenix application using GenServer state serialization and PostgreSQL storage.

## Overview

In this story, we added the ability for users to save their current conversation state and restore it later, enabling persistent conversation sessions across browser sessions and allowing users to manage multiple conversation contexts.

## Key Features Implemented

1. **Database Schema**: PostgreSQL table for storing serialized conversation sessions
2. **State Serialization**: Safe serialization/deserialization of GenServer state
3. **Phoenix Context**: Clean API for session management operations
4. **GenServer Integration**: Session save/restore methods on Agent processes
5. **LiveView UI**: Modal-based interface for session management

## Architecture Overview

### Database Layer

```elixir
# Migration: conversation_sessions table
create table(:conversation_sessions, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :session_name, :string, size: 255
  add :agent_id, :string, null: false
  add :user_id, :string
  add :session_data, :text, null: false  # JSON serialized state
  add :message_count, :integer, default: 0

  timestamps(type: :utc_datetime)
end
```

Key design decisions:
- **Binary UUID**: For session IDs to prevent enumeration
- **Agent ID indexing**: Fast lookups for agent-specific sessions
- **JSON storage**: Flexible serialization format in `session_data` text field
- **Message count**: Quick metadata without deserializing full content

### Schema Module

```elixir
defmodule TheMaestro.Sessions.ConversationSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "conversation_sessions" do
    field :session_name, :string
    field :agent_id, :string
    field :user_id, :string
    field :session_data, :string
    field :message_count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(conversation_session, attrs) do
    conversation_session
    |> cast(attrs, [:session_name, :agent_id, :user_id, :session_data, :message_count])
    |> validate_required([:agent_id, :session_data])
    |> unique_constraint([:agent_id, :session_name])
    |> maybe_generate_session_name()
  end
end
```

## State Serialization Strategy

### Challenge: GenServer State Serialization

Agent state contains complex data types that need careful serialization:

```elixir
%TheMaestro.Agents.Agent{
  agent_id: "user_123",
  message_history: [%{timestamp: %DateTime{}, ...}],  # DateTime structs
  loop_state: :idle,  # Atoms
  created_at: %DateTime{},  # DateTime struct
  llm_provider: TheMaestro.Providers.Gemini,  # Module atoms
  auth_context: %{credentials: %{...}}  # Sensitive data
}
```

### Solution: Safe Serialization Functions

```elixir
defp serialize_agent_state(agent_state) do
  serializable_state = %{
    agent_id: agent_state.agent_id,
    message_history: serialize_message_history(agent_state.message_history),
    loop_state: agent_state.loop_state,
    created_at: DateTime.to_iso8601(agent_state.created_at),  # DateTime → ISO string
    llm_provider: module_to_atom(agent_state.llm_provider),   # Module → string
    auth_context: serialize_auth_context(agent_state.auth_context)  # Sanitized
  }

  Jason.encode!(serializable_state)
end
```

Key techniques:
- **DateTime serialization**: Convert to ISO8601 strings for JSON compatibility
- **Module serialization**: Convert module atoms to strings for storage
- **Auth context sanitization**: Remove sensitive credentials during serialization
- **Message history**: Preserve complete conversation with timestamp conversion

### Deserialization with Error Handling

```elixir
defp deserialize_agent_state(serialized_data) do
  try do
    data = Jason.decode!(serialized_data)
    {:ok, created_at, _} = DateTime.from_iso8601(data["created_at"])
    
    agent_state = %TheMaestro.Agents.Agent{
      agent_id: data["agent_id"],
      message_history: deserialize_message_history(data["message_history"]),
      loop_state: String.to_existing_atom(data["loop_state"]),
      created_at: created_at,
      llm_provider: atom_to_module(data["llm_provider"]),
      auth_context: deserialize_auth_context(data["auth_context"])
    }
    
    {:ok, agent_state}
  rescue
    e in [Jason.DecodeError, ArgumentError, MatchError] ->
      {:error, e}
  end
end
```

## Phoenix Context Layer

### Sessions Context API

```elixir
defmodule TheMaestro.Sessions do
  @doc "Save an agent's current state as a conversation session"
  def save_session(agent_state, session_name \\ nil, user_id \\ nil)

  @doc "Restore an agent session from a saved conversation session"  
  def restore_session(agent_id, session_name)

  @doc "List conversation sessions for a given agent_id"
  def list_sessions_for_agent(agent_id)
end
```

### Save Session Implementation

```elixir
def save_session(agent_state, session_name \\ nil, user_id \\ nil) do
  session_name = session_name || generate_default_session_name()
  serialized_state = serialize_agent_state(agent_state)
  message_count = length(agent_state.message_history)

  attrs = %{
    session_name: session_name,
    agent_id: agent_state.agent_id,
    user_id: user_id,
    session_data: serialized_state,
    message_count: message_count
  }

  # Check if session exists (upsert pattern)
  case get_conversation_session_by_agent_and_name(agent_state.agent_id, session_name) do
    nil -> create_conversation_session(attrs)
    existing_session -> update_conversation_session(existing_session, attrs)
  end
end
```

Key features:
- **Upsert pattern**: Update existing sessions or create new ones
- **Automatic naming**: Generate timestamp-based names if not provided
- **Metadata extraction**: Store message count for quick access

## GenServer Integration

### Agent API Extensions

```elixir
defmodule TheMaestro.Agents.Agent do
  @doc "Saves the current agent session to the database"
  def save_session(agent_id, session_name \\ nil, user_id \\ nil)

  @doc "Restores an agent session from the database"  
  def restore_session(agent_id, session_name)

  @doc "Lists all saved sessions for an agent"
  def list_sessions(agent_id)
end
```

### GenServer Implementation

```elixir
def handle_call({:save_session, session_name, user_id}, _from, state) do
  case TheMaestro.Sessions.save_session(state, session_name, user_id) do
    {:ok, conversation_session} ->
      Logger.info("Session '#{conversation_session.session_name}' saved for agent #{state.agent_id}")
      {:reply, {:ok, conversation_session}, state}
    
    {:error, reason} ->
      {:reply, {:error, reason}, state}
  end
end

def handle_call({:restore_session, session_name}, _from, current_state) do
  case TheMaestro.Sessions.restore_session(current_state.agent_id, session_name) do
    {:ok, restored_state} ->
      # Preserve current LLM provider and auth context
      updated_state = %{
        restored_state
        | llm_provider: current_state.llm_provider,
          auth_context: current_state.auth_context
      }
      
      broadcast_session_restored(current_state.agent_id, session_name)
      {:reply, :ok, updated_state}
    
    {:error, reason} ->
      {:reply, {:error, reason}, current_state}
  end
end
```

Important considerations:
- **State preservation**: Keep current LLM provider and auth context during restore
- **Broadcasting**: Notify UI components about session restore events
- **Error handling**: Graceful failure without crashing the GenServer

## LiveView UI Implementation

### Session Management Modal

The UI provides a modal-based interface for session operations:

```elixir
# Session controls in header
<button phx-click="show_save_session_modal">💾 Save Session</button>
<button phx-click="show_restore_session_modal">📂 Restore Session</button>

# Modal for save/restore operations
<%= if @show_session_modal do %>
  <div class="fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center z-50">
    <!-- Save or restore form based on @session_action -->
  </div>
<% end %>
```

### Event Handlers

```elixir
def handle_event("save_session", %{"session_name" => session_name}, socket) do
  user_id = get_user_id(socket.assigns.current_user)
  
  case TheMaestro.Agents.Agent.save_session(socket.assigns.agent_id, session_name, user_id) do
    {:ok, _conversation_session} ->
      socket = put_flash(socket, :info, "Session '#{session_name}' saved successfully!")
      {:noreply, socket}
    
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Failed to save session: #{inspect(reason)}")}
  end
end
```

### Real-time Updates

```elixir
def handle_info({:session_restored, session_name}, socket) do
  # Refresh conversation history when session is restored
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
```

## Security Considerations

### Data Sanitization

```elixir
defp serialize_auth_context(auth_context) do
  # Only serialize non-sensitive metadata
  Map.take(auth_context, [:type])
end
```

### Access Control

- Sessions are scoped by `agent_id` - users can only access their own sessions
- User ID association for authenticated environments
- No direct session ID exposure in URLs

### Validation

```elixir
def changeset(conversation_session, attrs) do
  conversation_session
  |> validate_required([:agent_id, :session_data])
  |> validate_length(:session_name, min: 1, max: 255)
  |> unique_constraint([:agent_id, :session_name])
end
```

## Testing the Implementation

### Demo Script Highlights

```elixir
# 1. Create conversation with multiple messages
# 2. Save session with metadata
# 3. Modify current state
# 4. Restore original session
# 5. Verify message history integrity

SessionDemo.run()
# Output:
# ✅ Session saved successfully!
# ✅ Session restored successfully!
# ✅ Message history correctly restored!
```

### Key Test Scenarios

1. **Basic save/restore cycle**
2. **Session name uniqueness**
3. **Message history preservation**  
4. **Timestamp accuracy**
5. **Error handling for invalid data**

## Lessons Learned

### Serialization Challenges

- **DateTime handling**: JSON doesn't natively support DateTime objects
- **Module serialization**: Modules need string conversion for storage
- **Sensitive data**: Authentication contexts require careful sanitization

### State Management

- **Partial restoration**: Preserve current provider/auth while restoring history
- **Atomic operations**: Ensure consistent state during restore process
- **Error recovery**: Graceful handling of corrupted session data

### UI/UX Considerations

- **Real-time feedback**: Live updates when sessions are restored
- **Progressive enhancement**: Modal interface with proper fallbacks
- **Error messaging**: Clear feedback for validation errors

## Production Considerations

### Performance

- **Indexing**: Proper database indexes for agent_id and timestamps
- **Pagination**: Limit session lists for users with many saved sessions
- **Compression**: Consider gzipping large session data

### Scaling

- **Database growth**: Monitor and archive old sessions
- **Memory usage**: Large conversation histories impact GenServer memory
- **Concurrent access**: Handle multiple session operations gracefully

### Monitoring

- **Session usage metrics**: Track save/restore frequency
- **Error rates**: Monitor serialization/deserialization failures
- **Storage growth**: Alert on rapid database size increases

## Conclusion

This implementation provides a robust foundation for conversation persistence with:

- ✅ Safe state serialization/deserialization
- ✅ Clean Phoenix Context API
- ✅ Integrated GenServer session management
- ✅ User-friendly LiveView interface
- ✅ Comprehensive error handling
- ✅ Security-conscious design

The conversation checkpointing feature enables users to maintain context across sessions while providing a smooth, real-time user experience through Phoenix LiveView.