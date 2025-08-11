# Epic 1 Demo: Core Agent Engine

This demo showcases the foundational capabilities implemented in Epic 1 of The Maestro project. It demonstrates the core agent engine, LLM provider integration, and secure tooling system working together in a runnable example.

## What This Demo Demonstrates

### 🏗️ **Core Architecture**
- **OTP Application**: Fault-tolerant supervision tree with dynamic agent management
- **Agent GenServer**: Stateful conversation management with message history
- **Registry System**: Process discovery and management for multiple agents
- **Error Handling**: Graceful degradation and recovery patterns

### 🤖 **LLM Integration** 
- **Provider Pattern**: Model-agnostic `LLMProvider` behavior with Gemini implementation
- **Authentication**: Multiple auth methods (API Key, OAuth2, Service Account)
- **Conversation Flow**: Complete request-response cycle with context preservation
- **Error Recovery**: Fallback strategies for authentication and API failures

### 🛠️ **Tooling System**
- **Secure File Operations**: Sandboxed file reading with path validation
- **Tool Registry**: Dynamic tool registration and discovery
- **Function Calling**: Integration with LLM provider function calling capabilities
- **Security**: Protection against path traversal and unauthorized access

## Prerequisites

Before running this demo, ensure you have:

### 1. **Elixir Environment**
```bash
# Elixir 1.14+ and Erlang/OTP 25+
elixir --version
```

### 2. **Dependencies Installed**
```bash
# From the project root
mix deps.get
```

### 3. **LLM Authentication** (Choose One)

#### Option A: API Key (Simplest)
```bash
export GEMINI_API_KEY="your-gemini-api-key-here"
```
Get your API key from: https://makersuite.google.com/app/apikey

#### Option B: OAuth2 (Interactive)
```bash
# OAuth will be initiated automatically during demo
# Requires browser access for authorization flow
```

#### Option C: Service Account (Enterprise)
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
```

### 4. **File System Configuration**

The demo needs to access files in the demo directory. Ensure the configuration allows this:

```elixir
# config/dev.exs or config/config.exs
config :the_maestro, :file_system_tool,
  allowed_directories: [
    "/tmp",
    "/Users/your-username/path/to/project/demos",  # Update this path
    Path.join([File.cwd!(), "demos"]),
    Path.join([File.cwd!(), "test", "fixtures"])
  ],
  max_file_size: 10 * 1024 * 1024  # 10MB
```

## Running the Demo

### Quick Start
```bash
# From the project root directory
mix run demos/epic1/demo.exs
```

### Expected Output
```
═══════════════════════════════════════════════════════════════
🤖 The Maestro - Epic 1 Demo: Core Agent Engine
═══════════════════════════════════════════════════════════════

This demo showcases the foundational capabilities of The Maestro:
• OTP application architecture with fault tolerance
• AI Agent with Gemini LLM integration  
• Secure file system operations
• ReAct (Reason and Act) conversational loop

✅ Application started successfully!
🚀 Creating agent with ID: epic1_demo_1691234567
✅ Agent started successfully!

────────────────────────────────────────────────────────────
📋 DEMO SEQUENCE: Testing Core Agent Capabilities
────────────────────────────────────────────────────────────

🔬 TEST 1: Simple LLM Conversation
Sending message: 'Hello! Please introduce yourself briefly.'
✅ LLM Response received!
💬 Agent: Hello! I'm an AI assistant powered by The Maestro system...
   (response truncated for demo display)

🛠️  TEST 2: File Tool Usage
Asking agent to read file: /path/to/demos/epic1/test_file.txt
✅ Tool-assisted response received!
🔧 Agent (with file tool): ✅ **read_file**: Read 247 bytes from file

I can see this is a test file for Epic 1 Demo! The file contains...
   (response truncated for demo display)
🎯 File tool execution appears successful!

📊 FINAL AGENT STATE
──────────────────────────────
Agent ID: epic1_demo_1691234567
Loop State: idle
Message History: 4 messages
LLM Provider: TheMaestro.Providers.Gemini
Auth Status: ✅ Configured
Created At: 2024-01-15 10:30:45.123456Z

✨ Demo completed successfully!
The agent has demonstrated both direct LLM interaction and tool usage.
```

## Configuration Options

### Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `GEMINI_API_KEY` | Direct API key authentication | One of these |
| `GOOGLE_APPLICATION_CREDENTIALS` | Service account path | One of these |
| `GEMINI_OAUTH_CLIENT_ID` | OAuth client ID | For OAuth |
| `GEMINI_OAUTH_CLIENT_SECRET` | OAuth client secret | For OAuth |

### Application Configuration

```elixir
# config/config.exs
config :the_maestro, :file_system_tool,
  allowed_directories: [
    # Add directories where the agent can read files
    "/safe/directory/path",
    Path.join([File.cwd!(), "demos"]),
    Path.join([File.cwd!(), "test"])
  ],
  max_file_size: 10 * 1024 * 1024

# LLM Provider configuration
config :the_maestro, :llm_provider,
  default_provider: TheMaestro.Providers.Gemini,
  gemini: [
    model: "gemini-1.5-pro",
    temperature: 0.7,
    max_tokens: 8192
  ]
```

## Troubleshooting

### Authentication Issues

**Problem**: `Failed to get LLM response: :no_auth_context`
```bash
# Solution: Set up authentication
export GEMINI_API_KEY="your-api-key"
# OR configure OAuth/Service Account
```

**Problem**: `OAuth authorization failed`
```bash
# Solution: Check OAuth configuration
# Ensure you have valid client credentials
# Make sure redirect URLs are configured correctly
```

### File Tool Issues

**Problem**: `Path is not within allowed directories`
```elixir
# Solution: Update config/dev.exs
config :the_maestro, :file_system_tool,
  allowed_directories: [
    Path.join([File.cwd!(), "demos"]),
    # Add other safe directories
  ]
```

**Problem**: `File does not exist`
```bash
# Solution: Check if test file exists
ls -la demos/epic1/test_file.txt
# Re-create if missing
```

### Application Startup Issues

**Problem**: `Application failed to start`
```bash
# Solution: Ensure dependencies are installed
mix deps.get
mix deps.compile

# Check for configuration errors
mix compile --warnings-as-errors
```

## Understanding the Code

### Key Components Demonstrated

1. **Agent Lifecycle**
   ```elixir
   # Agent creation with supervision
   TheMaestro.Agents.start_agent(agent_id, opts)
   
   # Message handling
   TheMaestro.Agents.send_message(agent_id, message)
   ```

2. **LLM Provider Pattern**
   ```elixir
   # Behavior-based abstraction
   defmodule TheMaestro.Providers.Gemini do
     @behaviour TheMaestro.Providers.LLMProvider
     # Implementation details...
   end
   ```

3. **Tool System**
   ```elixir
   # Tool definition and execution
   def execute(%{"path" => path}) do
     with {:ok, validated_path} <- validate_path(path),
          {:ok, content} <- read_file_safely(validated_path) do
       {:ok, %{"content" => content, "path" => validated_path}}
     end
   end
   ```

### Security Highlights

- **Sandboxed File Operations**: All file access is validated against allowed directories
- **Path Traversal Protection**: Prevents `../` attacks and symlink exploitation  
- **Authentication Management**: Secure credential handling with multiple auth strategies
- **Process Isolation**: Each agent runs in its own supervised GenServer

## Next Steps

After running this demo successfully:

1. **Explore the Code**: Review the implementation in `lib/the_maestro/`
2. **Read the Tutorial**: See `tutorials/epic1/story1.6/README.md` for detailed explanations
3. **Try Variations**: Modify the demo to test different scenarios
4. **Check Epic 2**: See the Phoenix LiveView UI implementation

## Related Documentation

- [Story 1.6 Tutorial](../../tutorials/epic1/story1.6/README.md) - Detailed explanation of demo creation
- [Agent Architecture](../../tutorials/epic1/story1.3/README.md) - Understanding GenServer patterns
- [LLM Provider Integration](../../tutorials/epic1/story1.4/README.md) - Authentication and API patterns
- [Tooling System](../../tutorials/epic1/story1.5/README.md) - Security and extensibility patterns

---

**Built with The Maestro** - Demonstrating Elixir/OTP excellence in AI agent architecture.