# Epic 3 Demos: Advanced Agent Capabilities & Tooling

This directory contains demos showcasing the advanced capabilities implemented in Epic 3.

## Story 3.2: Full File System Tool (Write & List)

**Demo**: `story3.2_demo.exs`

Demonstrates the new file system tools that extend the agent's capabilities beyond just reading files:

### Features Demonstrated

- **write_file tool**: Securely write content to files with automatic directory creation
- **list_directory tool**: List directory contents with rich metadata and sorting
- **Multi-tool workflows**: Using multiple tools together to accomplish complex tasks
- **Security validation**: Path validation and sandboxing across all operations

### Running the Demo

```bash
# Basic demo (tests tools directly)
mix run demos/epic3/story3.2_demo.exs

# Full demo with AI agent (requires API key)
GEMINI_API_KEY=your_key mix run demos/epic3/story3.2_demo.exs
```

### What You'll See

1. **Tool Registration Verification**: Confirms all file system tools are available
2. **Direct Tool Testing**: Tests each tool through the tooling system
3. **Complex Workflows**: Demonstrates nested directory creation and file operations
4. **Agent Integration**: Shows how the AI agent can use the tools (if API key provided)

### Sample Output

```
🚀 Epic 3 Story 3.2 Demo: Full File System Tool (Write & List)
============================================================

📁 Setting up demo environment...
   ✅ Demo directory created: /tmp/epic3_story32_demo
   ✅ File system tool configured for demo directory

🔧 Verifying file system tools are available...
   ✅ read_file tool available
   ✅ write_file tool available
   ✅ list_directory tool available
   ✅ All file system tools are properly registered

🧪 Testing tools directly through the tooling system...
   ✅ All direct tool tests passed!

🤖 Testing tools with AI agent...
   ✅ Tools are properly configured and ready for LLM use

🎉 Demo completed successfully!
```

### Technical Verification

The demo verifies:
- ✅ Tool definitions are in correct JSON format for OpenAI Function Calling
- ✅ All tools execute successfully through the tooling system  
- ✅ Security sandboxing works correctly
- ✅ Agent processes have access to the tools
- ✅ Complex file operations work (nested directories, multiple operations)

This demonstrates that the new file system tools are ready for production use with Gemini and other LLM providers.

## Story 3.5: Conversation Checkpointing (Save/Restore)

**Demo**: `story3.5_demo.exs`

Demonstrates the conversation session persistence functionality that allows users to save and restore their conversation history:

### Features Demonstrated

- **Session Save**: Save complete agent state including message history and metadata
- **Session Restore**: Restore previous conversation state with full message history
- **Session Listing**: View available saved sessions for an agent
- **State Serialization**: Safe serialization/deserialization of complex GenServer state
- **Database Integration**: PostgreSQL storage with proper indexing and constraints

### Running the Demo

```bash
# Run the session checkpointing demo
mix run demos/epic3/story3.5_demo.exs
```

### What You'll See

1. **Agent Creation**: Creates a test agent with unique ID
2. **Conversation Simulation**: Exchanges several messages to build conversation history
3. **Session Save**: Saves the current conversation state to the database
4. **Session Listing**: Shows all saved sessions for the agent
5. **State Modification**: Adds new messages to change current state
6. **Session Restore**: Restores the original saved conversation
7. **Verification**: Confirms message history integrity after restore

### Sample Output

```
🎯 Epic 3 Story 3.5 Demo: Conversation Checkpointing
======================================================

🤖 Creating agent with ID: demo_agent_1755082132017
✅ Agent created successfully

💬 Starting demonstration conversation...
👤 User: Hello, this is my first message
🤖 Agent: I received your message: "Hello, this is my first message". This is a test response.
[... more messages ...]

📊 Current conversation has 6 messages

💾 Testing session save functionality...
✅ Session 'demo_session_1755082134316' saved successfully!
   - Session ID: 76048c83-dbe2-4cd6-bbe2-8678aadeb5c3
   - Message count: 6
   - Created at: 2025-08-13 10:48:54Z

📋 Testing session listing...
✅ Found 1 saved sessions for agent
   - demo_session_1755082134316 (6 messages)

🔄 Testing session restore functionality...
📊 Current state has 8 messages
✅ Session restored successfully!
   - Original messages: 6
   - Before restore: 8
   - After restore: 6
✅ Message history correctly restored!

🔍 Verifying restored conversation content...
📝 Restored message history:
   1. 👤 Hello, this is my first message...
   2. 🤖 I received your message: "Hello, this is my first message"...
   [... all original messages preserved ...]

✅ Demo completed successfully!
🎉 Conversation checkpointing is working correctly!
```

### Technical Verification

The demo verifies:
- ✅ Safe serialization/deserialization of GenServer state
- ✅ Database storage with proper schema and constraints
- ✅ Complete message history preservation including timestamps
- ✅ Session metadata accuracy (message counts, timestamps)
- ✅ State restoration without data loss
- ✅ Error handling for edge cases

### Web Interface Demo

After running the script demo, you can also test the web interface:

```bash
# Start the Phoenix server
mix phx.server

# Visit http://localhost:4000/agent
# 1. Send some messages to create conversation history
# 2. Click "💾 Save Session" and enter a session name
# 3. Send more messages to change the current state
# 4. Click "📂 Restore Session" and select your saved session
# 5. Observe the conversation history return to the saved state
```

This demonstrates that conversation checkpointing provides a complete user experience from programmatic API to web interface.