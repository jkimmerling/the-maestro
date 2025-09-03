Tool Call Matrix (Codex Translators)

Purpose

- Show concrete, provider-specific tool interactions so we can build a translation layer from generic tools to each provider’s on-wire format.
- Providers covered: Anthropic (Messages API), OpenAI Responses API, OpenAI Chat Completions API, Gemini (functionDeclarations + functionCall/functionResponse).
- Scenarios: shell, read_file, read_many_files.

Legend

- Tool declaration: How tools are sent to the provider.
- Assistant tool call: How a model asks to invoke a tool.
- Tool result injection: How we append the tool’s result back into history for the next turn.
- Final assistant: Optional final assistant text after tool result.

Notes

- These are minimal, illustrative shapes based on the repo specs. Omit unrelated fields for clarity. Field names and containers (messages vs contents vs input) differ by provider and must be respected exactly.

Scenario: shell (run_shell_command)

Anthropic (Messages API)

- Tool declaration

```json
{
  "tools": [
    {
      "name": "run_shell_command",
      "description": "Execute a shell command",
      "input_schema": {
        "type": "object",
        "properties": {
          "command": { "type": "string" },
          "directory": { "type": "string" },
          "description": { "type": "string" }
        },
        "required": ["command"]
      }
    }
  ]
}
```

Do/Don't Checklists

Anthropic (Messages API)

- Do: Use `tools: [{ name, input_schema }]` with correct parameter names (e.g., `read_file.absolute_path`).
- Do: Insert tool results as a new user message with `{ type: "tool_result", tool_use_id }`.
- Do: Keep IDs consistent: `tool_result.tool_use_id` must match the prior `tool_use.id`.
- Do: Put global instructions in the `system` field when applicable.
- Do: Treat `tool_result.content` as text only; summarize binary outputs.
- Don't: Send tool outputs as assistant text or mix into the same assistant message as `tool_use`.
- Don't: Use `file_path` for `read_file` (use `absolute_path`).
- Don't: Send Chat/Responses-style `tool` role messages; Anthropic uses `tool_result` content blocks.

OpenAI Responses API

- Do: Send tool calls as `input[]` items `{ type: "function_call", call_id, name, arguments }` (arguments JSON string).
- Do: Send tool results as `input[]` items `{ type: "function_call_output", call_id, output }`.
- Do: Include function tools in `tools[]`; include supported non-function tools like `{ type: "local_shell" }`, `{ type: "web_search" }` when enabled.
- Do: Use the `instructions` string for system-like guidance.
- Don't: Send tool outputs as Chat-style `tool` role messages.
- Don't: Embed binary content in outputs; summarize instead.
- Don't: Put tools under Chat’s `{ type: "function", function: {...} }` shape only—Responses supports broader tool types.

OpenAI Chat Completions API

- Do: Provide tools as `[{ type: "function", function: { name, parameters } }]`.
- Do: Emit tool calls inside an assistant message’s `tool_calls[]` array; send results as a `tool` role message with `tool_call_id`.
- Do: Pass arguments as a JSON string in `function.arguments`.
- Do: Prepend system content as `{ role: "system", content: "..." }` in `messages[]`.
- Don't: Use `input[]` or Responses event/item types.
- Don't: Include non-function tools in `tools[]`.
- Don't: Return binary payloads in the tool role message; summarize or use a dedicated mechanism/tool.

Gemini

- Do: Expose tools via `config.tools: [{ functionDeclarations: [...] }]` with `parametersJsonSchema`.
- Do: Handle model tool calls from `parts[]` where a part contains `functionCall`.
- Do: Inject tool results as a new user message with a `functionResponse` part (ID must match the `functionCall.id`).
- Do: Include `inlineData` (base64) next to the `functionResponse` for binary outputs.
- Do: Put system instructions in `config.systemInstruction`.
- Don't: Send `functionResponse` in model parts; results always come from the user side.
- Don't: Use Chat/Responses containers (`messages[]`/`input[]`); Gemini uses `contents[]` with parts.
- Don't: Rename parameters incorrectly (e.g., `read_file` expects `absolute_path`; `write_file` expects `file_path`).

Web Search and Web Fetch

web_search

| Provider | Availability | Declaration | Call Shape | Result Handling |
|---|---|---|---|---|
| Anthropic | Not native in this spec | N/A | N/A | Use a function tool like `google_web_search` instead |
| OpenAI Responses | Supported as non-function tool | Include `{ type: "web_search" }` in `tools[]` (no parameters) | Model emits non-function tool call in Responses stream; handled client-side | Client emits UI events (WebSearchBegin/End); no `function_call_output` is sent back to model |
| OpenAI Chat | Not in tools array | Omitted (Chat supports function tools only) | N/A | Use a function tool wrapper if needed |
| Gemini | Supported via function tools | `google_web_search` as a function declaration | Model calls `functionCall` with `{ query }` | Return text in `functionResponse.response.output`; include citations if available |

web_fetch (URL content retrieval)

| Provider | Availability | Declaration | Call Shape | Result Handling |
|---|---|---|---|---|
| Anthropic | Via custom function tool | Add `web_fetch` with `{ prompt: string }` | Assistant `tool_use` | Return summary text in `tool_result` |
| OpenAI Responses | Via custom function tool | Add `web_fetch` function tool | `function_call` → `function_call_output` | Return summary text; no binary |
| OpenAI Chat | Via custom function tool | Add `web_fetch` function tool | Assistant `tool_calls[]` → tool role message | Return summary text |
| Gemini | Native URL tooling path preferred | CLI may use `{ tools: [{ urlContext: {} }] }` under the hood; exposed as `web_fetch` function | Model `functionCall` | `functionResponse` output; can include Sources if available |

MCP Tool Mapping Notes

- Exposure:
  - MCP tools are exposed to models as standard function tools with sanitized names.
  - Name format may be fully qualified: `serverName__toolName` (invalid chars replaced with `_`, length <= 63 or compacted with a hash suffix).

- Provider inclusion:
  - Anthropic: Add to `tools[]` as `{ name, description, input_schema }` using the sanitized name.
  - OpenAI Responses: Add to `tools[]` as `{ type: "function", name, parameters }`.
  - OpenAI Chat: Add to `tools[]` as `{ type: "function", function: { name, parameters } }`.
  - Gemini: Add to `functionDeclarations` as `{ name, parametersJsonSchema }`.

- Call/Result flow: identical to regular function tools per provider. The ID mapping rules in the Identifier Mapping table apply unchanged.


Scenario: read_file

Anthropic (Messages API)

- Tool declaration: same tools array as shell, with read_file tool using `input_schema` where the primary parameter is `absolute_path`.

- Assistant tool call

```json
{
  "role": "assistant",
  "content": [
    {
      "type": "tool_use",
      "id": "rf_1",
      "name": "read_file",
      "input": { "absolute_path": "/abs/path/README.md" }
    }
  ]
}
```

- Tool result injection

```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "rf_1",
      "content": "# README\n...file contents..."
    }
  ]
}
```

OpenAI Responses API

- Assistant tool call and result (input items)

```json
[
  { "role": "user", "content": "Open README" },
  {
    "type": "function_call",
    "call_id": "rf_1",
    "name": "read_file",
    "arguments": "{\"absolute_path\":\"/abs/path/README.md\"}"
  },
  {
    "type": "function_call_output",
    "call_id": "rf_1",
    "output": "# README\n...file contents..."
  }
]
```

OpenAI Chat Completions API

- Assistant tool call and tool result message

```json
{
  "role": "assistant",
  "content": null,
  "tool_calls": [
    {
      "id": "rf_1",
      "type": "function",
      "function": { "name": "read_file", "arguments": "{\"absolute_path\":\"/abs/path/README.md\"}" }
    }
  ]
}
```

```json
{ "role": "tool", "tool_call_id": "rf_1", "content": "# README\n...file contents..." }
```

Gemini (functionDeclarations + functionCall/functionResponse)

- Assistant tool call and functionResponse

```json
{
  "role": "model",
  "parts": [
    { "functionCall": { "id": "rf_1", "name": "read_file", "args": { "absolute_path": "/abs/path/README.md" } } }
  ]
}
```

Binary Return Examples (read_file on an image)

- Anthropic (Messages API)
  - Tool result content is text-only. For images read via `read_file`, return a short text summary (e.g., "Binary content of type image/png was processed.") in the `tool_result.content`. Do not embed binary in `tool_result`.

- OpenAI Responses API
  - Tool outputs are strings in `function_call_output.output`. Summarize binary content (e.g., "Binary content of type image/png was processed."). No binary payload is included in this output item.

- OpenAI Chat Completions API
  - Tool outputs are strings in the tool role message `content`. Summarize binary content as text. To attach an actual image for the model, use a dedicated mechanism/tool (e.g., a `view_image` function) in a separate turn; do not attempt to embed binary in the tool role message.

- Gemini
  - Preferred: Return a `functionResponse` part with an adjacent `inlineData` part containing the base64 bytes. Example:

```json
{
  "role": "user",
  "parts": [
    {
      "functionResponse": {
        "id": "rf_img_1",
        "name": "read_file",
        "response": { "output": "Binary content of type image/png was processed." }
      }
    },
    {
      "inlineData": { "mimeType": "image/png", "data": "<base64>" }
    }
  ]
}
```

Consistency Summary

- Anthropic: tool_use/tool_result blocks in messages.content; tool results go back as a user message with a tool_result referencing the tool_use id.
- OpenAI Responses: function_call/function_call_output items inside `input` array; output is a sibling item keyed by the same call_id.
- OpenAI Chat: assistant tool_calls followed by a tool role message with tool_call_id; then the assistant continues.
- Gemini: model parts include functionCall; tool results are injected as a user part with functionResponse (and optional inlineData for binaries).

Translation Checklist

- Normalize schema once, map fields:
  - Anthropic → `input_schema`
  - OpenAI Responses → function tool object (name, parameters)
  - OpenAI Chat → `{ type: "function", function: { name, parameters } }`
  - Gemini → `functionDeclarations[].parametersJsonSchema`
- Return-path IDs:
  - Anthropic `tool_use_id`, OpenAI Responses `call_id`, OpenAI Chat `tool_call_id`, Gemini functionResponse.id
- Binary returns:
  - Prefer text summary for Anthropic/Responses/Chat; Gemini can attach `inlineData` alongside functionResponse.

Streaming Snippets (Tool Calls)

Anthropic (Messages API)

```text
event: content_block_start
data: {"type":"content_block_start","content_block":{"type":"tool_use","id":"call_123","name":"run_shell_command"}}

event: content_block_delta
data: {"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"command\":\"ls -la\"}"}}

event: content_block_stop
data: {"type":"content_block_stop"}
```

OpenAI Responses API

```text
data: {"type":"response.output_item.added","sequence_number":1,"output_index":0,"item":{"id":"fc_1","type":"function_call","status":"in_progress","arguments":"","call_id":"call_123","name":"run_shell_command"}}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","sequence_number":2,"item_id":"fc_1","output_index":0,"delta":"{\\"command\\":"}\n"}
data: {"type":"response.function_call_arguments.delta","sequence_number":3,"item_id":"fc_1","output_index":0,"delta":"\\"ls -la\\"}"}

data: {"type":"response.output_item.done","sequence_number":4,"output_index":0,"item":{"id":"fc_1","type":"function_call","status":"completed","arguments":"{\\"command\\":\\"ls -la\\"}","call_id":"call_123","name":"run_shell_command"}}
```

OpenAI Chat Completions API

```json
// SSE chunk (choices[0].delta)
{ "choices": [ { "delta": { "tool_calls": [ { "index": 0, "function": { "name": "run_shell_command" } } ] } } ] }
{ "choices": [ { "delta": { "tool_calls": [ { "index": 0, "function": { "arguments": "{\"command\":\"ls -la\"}" } } ] } } ] }
{ "choices": [ { "delta": { }, "finish_reason": "tool_calls" } ] }
```

Gemini (functionCall)

```json
// Streamed candidate part (simplified)
{ "candidates": [ { "content": { "role": "model", "parts": [ { "functionCall": { "id": "fc1", "name": "run_shell_command", "args": { "command": "ls -la" } } } ] } } ] }
```

Per-Scenario Comparison Tables

Shell (run_shell_command)

| Provider | Declaration | Assistant Tool Call | Tool Result Injection |
|---|---|---|---|
| Anthropic | `tools: [{ name, input_schema }]` | Assistant `content[]` includes `{ type: "tool_use", id, name, input }` | New user message with `{ type: "tool_result", tool_use_id, content }` |
| OpenAI Responses | `tools: [{ type: "function", name, parameters }]` | `input[]` item `{ type: "function_call", call_id, name, arguments }` | `input[]` sibling `{ type: "function_call_output", call_id, output }` |
| OpenAI Chat | `tools: [{ type: "function", function: { name, parameters } }]` | Assistant message `{ tool_calls: [{ id, type: "function", function: { name, arguments } }] }` | Tool role message `{ role: "tool", tool_call_id, content }` |
| Gemini | `config.tools: [{ functionDeclarations: [ { name, parametersJsonSchema } ] }]` | Model `parts[]` includes `{ functionCall: { id, name, args } }` | New user parts with `{ functionResponse: { id, name, response: { output } } }` (plus optional `inlineData`) |

read_file

| Provider | Declaration | Assistant Tool Call | Tool Result Injection |
|---|---|---|---|
| Anthropic | `read_file` in `tools[]` with `input_schema` (`absolute_path`, `offset?`, `limit?`) | Assistant `content[]` `tool_use` with args | New user `tool_result` (content: file text or truncated summary) |
| OpenAI Responses | `function` tool with `parameters` | `input[]` `function_call` with JSON `arguments` | `input[]` `function_call_output` with file text summary |
| OpenAI Chat | Function tool in `tools[]` | Assistant `tool_calls[]` with arguments JSON string | Tool role message with file text summary |
| Gemini | `functionDeclarations[]` (`parametersJsonSchema`) | Model `parts[]` functionCall with args | New user `functionResponse` part; can include `inlineData` for binary |

read_many_files

| Provider | Declaration | Assistant Tool Call | Tool Result Injection |
|---|---|---|---|
| Anthropic | `read_many_files` in `tools[]` | Assistant `tool_use` with `{ paths: string[] }` (and optional filters) | New user `tool_result` with concatenated content separated by `--- path ---` |
| OpenAI Responses | Function tool with schema for `paths` | `input[]` `function_call` with arguments JSON | `input[]` `function_call_output` concatenated content |
| OpenAI Chat | Function tool | Assistant `tool_calls[]` with arguments | Tool role message with concatenated content |
| Gemini | `functionDeclarations[]` | Model `functionCall` | New user `functionResponse` part with concatenated content; can include additional parts if needed |

write_file

| Provider | Declaration | Assistant Tool Call | Tool Result Injection |
|---|---|---|---|
| Anthropic | `write_file` with `file_path` and `content` in `input_schema` | Assistant `tool_use` with args | New user `tool_result` with status string (e.g., bytes written) |
| OpenAI Responses | Function tool | `input[]` `function_call` | `input[]` `function_call_output` with status string |
| OpenAI Chat | Function tool | Assistant `tool_calls[]` | Tool role message with status string |
| Gemini | `functionDeclarations[]` | Model `functionCall` | New user `functionResponse` with status string |

replace (edit)

| Provider | Declaration | Assistant Tool Call | Tool Result Injection |
|---|---|---|---|
| Anthropic | `replace` with `file_path`, `old_string`, `new_string`, `expected_replacements?` | Assistant `tool_use` with args | New user `tool_result` summarizing replacements |
| OpenAI Responses | Function tool | `input[]` `function_call` with arguments | `input[]` `function_call_output` summary |
| OpenAI Chat | Function tool | Assistant `tool_calls[]` | Tool role message with summary |
| Gemini | `functionDeclarations[]` | Model `functionCall` | New user `functionResponse` with summary |

grep (search_file_content)

| Provider | Declaration | Assistant Tool Call | Tool Result Injection |
|---|---|---|---|
| Anthropic | `search_file_content` with `pattern` (regex), `path?`, `include?`, `max_matches?` | Assistant `tool_use` with args | New user `tool_result` with file:line:match lines |
| OpenAI Responses | Function tool | `input[]` `function_call` with arguments | `input[]` `function_call_output` with grouped matches |
| OpenAI Chat | Function tool | Assistant `tool_calls[]` with arguments | Tool role message with matches |
| Gemini | `functionDeclarations[]` | Model `functionCall` | New user `functionResponse` with matches |

Identifier Mapping (IDs that tie request → tool result)

| Provider                  | Tool call ID field | Tool result reference field | Where result is placed            |
|---------------------------|--------------------|-----------------------------|-----------------------------------|
| Anthropic (Messages API)  | `id` on `tool_use` | `tool_use_id`               | New user message `tool_result`    |
| OpenAI Responses API      | `call_id`          | `call_id`                    | `input[]` as `function_call_output` |
| OpenAI Chat Completions   | `tool_calls[].id`  | `tool_call_id`              | `messages[]` tool role message    |
| Gemini                    | `functionCall.id`  | `functionResponse.id`       | New user `parts[]` functionResponse |

```json
{
  "role": "user",
  "parts": [
    {
      "functionResponse": {
        "id": "rf_1",
        "name": "read_file",
        "response": { "output": "# README\n...file contents..." }
      }
    }
  ]
}
```

At-a-Glance: Provider Fields

| Provider | System/Instructions | Message Container | Tools Field Key |
|---|---|---|---|
| Anthropic (Messages API) | `system` (string) | `messages[]` | `tools` with `{ name, input_schema }` |
| OpenAI Responses API | `instructions` (string) | `input[]` (ResponseItem array) | `tools` (function tools; plus non-function entries like `{ type: "local_shell" }`, `{ type: "web_search" }`) |
| OpenAI Chat Completions | Prepend `{ role: "system" }` to `messages[]` | `messages[]` | `tools` with `{ type: "function", function: { name, parameters } }` |
| Gemini | `config.systemInstruction` (string or Content) | `contents[]` | `config.tools: [{ functionDeclarations: FunctionDeclaration[] }]` |

Identifiers & Result Injection by Scenario (Compact)

Note: Identifier wiring is identical across scenarios per provider. Shown per scenario for quick scanning.

| Provider | Shell | Read File | Read Many | Write File | Replace | Grep |
|---|---|---|---|---|---|---|
| Anthropic | `tool_use.id → user.tool_result.tool_use_id` | Same as Shell | Same as Shell | Same as Shell | Same as Shell | Same as Shell |
| OpenAI Responses | `function_call.call_id → function_call_output.call_id (input[])` | Same as Shell | Same as Shell | Same as Shell | Same as Shell | Same as Shell |
| OpenAI Chat | `assistant.tool_calls[].id → tool.role.tool_call_id (messages[])` | Same as Shell | Same as Shell | Same as Shell | Same as Shell | Same as Shell |
| Gemini | `functionCall.id → user.parts.functionResponse.id (parts[])` | Same as Shell | Same as Shell | Same as Shell | Same as Shell | Same as Shell |

Scenario: read_many_files

Anthropic (Messages API)

- Assistant tool call

```json
{
  "role": "assistant",
  "content": [
    {
      "type": "tool_use",
      "id": "rmf_1",
      "name": "read_many_files",
      "input": { "paths": ["/abs/path/a.txt", "/abs/path/b.txt"] }
    }
  ]
}
```

Scenario: write_file

Anthropic (Messages API)

- Tool declaration uses `input_schema` with `file_path` and `content`.

- Assistant tool call

```json
{
  "role": "assistant",
  "content": [
    {
      "type": "tool_use",
      "id": "wf_1",
      "name": "write_file",
      "input": { "file_path": "/abs/path/NEW.txt", "content": "hello" }
    }
  ]
}
```

Scenario: replace (edit)

Anthropic (Messages API)

- Tool declaration uses `input_schema` with `file_path`, `old_string`, `new_string`, and optional `expected_replacements`.

- Assistant tool call

```json
{
  "role": "assistant",
  "content": [
    {
      "type": "tool_use",
      "id": "rep_1",
      "name": "replace",
      "input": {
        "file_path": "/abs/path/app.ts",
        "old_string": "const a = 1;",
        "new_string": "const a = 2;",
        "expected_replacements": 1
      }
    }
  ]
}
```

Scenario: grep (search_file_content)

Anthropic (Messages API)

- Tool declaration: `search_file_content` with `input_schema` containing `pattern` (regex string), optional `path` (dir), optional `include` (glob), optional `max_matches`.

- Assistant tool call

```json
{
  "role": "assistant",
  "content": [
    {
      "type": "tool_use",
      "id": "grep_1",
      "name": "search_file_content",
      "input": { "pattern": "TODO", "path": "/abs/project", "include": "**/*.ts" }
    }
  ]
}
```

- Tool result injection

```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "grep_1",
      "content": "/abs/project/a.ts:10: // TODO: refactor\n/abs/project/b.ts:42: // TODO: add tests"
    }
  ]
}
```

OpenAI Responses API

```json
[
  { "role": "user", "content": "Find TODOs" },
  {
    "type": "function_call",
    "call_id": "grep_1",
    "name": "search_file_content",
    "arguments": "{\"pattern\":\"TODO\",\"path\":\"/abs/project\",\"include\":\"**/*.ts\"}"
  },
  {
    "type": "function_call_output",
    "call_id": "grep_1",
    "output": "/abs/project/a.ts:10: // TODO: refactor\n/abs/project/b.ts:42: // TODO: add tests"
  }
]
```

OpenAI Chat Completions API

```json
{
  "role": "assistant",
  "content": null,
  "tool_calls": [
    {
      "id": "grep_1",
      "type": "function",
      "function": {
        "name": "search_file_content",
        "arguments": "{\"pattern\":\"TODO\",\"path\":\"/abs/project\",\"include\":\"**/*.ts\"}"
      }
    }
  ]
}
```

```json
{ "role": "tool", "tool_call_id": "grep_1", "content": "/abs/project/a.ts:10: // TODO: refactor\n/abs/project/b.ts:42: // TODO: add tests" }
```

Gemini (functionDeclarations + functionCall/functionResponse)

```json
{
  "role": "model",
  "parts": [
    {
      "functionCall": {
        "id": "grep_1",
        "name": "search_file_content",
        "args": { "pattern": "TODO", "path": "/abs/project", "include": "**/*.ts" }
      }
    }
  ]
}
```

```json
{
  "role": "user",
  "parts": [
    {
      "functionResponse": {
        "id": "grep_1",
        "name": "search_file_content",
        "response": {
          "output": "/abs/project/a.ts:10: // TODO: refactor\n/abs/project/b.ts:42: // TODO: add tests"
        }
      }
    }
  ]
}
```

- Tool result injection

```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "rep_1",
      "content": "Updated /abs/path/app.ts: 1 replacement"
    }
  ]
}
```

OpenAI Responses API

```json
[
  { "role": "user", "content": "Edit app.ts" },
  {
    "type": "function_call",
    "call_id": "rep_1",
    "name": "replace",
    "arguments": "{\"file_path\":\"/abs/path/app.ts\",\"old_string\":\"const a = 1;\",\"new_string\":\"const a = 2;\",\"expected_replacements\":1}"
  },
  {
    "type": "function_call_output",
    "call_id": "rep_1",
    "output": "Updated /abs/path/app.ts: 1 replacement"
  }
]
```

OpenAI Chat Completions API

```json
{
  "role": "assistant",
  "content": null,
  "tool_calls": [
    {
      "id": "rep_1",
      "type": "function",
      "function": {
        "name": "replace",
        "arguments": "{\"file_path\":\"/abs/path/app.ts\",\"old_string\":\"const a = 1;\",\"new_string\":\"const a = 2;\",\"expected_replacements\":1}"
      }
    }
  ]
}
```

```json
{ "role": "tool", "tool_call_id": "rep_1", "content": "Updated /abs/path/app.ts: 1 replacement" }
```

Gemini (functionDeclarations + functionCall/functionResponse)

```json
{
  "role": "model",
  "parts": [
    {
      "functionCall": {
        "id": "rep_1",
        "name": "replace",
        "args": {
          "file_path": "/abs/path/app.ts",
          "old_string": "const a = 1;",
          "new_string": "const a = 2;",
          "expected_replacements": 1
        }
      }
    }
  ]
}
```

```json
{
  "role": "user",
  "parts": [
    {
      "functionResponse": {
        "id": "rep_1",
        "name": "replace",
        "response": { "output": "Updated /abs/path/app.ts: 1 replacement" }
      }
    }
  ]
}
```

- Tool result injection

```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "wf_1",
      "content": "Wrote 5 bytes to /abs/path/NEW.txt"
    }
  ]
}
```

OpenAI Responses API

```json
[
  { "role": "user", "content": "Create NEW.txt" },
  {
    "type": "function_call",
    "call_id": "wf_1",
    "name": "write_file",
    "arguments": "{\"file_path\":\"/abs/path/NEW.txt\",\"content\":\"hello\"}"
  },
  {
    "type": "function_call_output",
    "call_id": "wf_1",
    "output": "Wrote 5 bytes to /abs/path/NEW.txt"
  }
]
```

OpenAI Chat Completions API

```json
{
  "role": "assistant",
  "content": null,
  "tool_calls": [
    {
      "id": "wf_1",
      "type": "function",
      "function": { "name": "write_file", "arguments": "{\"file_path\":\"/abs/path/NEW.txt\",\"content\":\"hello\"}" }
    }
  ]
}
```

```json
{ "role": "tool", "tool_call_id": "wf_1", "content": "Wrote 5 bytes to /abs/path/NEW.txt" }
```

Gemini (functionDeclarations + functionCall/functionResponse)

```json
{
  "role": "model",
  "parts": [
    { "functionCall": { "id": "wf_1", "name": "write_file", "args": { "file_path": "/abs/path/NEW.txt", "content": "hello" } } }
  ]
}
```

```json
{
  "role": "user",
  "parts": [
    {
      "functionResponse": {
        "id": "wf_1",
        "name": "write_file",
        "response": { "output": "Wrote 5 bytes to /abs/path/NEW.txt" }
      }
    }
  ]
}
```

- Tool result injection (concatenated with separators)

```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "rmf_1",
      "content": "--- /abs/path/a.txt ---\n...a...\n--- /abs/path/b.txt ---\n...b..."
    }
  ]
}
```

OpenAI Responses API

```json
[
  { "role": "user", "content": "Read two files" },
  {
    "type": "function_call",
    "call_id": "rmf_1",
    "name": "read_many_files",
    "arguments": "{\"paths\":[\"/abs/path/a.txt\",\"/abs/path/b.txt\"]}"
  },
  {
    "type": "function_call_output",
    "call_id": "rmf_1",
    "output": "--- /abs/path/a.txt ---\n...a...\n--- /abs/path/b.txt ---\n...b..."
  }
]
```

OpenAI Chat Completions API

```json
{
  "role": "assistant",
  "content": null,
  "tool_calls": [
    {
      "id": "rmf_1",
      "type": "function",
      "function": { "name": "read_many_files", "arguments": "{\"paths\":[\"/abs/path/a.txt\",\"/abs/path/b.txt\"]}" }
    }
  ]
}
```

```json
{ "role": "tool", "tool_call_id": "rmf_1", "content": "--- /abs/path/a.txt ---\n...a...\n--- /abs/path/b.txt ---\n...b..." }
```

Gemini (functionDeclarations + functionCall/functionResponse)

```json
{
  "role": "model",
  "parts": [
    { "functionCall": { "id": "rmf_1", "name": "read_many_files", "args": { "paths": ["/abs/path/a.txt", "/abs/path/b.txt"] } } }
  ]
}
```

```json
{
  "role": "user",
  "parts": [
    {
      "functionResponse": {
        "id": "rmf_1",
        "name": "read_many_files",
        "response": { "output": "--- /abs/path/a.txt ---\n...a...\n--- /abs/path/b.txt ---\n...b..." }
      }
    }
  ]
}
```

- Assistant tool call (non-streaming example inside assistant content)

```json
{
  "role": "assistant",
  "content": [
    { "type": "text", "text": "Working on it..." },
    {
      "type": "tool_use",
      "id": "call_123",
      "name": "run_shell_command",
      "input": { "command": "ls -la" }
    }
  ]
}
```

- Tool result injection (append as a new user message)

```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "call_123",
      "content": "Command: ls -la\nDirectory: (root)\nOutput: ...\nError: (none)\nExit Code: 0"
    }
  ]
}
```

- Final assistant (typical)

```json
{ "role": "assistant", "content": [{ "type": "text", "text": "Listed files successfully." }] }
```

OpenAI Responses API

- Tool declaration

```json
{
  "tools": [
    {
      "type": "function",
      "name": "run_shell_command",
      "description": "Execute a shell command",
      "parameters": {
        "type": "object",
        "properties": {
          "command": { "type": "string" },
          "directory": { "type": "string" },
          "description": { "type": "string" }
        },
        "required": ["command"]
      },
      "strict": null
    }
  ]
}
```

- Assistant tool call and tool result (Responses input items)

```json
[
  { "role": "user", "content": "List files" },
  {
    "type": "function_call",
    "call_id": "call_123",
    "name": "run_shell_command",
    "arguments": "{\"command\":\"ls -la\"}"
  },
  {
    "type": "function_call_output",
    "call_id": "call_123",
    "output": "Command: ls -la\nDirectory: (root)\nOutput: ...\nError: (none)\nExit Code: 0"
  }
]
```

- Final assistant is produced by the provider after the function_call_output is included in the next request’s `input`.

OpenAI Chat Completions API

- Tool declaration

```json
{
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "run_shell_command",
        "description": "Execute a shell command",
        "parameters": {
          "type": "object",
          "properties": {
            "command": { "type": "string" },
            "directory": { "type": "string" },
            "description": { "type": "string" }
          },
          "required": ["command"]
        }
      }
    }
  ]
}
```

- Assistant tool call (assistant message with tool_calls)

```json
{
  "role": "assistant",
  "content": null,
  "tool_calls": [
    {
      "id": "call_123",
      "type": "function",
      "function": { "name": "run_shell_command", "arguments": "{\"command\":\"ls -la\"}" }
    }
  ]
}
```

- Tool result injection (tool role message)

```json
{ "role": "tool", "tool_call_id": "call_123", "content": "Command: ls -la\nDirectory: (root)\nOutput: ...\nError: (none)\nExit Code: 0" }
```

- Final assistant message follows with normal text.

Gemini (functionDeclarations + functionCall/functionResponse)

- Tool declaration

```json
{
  "config": {
    "tools": [
      {
        "functionDeclarations": [
          {
            "name": "run_shell_command",
            "description": "Execute a shell command",
            "parametersJsonSchema": {
              "type": "object",
              "properties": {
                "command": { "type": "string" },
                "directory": { "type": "string" },
                "description": { "type": "string" }
              },
              "required": ["command"]
            }
          }
        ]
      }
    ]
  }
}
```

- Assistant tool call (model parts contain functionCall)

```json
{
  "role": "model",
  "parts": [
    { "functionCall": { "id": "fc1", "name": "run_shell_command", "args": { "command": "ls -la" } } }
  ]
}
```

- Tool result injection (user parts include functionResponse)

```json
{
  "role": "user",
  "parts": [
    {
      "functionResponse": {
        "id": "fc1",
        "name": "run_shell_command",
        "response": {
          "output": "Command: ls -la\nDirectory: (root)\nOutput: ...\nError: (none)\nExit Code: 0"
        }
      }
    }
  ]
}
```
