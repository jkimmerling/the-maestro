Codex CLI Tooling and LLM Call Specifications (from source/codex)

Overview

- Purpose: Exact message formats, request headers, tool definitions, and auth-mode differences used by Codex (Rust implementation in source/codex/codex-rs). This mirrors the wire-level behavior so you can implement the same in Elixir.
- Wire APIs: Codex supports both OpenAI Responses API and classic Chat Completions API. Provider selection decides the wire API. The built-in OpenAI provider uses Responses; the built-in OSS provider uses Chat Completions.
- Auth Modes: API key (OPENAI_API_KEY or provider env) and Personal ChatGPT OAuth (auth.json + tokens). This affects base URL, some headers, and whether responses are server-stored.

Key Source Files

- Request building / streaming
  - core/src/client.rs (Responses API streaming, headers, retries)
  - core/src/chat_completions.rs (Chat Completions streaming, messages mapping)
  - core/src/client_common.rs (Prompt, ResponsesApiRequest, reasoning/text controls)
  - core/src/model_provider_info.rs (provider config, base URLs, headers, auth selection)
- Tool definitions
  - core/src/openai_tools.rs (shell, web_search, view_image, MCP conversion, tools JSON for both APIs)
  - core/src/tool_apply_patch.rs and core/src/tool_apply_patch.lark (apply_patch freeform/function)
  - core/src/plan_tool.rs (update_plan)
  - core/src/exec_command/responses_api.rs (exec_command, write_stdin tools)
- Tool call handling and conversation flow
  - core/src/codex.rs (run task/turn, handle tool calls, safety, approvals, MCP calls)
  - core/src/mcp_connection_manager.rs, core/src/mcp_tool_call.rs (MCP tool listing/calls)
  - codex-rs/protocol/src/models.rs (ResponseItem shapes and serialization)

Wire APIs and Base URLs

- Responses API (OpenAI and ChatGPT OAuth)
  - Base URL selection (core/src/model_provider_info.rs::get_full_url):
    - ChatGPT OAuth: https://chatgpt.com/backend-api/codex/responses
    - OpenAI API default: https://api.openai.com/v1/responses
    - Optional override via config.toml model_providers[*].base_url (query params appended if configured)
  - Required headers for Responses API requests (core/src/client.rs):
    - OpenAI-Beta: responses=experimental
    - session_id: <uuid-v4 per session>
    - originator: <config.responses_originator_header> (default "codex_cli_rs")
    - User-Agent: <Codex UA string>
    - Authorization: Bearer <token> (API key or ChatGPT access token)
    - If ChatGPT OAuth and account id present: chatgpt-account-id: <account_id>
    - Accept: text/event-stream

- Chat Completions API (classic OpenAI-compatible)
  - Endpoint: <base_url>/chat/completions (provider-dependent; built-in OSS provider uses Chat)
  - Headers: Authorization (if provider requires), Accept: text/event-stream

Auth Modes (exact behavior)

- API Key (AuthMode::ApiKey)
  - Token selection (core/src/model_provider_info.rs::create_request_builder): if provider has env_key, read that env var; otherwise use AuthManager (auth.json or OPENAI_API_KEY). Bearer auth uses the selected value.
  - Base URL defaults to https://api.openai.com/v1 for the built-in OpenAI provider.
  - For Responses API requests, the body field "store" equals Prompt.store.

- ChatGPT OAuth (AuthMode::ChatGPT)
  - Tokens stored in $CODEX_HOME/auth.json:
    {
      "OPENAI_API_KEY": "..." | null,
      "tokens": { "id_token": "<JWT>", "access_token": "<opaque>", "refresh_token": "<opaque>", "account_id": "<uuid>"? },
      "last_refresh": "<ISO8601>"
    }
  - Authorization: Bearer <access_token>; also set header chatgpt-account-id: <account_id> when present.
  - Base URL defaults to https://chatgpt.com/backend-api/codex/responses.
  - For Responses API, store is always false (core/src/client.rs: let store = prompt.store && auth_mode != Some(AuthMode::ChatGPT)).
  - Token refresh: POST https://auth.openai.com/oauth/token with JSON body
    { "client_id": "app_EMoamEEZ73f0CkXaXp7hrann", "grant_type": "refresh_token", "refresh_token": "<refresh>", "scope": "openid profile email" }
    On success returns { id_token, access_token?, refresh_token? } which are written back to auth.json; last_refresh updated.

Responses API Request Payload (exact fields)

POST {base_url}/responses
Headers:
- OpenAI-Beta: responses=experimental
- session_id: "<uuid>"
- originator: "codex_cli_rs" (configurable)
- User-Agent: "Codex/<version>"
- Authorization: Bearer <token>
- If ChatGPT OAuth: chatgpt-account-id: <account_id>
- Accept: text/event-stream

Body JSON (core/src/client_common.rs::ResponsesApiRequest):
{
  "model": "<model-slug>",
  "instructions": "<system instructions string>",
  "input": [ <ResponseItem objects> ],
  "tools": [ <Responses-API tool objects> ],
  "tool_choice": "auto",
  "parallel_tool_calls": false,
  "reasoning": { "effort": "low|medium|high", "summary": "none|concise|detailed" } | null,
  "store": true|false,
  "stream": true,
  "include": [ "reasoning.encrypted_content" ] | [],
  "prompt_cache_key": "<uuid>" | null,
  "text": { "verbosity": "low|medium|high" } | null
}

Population rules:
- reasoning present only if model family supports reasoning summaries.
- include = ["reasoning.encrypted_content"] when store==false and reasoning!=null; otherwise [].
- text.verbosity only for GPT-5 family; omitted for other families even if configured (a warning is logged in code).

Responses API Stream Events (Codex maps to internal ResponseEvent)

- response.output_item.done → OutputItemDone(ResponseItem)
- response.output_text.delta → OutputTextDelta(String)
- response.reasoning_summary_text.delta → ReasoningSummaryDelta(String)
- response.reasoning_text.delta → ReasoningContentDelta(String)
- response.output_item.added (if type=="web_search_call") → WebSearchCallBegin { call_id }
- response.reasoning_summary_part.added → ReasoningSummaryPartAdded
- response.created (when present) → Created
- response.failed → error with optional retry-after delay parsed from message (rate limit)
- response.completed → Completed { response_id, token_usage? }

ResponseItem shapes (protocol/models.rs; exact field names and tags)

- Message:
  { "type": "message", "id": null|"...", "role": "assistant|user", "content": [ { "type": "output_text"|"input_text", "text": "..." } ] }
- FunctionCall:
  { "type": "function_call", "id": null|"...", "name": "...", "arguments": "<raw JSON string>", "call_id": "..." }
- FunctionCallOutput (when Codex replies):
  { "type": "function_call_output", "call_id": "...", "output": "<string>" }
- CustomToolCall:
  { "type": "custom_tool_call", "id": null|"...", "status": null|"...", "call_id": "...", "name": "...", "input": "<string>" }
- CustomToolCallOutput:
  { "type": "custom_tool_call_output", "call_id": "...", "output": "<string>" }
- LocalShellCall:
  { "type": "local_shell_call", "id": null|"...", "call_id": null|"...", "status": "completed|in_progress|incomplete", "action": { "type": "exec", "command": ["..."], "timeout_ms": n|null, "working_directory": "..."|null, "env": {..}|null, "user": "..."|null } }
- WebSearchCall:
  { "type": "web_search_call", "id": null|"...", "status": null|"...", "action": { "type": "search", "query": "..." } }
- Reasoning:
  { "type": "reasoning", "id": "...", "summary": [ { "type": "summary_text", "text": "..." } ], "content": [ { "type": "reasoning_text"|"text", "text": "..." } ] | null, "encrypted_content": "..." | null }
- Other: { "type": "other" }

Important: FunctionCallOutputPayload serializes output as a plain JSON string (never an object), for both success and failure cases. This mirrors upstream CLI to avoid 400 errors.

Chat Completions API Request Payload and Mapping (exact behavior)

POST {base_url}/chat/completions
Headers: Authorization (if required by provider), Accept: text/event-stream

Body JSON:
{
  "model": "<model-slug>",
  "messages": [ ... ],
  "stream": true,
  "tools": [ <Chat-Completions tool objects> ]
}

messages construction (core/src/chat_completions.rs):
- Prepend a system message: { "role": "system", "content": "<full instructions>" }
- Convert Prompt.input (Vec<ResponseItem>) to messages:
  - ResponseItem::Message → { "role": role, "content": text }, and if role=="assistant" and an adjacent reasoning string exists, include "reasoning": "..."
  - ResponseItem::FunctionCall → assistant anchor with tool_calls:
    { "role": "assistant", "content": null, "tool_calls": [ { "id": call_id, "type": "function", "function": { "name": name, "arguments": arguments } } ], ["reasoning": "..."]? }
  - ResponseItem::LocalShellCall → assistant anchor with tool_calls:
    { "role": "assistant", "content": null, "tool_calls": [ { "id": <id or empty>, "type": "local_shell_call", "status": status, "action": action_obj } ], ["reasoning": "..."]? }
  - ResponseItem::FunctionCallOutput → tool role message:
    { "role": "tool", "tool_call_id": call_id, "content": output_string }
  - ResponseItem::CustomToolCall → assistant anchor with tool_calls:
    { "role": "assistant", "content": null, "tool_calls": [ { "id": id, "type": "custom", "custom": { "name": name, "input": input } } ] }
  - ResponseItem::CustomToolCallOutput → { "role": "tool", "tool_call_id": call_id, "content": output }
  - Reasoning, WebSearchCall, Other → omitted from messages

Reasoning attachment rules:
- Reasoning text after the last user message is attached to the immediate previous assistant message (stop turns), or to the immediate next assistant anchor (tool_calls or assistant message) for tool-call turns. If the conversation ends with a user message, reasoning is dropped.

Streaming handling (core/src/chat_completions.rs::process_chat_sse):
- Accumulates assistant content deltas from choices[0].delta.content
- For tool_calls streamed via delta.tool_calls, accumulates name and arguments string pieces; when finish_reason=="tool_calls" emits a single ResponseItem::FunctionCall with the aggregated name/arguments and call_id.
- When finish_reason=="stop", emits a single terminal assistant message item with the accumulated text (and a terminal reasoning item if present), followed by Completed.
- For consumers not interested in per-token deltas, Codex wraps the stream with an aggregation adapter so only OutputItemDone + Completed are forwarded (matching Responses API behavior).

Chat tools array mapping (core/src/openai_tools.rs::create_tools_json_for_chat_completions_api):
- Input: list of OpenAiTool values
- Output: Only function tools are included, transformed to { "type": "function", "function": { name, description, strict, parameters } }
- Non-function tools (local_shell, web_search, custom/freeform) are omitted from the Chat Completions tools array.

Built-in Tools (names, descriptions, parameters)

1) shell (function)

- Default schema (ConfigShellToolType::DefaultShell):
  name: "shell"
  description: "Runs a shell command and returns its output"
  strict: false
  parameters:
  {
    "type": "object",
    "properties": {
      "command": { "type": "array", "items": { "type": "string" }, "description": "The command to execute" },
      "workdir": { "type": "string", "description": "The working directory to execute the command in" },
      "timeout_ms": { "type": "number", "description": "The timeout for the command in milliseconds" }
    },
    "required": ["command"],
    "additionalProperties": false
  }

- ShellWithRequest variant (AskForApproval::OnRequest, non-streamable tool): adds optional properties when sandbox_policy is WorkspaceWrite or ReadOnly:
  - with_escalated_permissions: boolean – "Whether to request escalated permissions. Set to true if command needs to be run without sandbox restrictions"
  - justification: string – "Only set if with_escalated_permissions is true. 1-sentence explanation of why we want to run this command."

  Description text (WorkspaceWrite; append the network line only when network_access is false):
  "
The shell tool is used to execute shell commands.
- When invoking the shell tool, your call will be running in a landlock sandbox, and some shell commands will require escalated privileges:
  - Types of actions that require escalated privileges:
    - Reading files outside the current directory
    - Writing files outside the current directory, and protected folders like .git or .env
  - Examples of commands that require escalated privileges:
    - git commit
    - npm install or pnpm install
    - cargo build
    - cargo test
- When invoking a command that will require escalated privileges:
  - Provide the with_escalated_permissions parameter with the boolean value true
  - Include a short, 1 sentence explanation for why we need to run with_escalated_permissions in the justification parameter." + (optional line if network_access==false: "\n  - Commands that require network access\n")
  "

  Description text (ReadOnly):
  "
The shell tool is used to execute shell commands.
- When invoking the shell tool, your call will be running in a landlock sandbox, and some shell commands (including apply_patch) will require escalated permissions:
  - Types of actions that require escalated privileges:
    - Reading files outside the current directory
    - Writing files
    - Applying patches
  - Examples of commands that require escalated privileges:
    - apply_patch
    - git commit
    - npm install or pnpm install
    - cargo build
    - cargo test
- When invoking a command that will require escalated privileges:
  - Provide the with_escalated_permissions parameter with the boolean value true
  - Include a short, 1 sentence explanation for why we need to run with_escalated_permissions in the justification parameter"
  "

2) local_shell (non-function)

- Only for model families with uses_local_shell_tool=true (e.g., "codex-mini-latest"). Tool entry in Responses tools: { "type": "local_shell" }.
- Tool calls appear as items of type local_shell_call (Responses) or Chat tool_calls with type local_shell_call; Codex executes these via the same exec path and replies with function_call_output items.

3) web_search (non-function)

- Tool entry in Responses tools when config.tools_web_search_request=true: { "type": "web_search" }.
- No input parameters; Codex emits WebSearchBegin/WebSearchEnd UI events and does not send a tool output back to the model for this tool.

4) view_image (function)

- name: "view_image"
- description: "Attach a local image (by filesystem path) to the conversation context for this turn."
- parameters:
  {
    "type": "object",
    "properties": { "path": { "type": "string", "description": "Local filesystem path to an image file" } },
    "required": ["path"],
    "additionalProperties": false
  }
- Behavior: Codex resolves the path against session cwd, injects an InputItem::LocalImage, and returns a function_call_output acknowledging attachment; the actual image is base64-embedded on the next turn.

5) update_plan (function)

- name: "update_plan"
- description (exact):
  "Updates the task plan.\nProvide an optional explanation and a list of plan items, each with a step and status.\nAt most one step can be in_progress at a time.\n"
- parameters (core/src/plan_tool.rs):
  {
    "type": "object",
    "properties": {
      "explanation": { "type": "string" },
      "plan": {
        "type": "array",
        "description": "The list of steps",
        "items": {
          "type": "object",
          "properties": {
            "step": { "type": "string" },
            "status": { "type": "string", "description": "One of: pending, in_progress, completed" }
          },
          "required": ["step", "status"],
          "additionalProperties": false
        }
      }
    },
    "required": ["plan"],
    "additionalProperties": false
  }
- Execution: Emits PlanUpdate to client; returns function_call_output with content "Plan updated".

6) apply_patch (two variants)

6.a) Custom freeform tool (preferred for GPT-5 family)

- Entry in tools (Responses API):
  {
    "type": "custom",
    "name": "apply_patch",
    "description": "Use the `apply_patch` tool to edit files",
    "format": { "type": "grammar", "syntax": "lark", "definition": "<grammar below>" }
  }
- Lark grammar (exact):

```
start: begin_patch hunk+ end_patch
begin_patch: "*** Begin Patch" LF
end_patch: "*** End Patch" LF?

hunk: add_hunk | delete_hunk | update_hunk
add_hunk: "*** Add File: " filename LF add_line+
delete_hunk: "*** Delete File: " filename LF
update_hunk: "*** Update File: " filename LF change_move? change?

filename: /(.+)/
add_line: "+" /(.*)/ LF -> line

change_move: "*** Move to: " filename LF
change: (change_context | change_line)+ eof_line?
change_context: ("@@" | "@@ " /(.+)/) LF
change_line: ("+" | "-" | " ") /(.*)/ LF
eof_line: "*** End of File" LF

%import common.LF
```

- Execution: Codex recognizes apply_patch invocations and uses the internal patch engine to apply file ops; approvals/sandbox may be required for write operations depending on policy.

6.b) Function tool variant (used for OSS or when include_apply_patch_tool=true and model prefers function schema)

- Entry in tools (Responses API):
  {
    "type": "function",
    "name": "apply_patch",
    "description": "Use the `apply_patch` tool to edit files.\n<full patch language primer below>\n",
    "strict": false,
    "parameters": {
      "type": "object",
      "properties": {
        "input": { "type": "string", "description": "The entire contents of the apply_patch command" }
      },
      "required": ["input"],
      "additionalProperties": false
    }
  }

- Description exact body (truncated here in outline form for readability; in code it is embedded verbatim and should be copied verbatim for byte-for-byte parity):
  - Explains the patch envelope:
    *** Begin Patch\n[ one or more file sections ]\n*** End Patch
  - File operations: Add File, Delete File, Update File (+ optional Move to), hunks with @@ headers and +/−/space lines
  - Context rules (3 lines default, @@ scoping when needed, multiple @@ allowed)
  - Full formal grammar is included in the description text in code (same as the Lark grammar above)
  - Notes: must include operation headers; prefix new lines with +; only relative file paths

  Verbatim description string from core/src/tool_apply_patch.rs:

```
Use the `apply_patch` tool to edit files.
Your patch language is a stripped‑down, file‑oriented diff format designed to be easy to parse and safe to apply. You can think of it as a high‑level envelope:

*** Begin Patch
[ one or more file sections ]
*** End Patch

Within that envelope, you get a sequence of file operations.
You MUST include a header to specify the action you are taking.
Each operation starts with one of three headers:

*** Add File: <path> - create a new file. Every following line is a + line (the initial contents).
*** Delete File: <path> - remove an existing file. Nothing follows.
*** Update File: <path> - patch an existing file in place (optionally with a rename).

May be immediately followed by *** Move to: <new path> if you want to rename the file.
Then one or more “hunks”, each introduced by @@ (optionally followed by a hunk header).
Within a hunk each line starts with:

For instructions on [context_before] and [context_after]:
- By default, show 3 lines of code immediately above and 3 lines immediately below each change. If a change is within 3 lines of a previous change, do NOT duplicate the first change’s [context_after] lines in the second change’s [context_before] lines.
- If 3 lines of context is insufficient to uniquely identify the snippet of code within the file, use the @@ operator to indicate the class or function to which the snippet belongs. For instance, we might have:
@@ class BaseClass
[3 lines of pre-context]
- [old_code]
+ [new_code]
[3 lines of post-context]

- If a code block is repeated so many times in a class or function such that even a single `@@` statement and 3 lines of context cannot uniquely identify the snippet of code, you can use multiple `@@` statements to jump to the right context. For instance:

@@ class BaseClass
@@ 	 def method():
[3 lines of pre-context]
- [old_code]
+ [new_code]
[3 lines of post-context]

The full grammar definition is below:
Patch := Begin { FileOp } End
Begin := "*** Begin Patch" NEWLINE
End := "*** End Patch" NEWLINE
FileOp := AddFile | DeleteFile | UpdateFile
AddFile := "*** Add File: " path NEWLINE { "+" line NEWLINE }
DeleteFile := "*** Delete File: " path NEWLINE
UpdateFile := "*** Update File: " path NEWLINE [ MoveTo ] { Hunk }
MoveTo := "*** Move to: " newPath NEWLINE
Hunk := "@@" [ header ] NEWLINE { HunkLine } [ "*** End of File" NEWLINE ]
HunkLine := (" " | "-" | "+") text NEWLINE

A full patch can combine several operations:

*** Begin Patch
*** Add File: hello.txt
+Hello world
*** Update File: src/app.py
*** Move to: src/main.py
@@ def greet():
-print("Hi")
+print("Hello, world!")
*** Delete File: obsolete.txt
*** End Patch

It is important to remember:

- You must include a header with your intended action (Add/Delete/Update)
- You must prefix new lines with `+` even when creating a new file
- File references can only be relative, NEVER ABSOLUTE.
```

7) Streamable exec tools (experimental)

- When Config.use_experimental_streamable_shell_tool=true, two function tools are added:

  a) exec_command
  - name: "exec_command"
  - description: "Execute shell commands on the local machine with streaming output."
  - parameters:
    {
      "type": "object",
      "properties": {
        "cmd": { "type": "string", "description": "The shell command to execute." },
        "yield_time_ms": { "type": "number", "description": "The maximum time in milliseconds to wait for output." },
        "max_output_tokens": { "type": "number", "description": "The maximum number of tokens to output." },
        "shell": { "type": "string", "description": "The shell to use. Defaults to \"/bin/bash\"." },
        "login": { "type": "boolean", "description": "Whether to run the command as a login shell. Defaults to true." }
      },
      "required": ["cmd"],
      "additionalProperties": false
    }

 b) write_stdin
  - name: "write_stdin"
  - description: "Write characters to an exec session's stdin. Returns all stdout+stderr received within yield_time_ms.\nCan write control characters (\u0003 for Ctrl-C), or an empty string to just poll stdout+stderr."
  - parameters:
    {
      "type": "object",
      "properties": {
        "session_id": { "type": "number", "description": "The ID of the exec_command session." },
        "chars": { "type": "string", "description": "The characters to write to stdin." },
        "yield_time_ms": { "type": "number", "description": "The maximum time in milliseconds to wait for output after writing." },
        "max_output_tokens": { "type": "number", "description": "The maximum number of tokens to output." }
      },
      "required": ["session_id", "chars"],
      "additionalProperties": false
    }

MCP Tools (Model Context Protocol)

- Codex spawns configured MCP servers and aggregates their tools (core/src/mcp_connection_manager.rs). Tools are included into the model tools list as function tools with fully-qualified names.
- Fully-qualified name format: "<server_name>__<tool_name>" (double underscore). If the result exceeds 64 chars, a sha1 suffix is appended after truncation to exactly 64 chars. Duplicate names are skipped.
- Conversion (core/src/openai_tools.rs::mcp_tool_to_openai_tool):
  {
    "type": "function",
    "name": "<server__tool>",
    "description": "<server-provided or empty>",
    "strict": false,
    "parameters": <sanitized JSON Schema>
  }
- Schema sanitation rules (create_tools_json_for_responses_api → sanitize_json_schema):
  - Ensure every schema object has a "type"; infer from keywords: properties=>object, items=>array, enum/const/format=>string, numeric constraints=>number; fallback to "string".
  - If type union array present, pick first supported among object|array|string|number|integer|boolean; integer normalized to number.
  - Ensure object schemas have a properties map (empty if absent). If additionalProperties is an object, sanitize that object too (booleans left as-is).
  - Ensure array schemas have items (default {"type":"string"}).

How Tool Calls and Outputs Flow

- Model emits tool calls:
  - Responses API: ResponseItem::FunctionCall { name, arguments (raw string), call_id }, ResponseItem::LocalShellCall, ResponseItem::CustomToolCall, WebSearchCall.
  - Chat Completions: assistant tool_calls anchors (function/local_shell_call/custom) and tool role messages for outputs.
- Codex executes via core/src/codex.rs::handle_function_call and core/src/mcp_tool_call.rs:
  - Names handled: "container.exec" | "shell", "view_image", "apply_patch", "update_plan", EXEC_COMMAND_TOOL_NAME ("exec_command"), WRITE_STDIN_TOOL_NAME ("write_stdin").
  - For MCP tools, Codex dispatches to the MCP client and returns a FunctionCallOutput with serialized result or error.
- Codex replies in the next turn by pre‑pending outputs to input:
  - Function call output: ResponseItem::FunctionCallOutput { call_id, output: "<string>" }
  - MCP result becomes the same FunctionCallOutput shape with content string

Safety, Approvals, and Sandbox

- For exec/apply_patch commands, Codex assesses safety (core/src/codex.rs):
  - Depending on AskForApproval and SandboxPolicy: auto-approve in sandbox, ask user to escalate, or reject.
  - On sandbox denial/failure with AskForApproval::OnFailure/UnlessTrusted, Codex prompts user to retry without sandbox; if approved, re-runs with SandboxType::None.
  - If command times out, returns a failure FunctionCallOutput describing the timeout.

System Instructions and Context Injection

- System instructions passed as a single string (instructions field for Responses; system message for Chat):
  - Base: core/src/prompt.md contents.
  - If model family needs extra apply_patch guidance (e.g. gpt-4.1) or no apply_patch tool is present, append the contents of apply-patch/apply_patch_tool_instructions.md.
- A user message with <user_instructions> ... </user_instructions> is injected at session start when available.
- An environment context message is injected at session start:
  <environment_context>
    <cwd>...</cwd>
    <approval_policy>...</approval_policy>
    <sandbox_mode>...</sandbox_mode>
    <network_access>...</network_access>
    <shell>...</shell>
  </environment_context>

Chat vs Responses API Differences (summary)

- Endpoint and base URL:
  - Responses: https://api.openai.com/v1/responses or https://chatgpt.com/backend-api/codex/responses (OAuth)
  - Chat: <provider base>/chat/completions
- Request headers:
  - Responses: OpenAI-Beta, session_id, originator, User-Agent, Authorization, optional chatgpt-account-id
  - Chat: Authorization (if needed), Accept: text/event-stream
- Tools array:
  - Responses: function + local_shell + web_search + custom/freeform tools supported
  - Chat: only function tools included (wrapped under {type:"function", function:{...}})
- Conversation encoding:
  - Responses: input is a typed array of ResponseItem objects
  - Chat: messages encoded as role/content plus tool_calls and tool role messages
- Reasoning:
  - Responses: streamed via reasoning delta events; Codex forwards ReasoningSummaryDelta/ReasoningContentDelta
  - Chat: Codex attaches reasoning strings to assistant anchors per adjacency rules
- Store flag:
  - Responses + ChatGPT OAuth: store=false always
  - Responses + API key: store = Prompt.store

Minimal Concrete Examples

1) Responses API shell call turn (abbreviated)

tools:
[
  {"type":"function","name":"shell","description":"Runs a shell command and returns its output","strict":false,
   "parameters":{"type":"object","properties":{"command":{"type":"array","items":{"type":"string"},"description":"The command to execute"},
                  "workdir":{"type":"string","description":"The working directory to execute the command in"},
                  "timeout_ms":{"type":"number","description":"The timeout for the command in milliseconds"}},
                 "required":["command"],"additionalProperties":false}}]

input contains a function call item streamed by the model:
{"type":"function_call","id":null,"name":"shell","arguments":"{\"command\":[\"ls\",\"-l\"]}","call_id":"call_123"}

Codex executes and prepends to next turn:
{"type":"function_call_output","call_id":"call_123","output":"{\"output\":\"...\",\"metadata\":{\"exit_code\":0}}"}

2) Chat Completions shell call turn (abbreviated)

tools:
[{"type":"function","function":{"name":"shell","description":"Runs a shell command and returns its output","strict":false,"parameters":{...}}}]

messages (abbreviated):
[
  {"role":"system","content":"<instructions>"},
  {"role":"user","content":"<prompt>"},
  {"role":"assistant","content":null,"tool_calls":[{"id":"call_123","type":"function","function":{"name":"shell","arguments":"{\"command\":[\"ls\"]}"}}]},
  {"role":"tool","tool_call_id":"call_123","content":"{\"output\":\"...\"}"}
]

Complete Tool List and Inclusion Conditions

- shell (function) – always included unless model family uses local_shell tool; default schema as above; ShellWithRequest variant when AskForApproval::OnRequest and non-streamable shell is used.
- local_shell (non-function) – included when model_family.uses_local_shell_tool=true (e.g., "codex-mini-latest").
- exec_command (function) – included only when Config.use_experimental_streamable_shell_tool=true.
- write_stdin (function) – included only when Config.use_experimental_streamable_shell_tool=true.
- web_search (non-function) – included when config.tools_web_search_request=true.
- view_image (function) – included when config.include_view_image_tool=true.
- apply_patch (custom/freeform) – included when model family apply_patch_tool_type==Freeform OR config.include_apply_patch_tool=true and family default is none; preferred for GPT-5 style families.
- apply_patch (function) – included when model family apply_patch_tool_type==Function OR config.include_apply_patch_tool=true for OSS models.
- update_plan (function) – included when config.include_plan_tool=true.
- MCP tools (function) – all tools from configured MCP servers converted to function tools with sanitized schemas and fully-qualified names.

System Prompt Changes and Context Edits

- System instructions string is recomputed each turn based on:
  - Base prompt (prompt.md)
  - Whether apply_patch needs extra instructions: if model family flag needs_special_apply_patch_instructions is true OR no apply_patch tool is present, append the contents of apply_patch_tool_instructions.md.
  - An optional base_instructions override replaces the base prompt entirely for that turn.
- Context includes appended conversation history (assistant/user messages and API messages only), plus the initial <user_instructions> and <environment_context> user messages.
- Tool usage itself does not change the system prompt content, except via the conditional apply_patch instructions as described. Conversation history grows with tool calls and their outputs so future turns include those items (Responses) or mapped tool/tool_call messages (Chat).

Additional Examples and Edge Cases (Addendum)

Concrete tool_result examples (as sent back to the model)

- shell → Responses API function_call_output
  {
    "type": "function_call_output",
    "call_id": "call_123",
    "output": "{\"output\":\"README.md\nlib/\n\",\"metadata\":{\"exit_code\":0,\"duration_seconds\":0.1}}"
  }

- shell → Chat Completions tool output message
  { "role": "tool", "tool_call_id": "call_123", "content": "{\"output\":\"README.md\\nlib/\\n\",\"metadata\":{\"exit_code\":0,\"duration_seconds\":0.1}}" }

- apply_patch → Responses API function_call_output (same shape as shell; content shows patch application result)
  {
    "type": "function_call_output",
    "call_id": "call_99",
    "output": "{\"output\":\"Applied 1 update to README.md\",\"metadata\":{\"exit_code\":0,\"duration_seconds\":0.2}}"
  }

- view_image → immediate tool result + next turn image content
  Immediate tool result:
  { "type": "function_call_output", "call_id": "img_1", "output": "attached local image path" }
  Next turn (Responses API input fragment):
  { "type": "message", "role": "user", "content": [ { "type": "input_image", "image_url": "data:image/png;base64,iVBORw0K..." } ] }

- update_plan → Responses API function_call_output
  { "type": "function_call_output", "call_id": "plan_1", "output": "Plan updated" }

- exec_command/write_stdin (experimental) → Responses API function_call_output
  { "type": "function_call_output", "call_id": "exec_1", "output": "{\"output\":\"…streamed text…\",\"metadata\":{\"exit_code\":0,\"duration_seconds\":1.3}}" }

- MCP tool call → Responses API function_call_output
  { "type": "function_call_output", "call_id": "mcp_1", "output": "{\"ok\":true,\"value\":42}" }

End-to-end examples (messages arrays before API call)

- Chat Completions (user → assistant tool_use → tool_result → assistant)
  tools:
  [ { "type": "function", "function": { "name": "shell", "description": "Runs a shell command and returns its output", "strict": false, "parameters": { "type": "object", "properties": { "command": { "type": "array", "items": {"type":"string"} } }, "required": ["command"], "additionalProperties": false } } } ]
  messages:
  [
    { "role": "system", "content": "<instructions>" },
    { "role": "user", "content": "List files" },
    { "role": "assistant", "content": null, "tool_calls": [ { "id": "call_123", "type": "function", "function": { "name": "shell", "arguments": "{\"command\":[\"ls\"]}" } } ] },
    { "role": "tool", "tool_call_id": "call_123", "content": "{\"output\":\"README.md\\nlib/\\n\",\"metadata\":{\"exit_code\":0,\"duration_seconds\":0.1}}" },
    { "role": "assistant", "content": "Found README.md and lib/" }
  ]

- Responses API (example input for a tool turn)
  input:
  [
    { "type": "message", "role": "user", "content": [ { "type": "input_text", "text": "List files" } ] }
  ]
  The model streams a function_call:
  { "type": "function_call", "id": null, "name": "shell", "arguments": "{\"command\":[\"ls\"]}", "call_id": "call_123" }
  Codex replies next turn with:
  { "type": "function_call_output", "call_id": "call_123", "output": "{\"output\":\"README.md\\nlib/\\n\",\"metadata\":{\"exit_code\":0,\"duration_seconds\":0.1}}" }

SSE transcripts from tests (Responses API)

- Two output items and a completed event (verbatim shape from unit tests):
  event: response.output_item.done
  data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello"}]}}

  event: response.output_item.done
  data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"World"}]}}

  event: response.completed
  data: {"type":"response.completed","response":{"id":"resp1"}}

Edge cases and nuances

- Model resolution and overrides:
  - Family detection via core/src/model_family.rs::find_family_for_model (sets abilities like reasoning-summaries, local_shell, apply_patch preference)
  - Model provider selection via config.toml; OPENAI_BASE_URL env overrides built-in OpenAI provider base URL
- OAuth nuances for ChatGPT:
  - Access token and refresh in $CODEX_HOME/auth.json; refresh via POST https://auth.openai.com/oauth/token
  - Header "chatgpt-account-id" added when present
  - Responses API store=false forced; include ["reasoning.encrypted_content"] when reasoning present
  - Usage-limit errors (429) return structured JSON with plan_type and resets_in_seconds; Codex surfaces UsageLimitReached errors to UI

MCP functionDeclarations examples (sanitized from tests)

- dash/paginate (integer normalized to number)
  tool entry:
  { "type": "function", "name": "dash/paginate", "description": "Pagination", "strict": false,
    "parameters": { "type": "object", "properties": { "page": { "type": "number" } }, "required": null, "additionalProperties": null } }

- dash/tags (array without items defaulted to string items)
  tool entry:
  { "type": "function", "name": "dash/tags", "description": "Tags", "strict": false,
    "parameters": { "type": "object", "properties": { "tags": { "type": "array", "items": { "type": "string" } } }, "required": null, "additionalProperties": null } }

Built-in tool summary (names → source paths → params → llmContent → returnDisplay)

- shell
  - Source: core/src/openai_tools.rs (create_shell_tool*), core/src/codex.rs (handle_function_call → exec), core/src/codex.rs (format_exec_output)
  - Params: { command: string[], workdir?: string, timeout_ms?: number, with_escalated_permissions?: boolean, justification?: string }
  - LLM content: function_call {name:"shell", arguments: string JSON}
  - ReturnDisplay: function_call_output content string {output, metadata{exit_code,duration_seconds}}

- local_shell
  - Source: openai_tools.rs (LocalShell), codex.rs (LocalShellCall handler)
  - Params: action.exec with command/timeout/workdir/env
  - LLM content: local_shell_call item/tool_call
  - ReturnDisplay: same as shell

- web_search
  - Source: openai_tools.rs (WebSearch), codex.rs handler emits events
  - Params: none
  - LLM content: web_search_call item
  - ReturnDisplay: none (UI events only)

- view_image
  - Source: openai_tools.rs (create_view_image_tool), codex.rs (view_image handler), protocol/models.rs (LocalImage→InputImage)
  - Params: { path: string }
  - LLM content: next turn includes message content item {type:"input_image", image_url:"data:<mime>;base64,<encoded>"}
  - ReturnDisplay: function_call_output "attached local image path"

- update_plan
  - Source: plan_tool.rs
  - Params: { plan: [{step,status}], explanation?: string }
  - LLM content: function_call {name:"update_plan"}
  - ReturnDisplay: function_call_output "Plan updated"

- apply_patch (freeform/function)
  - Source: tool_apply_patch.rs (+ .lark), codex.rs handler delegates to exec path
  - Params: freeform grammar or {input: string}
  - LLM content: function_call {name:"apply_patch"}
  - ReturnDisplay: function_call_output content string {output, metadata}

- exec_command / write_stdin (experimental)
  - Source: exec_command/responses_api.rs, session_manager.rs, codex.rs branches
  - Params: exec_command {cmd,yield_time_ms,max_output_tokens,shell,login}; write_stdin {session_id,chars,yield_time_ms,max_output_tokens}
  - LLM content: function_call
  - ReturnDisplay: function_call_output content string {output, metadata}

API-key path examples (headers + request bodies)

- Responses API headers (API key)
  Authorization: Bearer sk-...
  OpenAI-Beta: responses=experimental
  session_id: <uuid>
  originator: codex_cli_rs
  User-Agent: Codex/<ver>
  Accept: text/event-stream

- Responses API body (minimal)
  { "model": "gpt-5", "instructions": "…", "input": [], "tools": [], "tool_choice": "auto", "parallel_tool_calls": false, "store": true, "stream": true, "include": [] }

- Chat Completions headers (API key)
  Authorization: Bearer sk-...
  Accept: text/event-stream
  User-Agent: Codex/<ver>

- Chat Completions body (minimal)
  { "model": "gpt-4o", "messages": [ { "role": "system", "content": "…" }, { "role": "user", "content": "…" } ], "stream": true, "tools": [] }

Per-Tool: Source Paths and Returns (exact)

shell (function)

- Definition (tool JSON):
  - source/codex/codex-rs/core/src/openai_tools.rs → create_shell_tool() and create_shell_tool_for_sandbox()
- Execution handler:
  - source/codex/codex-rs/core/src/codex.rs → handle_function_call → name == "container.exec" | "shell" → parse_container_exec_arguments() → handle_container_exec_with_params()
  - Execution pipeline: run_exec_with_events() and format_exec_output() for the content string
- Return to LLM when done:
  - Responses API: ResponseItem::FunctionCallOutput { call_id, output: "<string>" }
    - output is a JSON string of shape {"output":"<truncated head/tail of combined stdout+stderr>","metadata":{"exit_code":<i32>,"duration_seconds":<f32>}}
    - exact serializer in core/src/codex.rs: format_exec_output()
  - Chat Completions: { role:"tool", tool_call_id:"<call_id>", content:"<same string>" }

local_shell (non-function)

- Definition (tool JSON):
  - Included as {"type":"local_shell"} when model family requires it
  - source/codex/codex-rs/core/src/openai_tools.rs → get_openai_tools() branch for ConfigShellToolType::LocalShell
- Execution handler:
  - The model emits a LocalShellCall; Codex handles via the same exec path as shell in core/src/codex.rs
- Return to LLM when done:
  - Same as shell: FunctionCallOutput with the formatted exec output string (Responses) or tool role message (Chat)

web_search (non-function)

- Definition (tool JSON):
  - {"type":"web_search"} when config.tools_web_search_request=true
  - source/codex/codex-rs/core/src/openai_tools.rs → get_openai_tools()
- Execution handler:
  - Emitted by model as WebSearchCall; Codex sends WebSearchBegin/WebSearchEnd events (core/src/codex.rs)
- Return to LLM when done:
  - No function_call_output is sent back to the model for web_search; Codex only emits UI events

view_image (function)

- Definition (tool JSON):
  - source/codex/codex-rs/core/src/openai_tools.rs → create_view_image_tool()
- Execution handler:
  - source/codex/codex-rs/core/src/codex.rs → handle_function_call → name == "view_image"; resolves path, then injects InputItem::LocalImage { path }
  - The injected image becomes a ContentItem::InputImage with a data URL on next turn: see source/codex/codex-rs/protocol/src/models.rs → impl From<Vec<InputItem>> for ResponseInputItem → LocalImage branch:
    - Reads file bytes
    - mime_guess::from_path(path).first().essence_str()
    - Base64 encodes bytes
    - Sets image_url: "data:<mime>;base64,<encoded>"
- Return to LLM when done:
  - Immediate tool result: FunctionCallOutput with content "attached local image path" (or failure text)
  - How the image is sent to the LLM:
    - Responses API: In the subsequent request’s input array as a user Message with ContentItem::InputImage { image_url: data:<mime>;base64,<encoded> }
    - Chat Completions: Current mapping ignores InputImage when constructing messages (only text is forwarded), so images are not sent via the Chat path

update_plan (function)

- Definition (tool JSON):
  - source/codex/codex-rs/core/src/plan_tool.rs (PLAN_TOOL static)
- Execution handler:
  - source/codex/codex-rs/core/src/plan_tool.rs → handle_update_plan()
- Return to LLM when done:
  - FunctionCallOutput with content "Plan updated"; additionally emits EventMsg::PlanUpdate to UI/clients

apply_patch (custom freeform)

- Definition (tool JSON):
  - source/codex/codex-rs/core/src/tool_apply_patch.rs → create_apply_patch_freeform_tool()
  - Grammar in source/codex/codex-rs/core/src/tool_apply_patch.lark
- Execution handler:
  - source/codex/codex-rs/core/src/codex.rs → handle_function_call → name == "apply_patch" → wraps into ExecParams with command ["apply_patch", input]
  - Actual patch application logic in codex-rs/apply-patch crate (parser + file ops)
- Return to LLM when done:
  - Same as shell: FunctionCallOutput with formatted exec output string; includes exit_code and duration_seconds in metadata of the output string

apply_patch (function variant)

- Definition (tool JSON):
  - source/codex/codex-rs/core/src/tool_apply_patch.rs → create_apply_patch_json_tool()
- Execution handler & returns:
  - Same as freeform, but args are JSON schema { input: string }
  - Return payload same as shell

exec_command (function; experimental streamable shell)

- Definition (tool JSON):
  - source/codex/codex-rs/core/src/exec_command/responses_api.rs → create_exec_command_tool_for_responses_api()
- Execution handler:
  - source/codex/codex-rs/core/src/exec_command/session_manager.rs (exec sessions), and codex.rs wiring
- Return to LLM when done:
  - FunctionCallOutput with string content representing combined output and exec metadata (same general shape as shell)

write_stdin (function; experimental streamable shell)

- Definition (tool JSON):
  - source/codex/codex-rs/core/src/exec_command/responses_api.rs → create_write_stdin_tool_for_responses_api()
- Execution handler:
  - source/codex/codex-rs/core/src/exec_command/session_manager.rs
- Return to LLM when done:
  - FunctionCallOutput with output string for data received after the write within yield_time_ms

MCP tools (function; dynamic)

- Definition (tool JSON):
  - Fully-qualified name tool entries created in source/codex/codex-rs/core/src/openai_tools.rs → mcp_tool_to_openai_tool()
- Execution handler:
  - source/codex/codex-rs/core/src/mcp_tool_call.rs → handle_mcp_tool_call()
- Return to LLM when done:
  - FunctionCallOutput, with content preferring structured_content (serialized JSON) if present else serialized content text blocks

Implementation Pointers and Function Signatures (for Rust→Elixir port)

shell

- Tool JSON constructors:
  - core/src/openai_tools.rs
    - fn create_shell_tool() -> OpenAiTool
    - fn create_shell_tool_for_sandbox(sandbox_policy: &SandboxPolicy) -> OpenAiTool
- Function call parsing/translation:
  - core/src/codex.rs
    - fn parse_container_exec_arguments(arguments: String, turn_context: &TurnContext, call_id: &str) -> Result<ExecParams, Box<ResponseInputItem>>
    - fn to_exec_params(params: ShellToolCallParams, turn_context: &TurnContext) -> ExecParams
- Exec invocation and output mapping:
  - core/src/codex.rs
    - async fn handle_container_exec_with_params(params: ExecParams, sess: &Session, turn_context: &TurnContext, turn_diff_tracker: &mut TurnDiffTracker, sub_id: String, call_id: String) -> ResponseInputItem
    - fn format_exec_output(exec_output: &ExecToolCallOutput) -> String
    - struct ExecInvokeArgs<'a> { params: ExecParams, sandbox_type: SandboxType, sandbox_policy: &'a SandboxPolicy, codex_linux_sandbox_exe: &'a Option<PathBuf>, stdout_stream: Option<StdoutStream> }
    - struct ExecParams { command: Vec<String>, cwd: PathBuf, timeout_ms: Option<u64>, env: HashMap<String,String>, with_escalated_permissions: Option<bool>, justification: Option<String> }
    - struct ExecToolCallOutput { exit_code: i32, stdout: StreamOutput, stderr: StreamOutput, aggregated_output: StreamOutput, duration: Duration }

local_shell

- Tool exposure:
  - core/src/openai_tools.rs → get_openai_tools() includes OpenAiTool::LocalShell when model_family.uses_local_shell_tool
- Handling path:
  - core/src/codex.rs → handle_response_item for ResponseItem::LocalShellCall (maps to ShellToolCallParams then calls handle_container_exec_with_params)

web_search

- Tool exposure:
  - core/src/openai_tools.rs → get_openai_tools() includes OpenAiTool::WebSearch
- Handling path:
  - core/src/codex.rs → WebSearchBegin/WebSearchEnd events (no function_call_output back to model)

view_image

- Tool JSON:
  - core/src/openai_tools.rs → fn create_view_image_tool() -> OpenAiTool
- Handler:
  - core/src/codex.rs → handle_function_call branch name == "view_image"
    - Resolves path via TurnContext::resolve_path(Some(args.path))
    - Injects InputItem::LocalImage { path }
- Data encoding into input for next turn (Responses API):
  - codex-rs/protocol/src/models.rs
    - impl From<Vec<InputItem>> for ResponseInputItem converts LocalImage to ContentItem::InputImage with:
      - bytes = std::fs::read(path)
      - mime = mime_guess::from_path(path).first().map(|m| m.essence_str())
      - encoded = base64::STANDARD.encode(bytes)
      - image_url = format!("data:{mime};base64,{encoded}")

update_plan

- Tool JSON + handler:
  - core/src/plan_tool.rs
    - static PLAN_TOOL: LazyLock<OpenAiTool> (name: "update_plan")
    - async fn handle_update_plan(session: &Session, arguments: String, sub_id: String, call_id: String) -> ResponseInputItem

apply_patch (freeform)

- Tool JSON:
  - core/src/tool_apply_patch.rs → fn create_apply_patch_freeform_tool() -> OpenAiTool
  - grammar: core/src/tool_apply_patch.lark
- Handler chain:
  - core/src/codex.rs → handle_function_call name=="apply_patch" parses args {input}
  - Wraps as ExecParams { command: ["apply_patch", input], ... } then calls handle_container_exec_with_params
  - Internals for parsing and applying patch: codex-rs/apply-patch crate
    - apply-patch/src/lib.rs: parse_patch, maybe_parse_apply_patch, apply_patch engine

apply_patch (function)

- Tool JSON:
  - core/src/tool_apply_patch.rs → fn create_apply_patch_json_tool() -> OpenAiTool
- Handler: same as freeform variant (ExecParams -> handle_container_exec_with_params)

exec_command + write_stdin (experimental)

- Tool JSON:
  - core/src/exec_command/responses_api.rs
    - fn create_exec_command_tool_for_responses_api() -> ResponsesApiTool
    - fn create_write_stdin_tool_for_responses_api() -> ResponsesApiTool
- Session and IO:
  - core/src/exec_command/session_manager.rs → SessionManager (manages pty/session ids)
  - core/src/codex.rs → EXEC_COMMAND_TOOL_NAME and WRITE_STDIN_TOOL_NAME branches in handle_function_call

MCP tools

- Tool JSON conversion:
  - core/src/openai_tools.rs → fn mcp_tool_to_openai_tool(fully_qualified_name: String, tool: mcp_types::Tool) -> Result<ResponsesApiTool, serde_json::Error>
- Tool calling:
  - core/src/mcp_tool_call.rs
    - async fn handle_mcp_tool_call(sess: &Session, sub_id: &str, call_id: String, server: String, tool_name: String, arguments: String, timeout: Option<Duration>) -> ResponseInputItem
    - Converts CallToolResult into FunctionCallOutputPayload via core/src/codex.rs fn convert_call_tool_result_to_function_call_output_payload

Porting Notes to Elixir (structures and builders)

Data structures (suggested typespecs)

```elixir
defmodule Codex.Tool.JsonSchema do
  @type t ::
          {:boolean, %{description: String.t() | nil}}
          | {:string, %{description: String.t() | nil}}
          | {:number, %{description: String.t() | nil}}
          | {:array, %{items: t(), description: String.t() | nil}}
          | {:object,
             %{
               properties: %{optional(String.t()) => t()},
               required: [String.t()] | nil,
               additionalProperties: boolean() | nil
             }}
end

defmodule Codex.Tool.Function do
  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          strict: boolean(),
          parameters: Codex.Tool.JsonSchema.t()
        }
  defstruct [:name, :description, strict: false, :parameters]
end

defmodule Codex.Tool.Freeform do
  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          format: %{type: String.t(), syntax: String.t(), definition: String.t()}
        }
  defstruct [:name, :description, :format]
end

defmodule Codex.Tool do
  @type t :: {:function, Codex.Tool.Function.t()} |
              {:custom, Codex.Tool.Freeform.t()} |
              :local_shell |
              :web_search
end

defmodule Codex.ResponseItem do
  @type content_item :: {:input_text, String.t()} | {:output_text, String.t()} | {:input_image, String.t()}

  @type t ::
          {:message, %{role: :user | :assistant, content: [content_item()]}}
          | {:function_call, %{name: String.t(), arguments: String.t(), call_id: String.t()}}
          | {:function_call_output, %{call_id: String.t(), output: String.t()}}
          | {:custom_tool_call, %{name: String.t(), input: String.t(), call_id: String.t()}}
          | {:custom_tool_call_output, %{call_id: String.t(), output: String.t()}}
          | {:local_shell_call, %{status: :completed | :in_progress | :incomplete, action: map(), id: String.t() | nil, call_id: String.t() | nil}}
          | {:web_search_call, %{id: String.t() | nil, action: %{type: :search, query: String.t()}}}
          | {:reasoning, %{summary: [String.t()], content: [String.t()] | nil, encrypted_content: String.t() | nil}}
end
```

Building tools (Responses vs Chat)

```elixir
defmodule Codex.Tools.Build do
  # Map Elixir structs to JSON maps for Responses API
  def responses_tools_json(tools) do
    Enum.map(tools, fn
      {:function, %Codex.Tool.Function{} = f} ->
        %{type: "function", name: f.name, description: f.description, strict: f.strict,
          parameters: schema_json(f.parameters)}
      {:custom, %Codex.Tool.Freeform{} = c} ->
        %{type: "custom", name: c.name, description: c.description, format: c.format}
      :local_shell -> %{type: "local_shell"}
      :web_search -> %{type: "web_search"}
    end)
  end

  # Map to Chat Completions tools: only functions
  def chat_tools_json(tools) do
    tools
    |> Enum.flat_map(fn
      {:function, %Codex.Tool.Function{} = f} ->
        [ %{type: "function", function: %{name: f.name, description: f.description,
             strict: f.strict, parameters: schema_json(f.parameters)}} ]
      _ -> []
    end)
  end

  defp schema_json({:boolean, m}), do: Map.merge(%{type: "boolean"}, drop_nil_desc(m))
  defp schema_json({:string, m}), do: Map.merge(%{type: "string"}, drop_nil_desc(m))
  defp schema_json({:number, m}), do: Map.merge(%{type: "number"}, drop_nil_desc(m))
  defp schema_json({:array, %{items: items} = m}), do:
    %{type: "array", items: schema_json(items)} |> Map.merge(drop_nil_desc(Map.delete(m, :items)))
  defp schema_json({:object, m}) do
    %{
      type: "object",
      properties: Map.new(m.properties, fn {k, v} -> {k, schema_json(v)} end)
    }
    |> maybe_put(:required, m[:required])
    |> maybe_put(:additionalProperties, m[:additionalProperties])
  end

  defp drop_nil_desc(m), do: if m[:description], do: %{description: m.description}, else: %{}
  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end
```

Mapping ResponseItems to Chat Completions messages

```elixir
defmodule Codex.ChatMapping do
  # returns a list of message maps
  def to_messages(instructions, items) do
    msgs = [%{role: "system", content: instructions}] ++ Enum.flat_map(items, &map_item/1)
    msgs
  end

  defp map_item({:message, %{role: role, content: content}}) do
    text = content
           |> Enum.flat_map(fn
             {:input_text, t} -> [t]
             {:output_text, t} -> [t]
             _ -> []
           end)
           |> Enum.join("")
    [%{role: Atom.to_string(role), content: text}]
  end
  defp map_item({:function_call, %{name: name, arguments: args, call_id: id}}) do
    [%{role: "assistant", content: nil,
       tool_calls: [%{id: id, type: "function", function: %{name: name, arguments: args}}]}]
  end
  defp map_item({:function_call_output, %{call_id: id, output: out}}) do
    [%{role: "tool", tool_call_id: id, content: out}]
  end
  defp map_item({:custom_tool_call, %{name: name, input: input, call_id: id}}) do
    [%{role: "assistant", content: nil,
       tool_calls: [%{id: id, type: "custom", custom: %{name: name, input: input}}]}]
  end
  defp map_item({:custom_tool_call_output, %{call_id: id, output: out}}), do: [%{role: "tool", tool_call_id: id, content: out}]
  defp map_item({:local_shell_call, %{id: id, call_id: call_id} = m}) do
    [%{role: "assistant", content: nil,
       tool_calls: [%{id: call_id || id || "", type: "local_shell_call",
                     status: Atom.to_string(m.status), action: m.action}]}]
  end
  defp map_item(_), do: []
end
```

Exec output payload formatting (string, not object)

```elixir
defmodule Codex.ExecOutput do
  @head_lines 256
  @tail_lines 128
  @max_lines  (@head_lines + @tail_lines)
  @head_bytes 48_000
  @max_bytes  64_000

  @spec format(String.t(), integer(), float()) :: String.t()
  def format(aggregated_output_text, exit_code, duration_seconds) do
    text = truncate_text(aggregated_output_text)
    payload = %{output: text, metadata: %{exit_code: exit_code, duration_seconds: duration_seconds}}
    Jason.encode!(payload) # must serialize to a JSON string and embed as plain string in FunctionCallOutput
  end

  defp truncate_text(s) do
    lines = String.split(s, "\n")
    total = length(lines)
    cond do
      byte_size(s) <= @max_bytes and total <= @max_lines -> s
      true ->
        head = Enum.take(lines, @head_lines) |> Enum.join("\n") |> take_bytes(@head_bytes)
        tail = Enum.take(lines, -@tail_lines) |> Enum.join("\n")
        omitted = total - (@head_lines + @tail_lines) |> max(0)
        marker = "\n[... omitted #{omitted} of #{total} lines ...]\n\n"
        head <> marker <> take_last_bytes(tail, @max_bytes - byte_size(head) - byte_size(marker))
    end
  end
  defp take_bytes(s, maxb) when byte_size(s) <= maxb, do: s
  defp take_bytes(s, maxb), do: :binary.part(s, {0, maxb}) |> :unicode.characters_to_list() |> to_string()
  defp take_last_bytes(s, maxb) when maxb <= 0, do: ""
  defp take_last_bytes(s, maxb) when byte_size(s) <= maxb, do: s
  defp take_last_bytes(s, maxb), do: :binary.part(s, {byte_size(s) - maxb, maxb}) |> :unicode.characters_to_list() |> to_string()
end
```

View image (file→data URL) for Responses API

```elixir
defmodule Codex.Images do
  @spec local_path_to_data_url(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def local_path_to_data_url(path) do
    with {:ok, bin} <- File.read(path) do
      mime = MIME.from_path(path) || "application/octet-stream"
      encoded = Base.encode64(bin)
      {:ok, "data:" <> mime <> ";base64," <> encoded}
    end
  end
end
```

MCP tool conversion (server__tool name + schema sanitation)

```elixir
defmodule Codex.MCP do
  @max_name 64

  def qualify_name(server, tool) do
    name = server <> "__" <> tool
    if String.length(name) <= @max_name, do: name, else: truncate_with_sha1(name)
  end

  defp truncate_with_sha1(name) do
    hash = :crypto.hash(:sha, name) |> Base.encode16(case: :lower)
    prefix_len = @max_name - String.length(hash)
    String.slice(name, 0, prefix_len) <> hash
  end

  # Minimal sanitizer to coerce to supported subset
  def sanitize_schema(value) when is_map(value) do
    type = value["type"] || infer_type(value)
    value = Map.put(value, "type", normalize_type(type))
    value =
      case value["type"] do
        "object" -> Map.put_new(value, "properties", %{})
        "array" -> Map.put_new(value, "items", %{"type" => "string"})
        _ -> value
      end
    sanitize_children(value)
  end
  def sanitize_schema(list) when is_list(list), do: Enum.map(list, &sanitize_schema/1)
  def sanitize_schema(other), do: other

  defp normalize_type([h | _]), do: normalize_type(h)
  defp normalize_type("integer"), do: "number"
  defp normalize_type(t) when t in ["object","array","string","number","boolean"], do: t
  defp normalize_type(_), do: "string"

  defp infer_type(m) do
    cond do
      Map.has_key?(m, "properties") -> "object"
      Map.has_key?(m, "items") -> "array"
      Map.has_key?(m, "enum") or Map.has_key?(m, "const") or Map.has_key?(m, "format") -> "string"
      Enum.any?(["minimum","maximum","exclusiveMinimum","exclusiveMaximum","multipleOf"], &Map.has_key?(m, &1)) -> "number"
      true -> "string"
    end
  end

  defp sanitize_children(m) do
    m
    |> Map.update("properties", %{}, fn props -> Enum.into(props, %{}, fn {k, v} -> {k, sanitize_schema(v)} end) end)
    |> Map.update("items", nil, fn v -> sanitize_schema(v) end)
    |> Map.update("oneOf", nil, &sanitize_schema/1)
    |> Map.update("anyOf", nil, &sanitize_schema/1)
    |> Map.update("allOf", nil, &sanitize_schema/1)
  end
end
```

Auth/header differences to mirror

- Responses API:
  - Headers: "OpenAI-Beta" => "responses=experimental", "session_id" => UUID, "originator" => configured string, "User-Agent" => your UA, "Authorization" => Bearer token, Accept: text/event-stream
  - If ChatGPT OAuth: add header "chatgpt-account-id"
  - Body.store: false for ChatGPT OAuth; Prompt.store for API Key
- Chat Completions API: Authorization (if provider), Accept: text/event-stream

Critical compatibility rules

- FunctionCallOutput output MUST be a plain string (the JSON-encoded payload), not an object. Sending {content, success:false} as an object will cause 400s.
- Only function tools go into Chat Completions tools; local_shell/web_search/custom are omitted.
- view_image only transmits images via Responses API (data URL input item). Do not expect image support via Chat mapping.
