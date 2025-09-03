# Codex Tool Specifications - Complete Analysis

## Overview
Codex (Claude Code) implements a sophisticated tool system that bridges OpenAI's API with local execution capabilities through MCP (Model Context Protocol) servers and built-in tools. The system supports both OpenAI's Responses API (experimental) and Chat Completions API.

## API Endpoints and Wire Protocols

### 1. Responses API (Primary/Default)
- **Endpoint**: `https://api.openai.com/v1/responses`
- **Headers**:
  ```
  OpenAI-Beta: responses=experimental
  session_id: <UUID>
  Accept: text/event-stream
  originator: codex-cli
  User-Agent: codex/<version> (codex-cli)
  chatgpt-account-id: <account_id> (only for ChatGPT OAuth)
  ```
- **Request Format**: `ResponsesApiRequest` structure
- **Streaming**: SSE (Server-Sent Events)

### 2. Chat Completions API (Fallback)
- **Endpoint**: `https://api.openai.com/v1/chat/completions`
- **Headers**: Standard OpenAI headers
- **Request Format**: Standard chat completions format with tools array
- **Streaming**: SSE with aggregation layer

## Authentication Modes

### 1. API Key Authentication (`AuthMode::ApiKey`)
**File**: `/Users/jasonk/Development/the_maestro/source/codex/codex-rs/core/src/auth.rs`

- Uses `OPENAI_API_KEY` environment variable or config file
- Direct token passed as Bearer token
- Response storage enabled by default
- No account-specific headers

### 2. ChatGPT OAuth Authentication (`AuthMode::ChatGPT`)
**File**: `/Users/jasonk/Development/the_maestro/source/codex/codex-rs/core/src/auth.rs`

- Uses OAuth flow with refresh tokens
- Stores tokens in `auth.json` file
- Auto-refreshes tokens after 28 days
- Adds `chatgpt-account-id` header
- Response storage disabled (uses encrypted reasoning)
- Supports plan type detection (Free/Plus/Pro/Team)

**Key Differences**:
- OAuth includes account context and plan limitations
- OAuth uses encrypted reasoning content when not storing responses
- OAuth has usage limit handling with reset timers
- API Key allows full response storage

## Tool Message Format

### Request Format (Responses API)
```json
{
  "model": "gpt-4",
  "instructions": "System instructions...",
  "input": [
    {
      "type": "message",
      "role": "user",
      "content": [{"type": "input_text", "text": "..."}]
    },
    {
      "type": "function_call",
      "name": "tool_name",
      "arguments": "JSON string",
      "call_id": "unique_id"
    },
    {
      "type": "function_call_output",
      "call_id": "matching_id",
      "output": {
        "content": "result or error",
        "success": true/false
      }
    }
  ],
  "tools": [...],
  "tool_choice": "auto",
  "parallel_tool_calls": false,
  "reasoning": {...},
  "store": true/false,
  "stream": true,
  "include": ["reasoning.encrypted_content"],
  "prompt_cache_key": "session_uuid"
}
```

### Tool Definition Format
```rust
// From openai_tools.rs
pub struct ResponsesApiTool {
    name: String,
    description: String,
    strict: bool,  // For structured outputs
    parameters: JsonSchema,
}

// Tool types
pub enum OpenAiTool {
    Function(ResponsesApiTool),     // Standard function tools
    LocalShell {},                  // Built-in shell execution
    WebSearch {},                   // Web search capability
    Freeform(FreeformTool),        // Custom format tools
}
```

## Built-in Tools

### 1. Shell Execution (`shell` / `local_shell`)
**Path**: `/Users/jasonk/Development/the_maestro/source/codex/codex-rs/core/src/openai_tools.rs:169`
```rust
- Name: "shell"
- Parameters: command[], workdir, timeout_ms
- Returns: stdout/stderr output
- Supports sandboxing via Landlock
```

### 2. Exec Command (Streamable)
**Path**: `/Users/jasonk/Development/the_maestro/source/codex/codex-rs/core/src/exec_command/responses_api.rs`
```rust
- Name: "exec_command"
- Parameters: cmd, yield_time_ms, max_output_tokens, shell, login
- Returns: Streaming output with session management
```

### 3. Write Stdin
**Path**: `/Users/jasonk/Development/the_maestro/source/codex/codex-rs/core/src/exec_command/responses_api.rs:57`
```rust
- Name: "write_stdin"
- Parameters: session_id, chars, yield_time_ms, max_output_tokens
- Returns: Output after writing to stdin
```

### 4. View Image
**Path**: `/Users/jasonk/Development/the_maestro/source/codex/codex-rs/core/src/openai_tools.rs:302`
```rust
- Name: "view_image"
- Parameters: path (local filesystem)
- Returns: Attaches image to conversation via base64 encoding
- Image sent as: {"type": "input_image", "image_url": "data:image/...;base64,..."}
```

### 5. Apply Patch
**Path**: `/Users/jasonk/Development/the_maestro/source/codex/codex-rs/core/src/tool_apply_patch.rs`
```rust
- Name: "apply_patch"
- Two formats: JSON structured or Freeform
- Parameters: input (diff content)
- Returns: Success/failure with file changes
```

### 6. Update Plan
**Path**: `/Users/jasonk/Development/the_maestro/source/codex/codex-rs/core/src/plan_tool.rs`
```rust
- Name: "update_plan"
- Parameters: explanation, plan[]
- Plan items: {step: string, status: pending|in_progress|completed}
- Returns: "Plan updated"
```

## MCP (Model Context Protocol) Tools

### MCP Integration
**Path**: `/Users/jasonk/Development/the_maestro/source/codex/codex-rs/core/src/mcp_connection_manager.rs`

MCP servers provide additional tools that are:
1. Spawned as separate processes
2. Communicate via stdio
3. Registered with fully-qualified names: `<server>__<tool>`
4. Tool names limited to 64 characters (SHA1 hash for longer names)

### MCP Tool Call Flow
**Path**: `/Users/jasonk/Development/the_maestro/source/codex/codex-rs/core/src/mcp_tool_call.rs`
```rust
1. Parse arguments as JSON
2. Create McpInvocation object
3. Send McpToolCallBeginEvent
4. Execute via session.call_tool()
5. Send McpToolCallEndEvent with duration
6. Return ResponseInputItem::McpToolCallOutput
```

### MCP Tool Registration
```rust
// Tool name qualification
const MCP_TOOL_NAME_DELIMITER: &str = "__";
const MAX_TOOL_NAME_LENGTH: usize = 64;

// Example: "mcp_server__tool_name"
// If > 64 chars: truncated + SHA1 hash suffix
```

## Tool Invocation Flow

### 1. Tool Discovery
```rust
// From codex.rs
1. Built-in tools loaded from ToolsConfig
2. MCP servers initialized at session start
3. MCP tools discovered via tools/list request
4. All tools aggregated into single tools array
```

### 2. Tool Execution
```rust
// From codex.rs:handle_function_call()
match tool_name {
    "shell" => handle_shell_call()
    "exec_command" => handle_exec_command()
    "write_stdin" => handle_write_stdin()
    "view_image" => inject_input(LocalImage)
    "apply_patch" => handle_apply_patch()
    "update_plan" => handle_update_plan()
    _ => {
        // Check MCP tools
        if let Some((server, tool)) = parse_mcp_tool_name() {
            handle_mcp_tool_call()
        }
    }
}
```

### 3. Response Format
```rust
pub enum ResponseInputItem {
    FunctionCallOutput {
        call_id: String,
        output: FunctionCallOutputPayload {
            content: String,
            success: Option<bool>,
        }
    },
    McpToolCallOutput {
        call_id: String,
        result: Result<CallToolResult, String>,
    },
    CustomToolCallOutput {
        call_id: String,
        output: String,
    }
}
```

## System Prompt Modifications

The system prompt is dynamically constructed based on:

1. **Base Instructions**: Core behavior guidelines
2. **User Instructions**: Custom user preferences
3. **Model-specific Instructions**: Per-model optimizations
4. **Tool Availability**: Tool descriptions added to prompt
5. **Environment Context**: Working directory, sandbox mode

**Construction in `client_common.rs`**:
```rust
fn get_full_instructions(&self, model_family: &ModelFamily) -> String {
    let mut parts = vec![];
    
    // Base instructions
    if let Some(base) = &self.base_instructions {
        parts.push(base.clone());
    }
    
    // Model-specific
    if let Some(specific) = model_family.instructions {
        parts.push(specific);
    }
    
    // User instructions
    if let Some(user) = &self.user_instructions {
        parts.push(user.clone());
    }
    
    // Tool descriptions (implicit via tools array)
    
    parts.join("\n\n")
}
```

## Special Tool Features

### 1. Image Handling
- Images are read from local filesystem
- Converted to base64 data URLs
- Injected into conversation as `InputImage` content items
- Format: `data:image/[type];base64,[data]`

### 2. Streaming Execution
- `exec_command` maintains session state
- Supports interactive stdin/stdout
- Session management via unique IDs
- Yield time controls output buffering

### 3. Sandboxing
- Landlock support on Linux
- Policy-based file system restrictions
- Approval workflows for dangerous operations
- Environment variable filtering

### 4. Patch Application
- Supports unified diff format
- Freeform XML-based patch format
- File creation/deletion support
- Approval required for destructive changes

## Error Handling

### Tool Errors Return:
```json
{
  "call_id": "...",
  "output": {
    "content": "err: <error_message>",
    "success": false
  }
}
```

### Common Error Types:
- Parse errors (invalid arguments)
- Execution errors (command failed)
- Permission errors (sandbox restrictions)
- Timeout errors (execution limit exceeded)
- MCP communication errors

## Implementation Files Reference

| Component | File Path |
|-----------|-----------|
| Tool Definitions | `/source/codex/codex-rs/core/src/openai_tools.rs` |
| MCP Integration | `/source/codex/codex-rs/core/src/mcp_connection_manager.rs` |
| MCP Tool Calls | `/source/codex/codex-rs/core/src/mcp_tool_call.rs` |
| Tool Execution | `/source/codex/codex-rs/core/src/codex.rs:handle_function_call()` |
| Shell Tools | `/source/codex/codex-rs/core/src/shell.rs` |
| Exec Command | `/source/codex/codex-rs/core/src/exec_command/` |
| Apply Patch | `/source/codex/codex-rs/core/src/tool_apply_patch.rs` |
| Plan Tool | `/source/codex/codex-rs/core/src/plan_tool.rs` |
| Auth System | `/source/codex/codex-rs/core/src/auth.rs` |
| Client Logic | `/source/codex/codex-rs/core/src/client.rs` |
| Protocol Models | `/source/codex/codex-rs/protocol/src/models.rs` |

## Key Insights for Elixir Implementation

1. **Tool Registration**: Tools must be registered with proper JSON schema
2. **Naming Convention**: MCP tools use `server__tool` format with 64-char limit
3. **Response Format**: All tools return standardized success/content structure
4. **Streaming**: Use SSE for real-time output from long-running commands
5. **Authentication**: Handle both API key and OAuth flows differently
6. **Sandboxing**: Implement security boundaries for file system access
7. **Session Management**: Maintain state for interactive tools
8. **Error Handling**: Consistent error format across all tool types
9. **Image Support**: Base64 encoding for local image injection
10. **Plan Tracking**: Structured planning tool for task management

## Tool Response Flow to LLM

When a tool completes execution, the response is:
1. Wrapped in appropriate `ResponseInputItem` type
2. Converted to `ResponseItem` for the conversation
3. Added to the conversation history
4. Sent back to the LLM in the next request's `input` array
5. LLM processes the tool output and continues generation

The key is that tool outputs become part of the conversation history, allowing the LLM to see results and continue reasoning based on them.