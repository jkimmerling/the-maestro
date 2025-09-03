Anthropic/Claude Tooling Integration Specs (llxprt-code)

Scope: Exact request/response formatting, tool message encoding, auth differences (API key vs OAuth), streaming handling, and tool inventory as implemented in llxprt-code at source/llxprt-code.

Repository Paths Referenced
- Provider: `source/llxprt-code/packages/core/src/providers/anthropic/AnthropicProvider.ts`
- Tool formatting: `source/llxprt-code/packages/core/src/tools/ToolFormatter.ts`
- Message wrapper (parts → provider messages): `source/llxprt-code/packages/core/src/providers/adapters/GeminiCompatibleWrapper.ts`
- Non-interactive tool executor: `source/llxprt-code/packages/core/src/core/nonInteractiveToolExecutor.ts`
- Tool → functionResponse parts: `source/llxprt-code/packages/core/src/core/coreToolScheduler.ts` (convertToFunctionResponse)
- Anthropic OAuth device flow: `source/llxprt-code/packages/core/src/auth/anthropic-device-flow.ts`
- Anthropic OAuth provider (CLI): `source/llxprt-code/packages/cli/src/auth/anthropic-oauth-provider.ts`
- Tests showing exact Anthropic payloads: `source/llxprt-code/packages/core/src/providers/anthropic/AnthropicProvider.test.ts`

OpenAI Responses vs Chat (Deep Source Mapping)
- Endpoints and base URLs
  - Responses API
    - Base URL default: `https://api.openai.com/v1`
    - Endpoint: `POST /responses`
    - Code reference: `OpenAIResponsesProvider.callResponsesEndpoint` and `responsesURL = `${baseURL}/responses``
  - Chat Completions API
    - Via OpenAI SDK: `openai.chat.completions.create({...})`
    - Base URL: default OpenAI unless overridden; for Qwen OAuth the base URL may be set to `https://<resource_url>/v1`
    - Code reference: `OpenAIProvider.executeApiCall`
  - Anthropic Messages API
    - Base URL default: `https://api.anthropic.com`
    - Endpoint: `POST /v1/messages` via `@anthropic-ai/sdk` `messages.create`
    - Code reference: `AnthropicProvider.generateChatCompletion`

- Headers
  - Responses API: `Authorization: Bearer <OPENAI_API_KEY>`, `Content-Type: application/json; charset=utf-8`
    - No “ChatGPT account” header is set anywhere in llxprt-code
  - Chat Completions API (OpenAI): managed by SDK; auth is via `apiKey` set on OpenAI client
  - Anthropic (API key): SDK handles headers; no special headers added by llxprt-code
  - Anthropic (OAuth): client created with `{ authToken, defaultHeaders: { 'anthropic-beta': 'oauth-2025-04-20' } }`

- Exact request bodies
  - Responses API JSON (built in `buildResponsesRequest`):
    - Top-level: `{ model, input?: ResponsesMessage[], prompt?, tools?, stream?, previous_response_id?, store?, tool_choice?, stateful?, ...gen-params }`
    - `input` is an ordered array combining:
      - role messages: `{ role: 'user'|'assistant'|'system'|'developer', content: string, usage? }`
      - function calls: `{ type: 'function_call', call_id, name, arguments }` (arguments is a JSON string)
      - function call outputs: `{ type: 'function_call_output', call_id, output }` (output is a plain string)
    - `previous_response_id` set when a parent turn id is present; then `store: true` is also set
    - Tools array uses Responses format (see ToolFormatter.toResponsesTool)
  - Chat Completions API JSON (OpenAI):
    - `model`, `messages` (IMessage array mapped directly), `tools` (OpenAI function tools), `tool_choice`, `stream` and `stream_options` if streaming is enabled, plus model params
  - Anthropic Messages API JSON:
    - `model`, `messages` (Anthropic content blocks encoding), `max_tokens`, `tools` formatted for Anthropic, `stream` flag, and optionally `system`

- Stream event decoding
  - Responses API (Server-Sent Events): parsed in `parseResponsesStream.ts`
    - Text: `response.output_text.delta` and `response.message_content.delta` events yield `assistant` text chunks
    - O3 “reasoning JSON” detection: accumulates JSON-like deltas; when a JSON object with `reasoning` and `next_speaker` is complete, yields a `Thinking: ...` line and optionally the answer/response content; otherwise yields normal text
    - Tool calls: sequence of `response.output_item.added` (function_call), `response.function_call_arguments.delta` chunks, completion events; assembled into IMessage.tool_calls with id, name, and arguments
    - Usage: `response.completed` yields a usage-only assistant message
  - Chat Completions API (OpenAI): handled by SDK; no special reasoning attachment logic in llxprt-code
  - Anthropic Messages API (stream): see “Streaming Response Handling” section above (message_start/stop, content_block_* events)

- Store/include rules (Responses API)
  - OAuth: Not supported by this provider (API key only)
  - Store: `store: true` set only when `previous_response_id` is set (i.e., when a `parentId` is provided)
  - Include: No `include` parameter is constructed or sent anywhere in llxprt-code

- Reasoning attachment (Chat Completions)
  - None. Reasoning JSON is detected and rendered only for Responses streaming (O3 models) in `parseResponsesStream.ts`

Complete Tool Inventory and Inclusion Logic
- Native tools (name → path)
  - run_shell_command → `packages/core/src/tools/shell.ts`
  - read_file → `packages/core/src/tools/read-file.ts`
  - write_file → `packages/core/src/tools/write-file.ts`
  - replace → `packages/core/src/tools/edit.ts`
  - search_file_content → `packages/core/src/tools/grep.ts`
  - list_directory → `packages/core/src/tools/ls.ts`
  - glob → `packages/core/src/tools/glob.ts`
  - read_many_files → `packages/core/src/tools/read-many-files.ts`
  - todo_read → `packages/core/src/tools/todo-read.ts`
  - todo_write → `packages/core/src/tools/todo-write.ts`
  - todo_pause → `packages/core/src/tools/todo-pause.ts`
  - save_memory → `packages/core/src/tools/memoryTool.ts`
  - web_fetch → `packages/core/src/tools/web-fetch.ts`
  - google_web_search → `packages/core/src/tools/web-search.ts` and `web-search-invocation.ts`

- MCP tools
  - Discovered via `mcp-client.ts` and wrapped by `DiscoveredMCPTool` (`mcp-tool.ts`).
  - Registry name exposed to LLM defaults to sanitized tool name; a fully-qualified variant uses `server__tool` via `asFullyQualifiedTool()`.
  - All discovered MCP tools are exposed to providers like native tools; formatting depends on target provider (OpenAI/Anthropic formats).

- Tools appearance per provider
  - Anthropic Messages: tools converted with ToolFormatter → `{ name, description, input_schema }` array
  - OpenAI Chat Completions: tools converted to `type: 'function', function: { name, description, parameters }`
  - OpenAI Responses: tools converted to Responses tool format via `ToolFormatter.toResponsesTool()` (flattened function tool objects)
  - Gemini Server Tools: separate “server tools” concept (e.g., `web_fetch`, `web_search`) on the Gemini provider; Anthropic/OpenAI providers do not expose server tools themselves

Tool JSON Definitions (Schemas/Descriptions)
- run_shell_command (ShellTool) description text (verbatim)
  - On Unix: “This tool executes a given shell command as `bash -c <command>`. Command can start background processes using `&`. Command is executed as a subprocess that leads its own process group. Command process group can be terminated as `kill -- -PGID` or signaled as `kill -s SIGNAL -- -PGID`.

      The following information is returned:

      Command: Executed command.
      Directory: Directory (relative to project root) where command was executed, or `(root)`.
      Stdout: Output on stdout stream. Can be `(empty)` or partial on error and for any unwaited background processes.
      Stderr: Output on stderr stream. Can be `(empty)` or partial on error and for any unwaited background processes.
      Error: Error or `(none)` if no error was reported for the subprocess.
      Exit Code: Exit code or `(none)` if terminated by signal.
      Signal: Signal number or `(none)` if no signal was received.
      Background PIDs: List of background processes started or `(none)`.
      Process Group PGID: Process group started or `(none)`”
  - On Windows: equivalent text with `cmd.exe /c <command>` and `start /b` reference
  - Parameters schema: `{ command: string; description?: string; directory?: string }` with `command` required; confirmation step can escalate to “proceed always” allowlist per root command

- read_file description: reads a file, can return truncated content with explicit guidance for `offset`/`limit`; requires absolute paths and workspace checks; schema includes `absolute_path` (or `file_path` alias), `offset`, `limit`

- write_file description: writes content to an absolute path within workspace; schema includes `file_path` (or `absolute_path` alias), `content`; returns success/error strings

- Other listed native tools: see their respective files for descriptions and parameter JSON; ToolFormatter converts to provider-specific formats without altering semantics

- Not present in llxprt-code (explicitly):
  - view_image, update_plan, apply_patch, exec_command, write_stdin — these tools do not exist in the repository; there are no schemas, descriptions, or behaviors to document from source

Verbatim Schemas and Descriptions (Copied from Source)
- replace (EditTool) — `packages/core/src/tools/edit.ts`
  - Name: `replace`
  - Description: Replaces text within a file. By default, replaces a single occurrence, but can replace multiple occurrences when `expected_replacements` is specified. This tool requires providing significant context around the change to ensure precise targeting. Always use the read_file tool to examine the file's current content before attempting a text replacement. The user may modify new_string; if modified, it is stated in the response. Requirements: file_path must be absolute; old_string and new_string must be exact literal text; do not escape; include at least 3 lines of context before/after; for multiple replacements set expected_replacements. If requirements are not satisfied, tool fails.
  - Schema (parameters):
    - type: object
    - required: [file_path, old_string, new_string]
    - properties:
      - file_path: string, “The absolute path to the file to modify. Must start with '/'.”
      - old_string: string, “The exact literal text to replace… include at least 3 lines of context BEFORE and AFTER…”
      - new_string: string, “The exact literal text to replace old_string with…”
      - expected_replacements: number, minimum 1, “Number of replacements expected. Defaults to 1…”

- search_file_content (GrepTool) — `packages/core/src/tools/grep.ts`
  - Name: `search_file_content`
  - Description: “Searches for a regular expression pattern within the content of files in a specified directory… IMPORTANT: expects regex patterns, not literal strings.”
- Schema (parameters):
    - Verbatim parameters object:
      ```ts
      {
        properties: {
          pattern: {
            description:
              "The regular expression (regex) pattern to search for within file contents. Special characters like ( ) [ ] { } . * + ? ^ $ \\ | must be escaped with a backslash. Examples: 'openModelDialog\\(' to find 'openModelDialog(', 'function\\s+myFunction' to find function declarations, '\\.test\\.' to find '.test.' in filenames.",
            type: 'string',
          },
          path: {
            description:
              'Optional: The absolute path to the directory to search within. If omitted, searches the current working directory.',
            type: 'string',
          },
          include: {
            description:
              "Optional: A glob pattern to filter which files are searched (e.g., '*.js', '*.{ts,tsx}', 'src/**'). If omitted, searches all files (respecting potential global ignores).",
            type: 'string',
          },
          max_matches: {
            description:
              'Optional: Maximum number of matches to return. If omitted, uses the configured limit (default 50). Set a lower number if you expect many matches to avoid overwhelming output.',
            type: 'number',
          },
        },
        required: ['pattern'],
        type: 'object',
      }
      ```

- list_directory (LSTool) — `packages/core/src/tools/ls.ts`
  - Name: `list_directory`
  - Description: “Lists the names of files and subdirectories directly within a specified directory path. Can optionally ignore entries matching provided glob patterns.”
- Schema (parameters):
    - Verbatim parameters object:
      ```ts
      {
        properties: {
          path: {
            description:
              'The absolute path to the directory to list (must be absolute, not relative)',
            type: 'string',
          },
          ignore: {
            description: 'List of glob patterns to ignore',
            items: {
              type: 'string',
            },
            type: 'array',
          },
          file_filtering_options: {
            description:
              'Optional: Whether to respect ignore patterns from .gitignore or .llxprtignore',
            type: 'object',
            properties: {
              respect_git_ignore: {
                description:
                  'Optional: Whether to respect .gitignore patterns when listing files. Only available in git repositories. Defaults to true.',
                type: 'boolean',
              },
              respect_llxprt_ignore: {
                description:
                  'Optional: Whether to respect .llxprtignore patterns when listing files. Defaults to true.',
                type: 'boolean',
              },
            },
          },
        },
        required: ['path'],
        type: 'object',
      }
      ```

- glob (GlobTool) — `packages/core/src/tools/glob.ts`
  - Name: `glob`
  - Description: Select files matching a glob pattern across workspace directories, supporting case sensitivity and git ignore filtering.
- Schema (parameters):
    - Verbatim parameters object:
      ```ts
      {
        properties: {
          pattern: {
            description:
              "The glob pattern to match against (e.g., '**/*.py', 'docs/*.md').",
            type: 'string',
          },
          path: {
            description:
              'Optional: The absolute path to the directory to search within. If omitted, searches the root directory.',
            type: 'string',
          },
          case_sensitive: {
            description:
              'Optional: Whether the search should be case-sensitive. Defaults to false.',
            type: 'boolean',
          },
          respect_git_ignore: {
            description:
              'Optional: Whether to respect .gitignore patterns when finding files. Only available in git repositories. Defaults to true.',
            type: 'boolean',
          },
          max_files: {
            description:
              'Optional: Maximum number of files to return. If omitted, returns all matching files up to system limits. Set a lower number if you expect many matches to avoid overwhelming output.',
            type: 'number',
          },
        },
        required: ['pattern'],
        type: 'object',
      }
      ```

- read_many_files — `packages/core/src/tools/read-many-files.ts`
  - Name: `read_many_files`
  - Description: Concatenates multiple files’ content with separators; supports include/exclude patterns and defaults to ignore common/binary paths; can respect .gitignore and .llxprtignore.
- Schema (parameters):
    - Verbatim parameters object:
      ```ts
      {
        type: 'object',
        properties: {
          paths: {
            type: 'array',
            items: { type: 'string', minLength: 1 },
            minItems: 1,
            description: "Required. An array of glob patterns or paths relative to the tool's target directory. Examples: ['src/**/*.ts'], ['README.md', 'docs/']",
          },
          include: {
            type: 'array',
            items: { type: 'string', minLength: 1 },
            description: 'Optional. Additional glob patterns to include. These are merged with `paths`. Example: "*.test.ts" to specifically add test files if they were broadly excluded.',
            default: [],
          },
          exclude: {
            type: 'array',
            items: { type: 'string', minLength: 1 },
            description: 'Optional. Glob patterns for files/directories to exclude. Added to default excludes if useDefaultExcludes is true. Example: "**/*.log", "temp/"',
            default: [],
          },
          recursive: {
            type: 'boolean',
            description: 'Optional. Whether to search recursively (primarily controlled by `**` in glob patterns). Defaults to true.',
            default: true,
          },
          useDefaultExcludes: {
            type: 'boolean',
            description: 'Optional. Whether to apply a list of default exclusion patterns (e.g., node_modules, .git, binary files). Defaults to true.',
            default: true,
          },
          file_filtering_options: {
            description: 'Whether to respect ignore patterns from .gitignore or .llxprtignore',
            type: 'object',
            properties: {
              respect_git_ignore: {
                description: 'Optional: Whether to respect .gitignore patterns when listing files. Only available in git repositories. Defaults to true.',
                type: 'boolean',
              },
              respect_llxprt_ignore: {
                description: 'Optional: Whether to respect .llxprtignore patterns when listing files. Defaults to true.',
                type: 'boolean',
              },
            },
          },
        },
        required: ['paths'],
      }
      ```

- todo_read — `packages/core/src/tools/todo-read.ts`
  - Name: `todo_read`
  - Description: “Read the current todo list for the session. Returns all todos with their status, priority, and content.”
- Schema (parameters):
    - Verbatim parameters object:
      ```ts
      {
        type: Type.OBJECT,
        properties: {},
      }
      ```

- todo_write — `packages/core/src/tools/todo-write.ts`
  - Name: `todo_write`
  - Description: “Create and manage a structured task list for the current coding session. Updates the entire todo list.”
- Schema (parameters):
    - Verbatim parameters object:
      ```ts
      {
        type: Type.OBJECT,
        properties: {
          todos: {
            type: Type.ARRAY,
            items: {
              type: Type.OBJECT,
              properties: {
                id: { type: Type.STRING, description: 'Unique identifier for the todo item' },
                content: { type: Type.STRING, description: 'Description of the todo item', minLength: '1' },
                status: { type: Type.STRING, enum: ['pending', 'in_progress', 'completed'], description: 'Current status of the todo item' },
                priority: { type: Type.STRING, enum: ['high', 'medium', 'low'], description: 'Priority level of the todo item' },
                subtasks: {
                  type: Type.ARRAY,
                  items: {
                    type: Type.OBJECT,
                    properties: {
                      id: { type: Type.STRING, description: 'Unique identifier for the subtask' },
                      content: { type: Type.STRING, description: 'Description of the subtask', minLength: '1' },
                      toolCalls: {
                        type: Type.ARRAY,
                        items: {
                          type: Type.OBJECT,
                          properties: {
                            id: { type: Type.STRING, description: 'Unique identifier for the tool call' },
                            name: { type: Type.STRING, description: 'Name of the tool being called' },
                            parameters: { type: Type.OBJECT, description: 'Parameters for the tool call' },
                          },
                          required: ['id', 'name', 'parameters'],
                        },
                        description: 'Tool calls associated with the subtask',
                      },
                    },
                    required: ['id', 'content'],
                  },
                  description: 'Subtasks associated with this todo',
                },
              },
              required: ['id', 'content', 'status', 'priority'],
            },
            description: 'The updated todo list',
          },
        },
        required: ['todos'],
      }
      ```

- todo_pause — `packages/core/src/tools/todo-pause.ts`
  - Name: `todo_pause`
  - Description: “Pause the current todo continuation when encountering errors or blockers… Reason should clearly explain the issue.”
  - Schema (parameters):
    - type: OBJECT
    - required: ['reason']
    - properties:
      - reason: STRING, minLength '1', maxLength '500'

— read_file — `packages/core/src/tools/read-file.ts`
- Name: `read_file`
- Description: Reads and returns the content of a specified file. Handles text, images (PNG, JPG, GIF, WEBP, SVG, BMP), and PDF files. For large files, returns a truncated view with explicit instructions to continue reading using `offset`/`limit`. Absolute path and workspace boundary checks enforced.
- Schema (parameters; verbatim structure):
  - type: 'object'
  - properties:
    - absolute_path: { type: 'string', description: "The absolute path to the file to read (e.g., '/home/user/project/file.txt'). Relative paths are not supported. You must provide an absolute path." }
    - offset: { type: 'number', description: "Optional: For text files, the 0-based line number to start reading from. Requires 'limit' to be set. Use for paginating through large files." }
    - limit: { type: 'number', description: "Optional: For text files, maximum number of lines to read. Use with 'offset' to paginate through large files. If omitted, reads the entire file (if feasible, up to a default limit)." }
  - required: ['absolute_path']
  - requireOne: [['absolute_path', 'file_path']] // Accept either absolute_path or file_path

— write_file — `packages/core/src/tools/write-file.ts`
- Name: `write_file`
- Description: Writes content to a specified file in the local filesystem. Absolute path required and must be within workspace boundaries. Errors include permission denied, no space left, and target is directory; includes specific error codes when applicable.
- Schema (parameters; verbatim structure):
  - type: 'object'
  - properties:
    - file_path: { type: 'string', description: "The absolute path to the file to write to (e.g., '/home/user/project/file.txt'). Relative paths are not supported." }
    - content: { type: 'string', description: 'The content to write to the file.' }
  - required: ['file_path', 'content']
  - requireOne: [['file_path', 'absolute_path']] // Accept either file_path or absolute_path

Concrete tool_result content examples (as sent to Anthropic)
- run_shell_command
  - tool_result.content (string):
    - Example: `Command: ls -la\nDirectory: (root)\nOutput: <stdout or (empty)>\nError: (none)\nExit Code: 0\nSignal: (none)\nBackground PIDs: (none)\nProcess Group PGID: 12345`
- read_file
  - Untruncated: full file text as a single string
  - Truncated: prefixed status block with next-offset guidance followed by content
- write_file
  - On success: “Wrote N bytes to …” or generic success line (per implementation), else error message including codes like EACCES/ENOSPC/EISDIR
- replace
  - On success: Summary string including file path, replacement counts, and optional <system-reminder> if emojis were filtered; on error: “Error executing edit: …”
- search_file_content
  - String with lines like: `path/file.ts:123: matched line text`
- list_directory
  - String listing entries, possibly followed by counts like “(3 git-ignored, 2 llxprt-ignored)”
- glob
  - String listing matched paths; ordering prioritizes recent files, then alphabetical
- read_many_files
  - Concatenated text with separators `--- path ---`; binary files summarized when needed
- todo_read / todo_write / todo_pause
  - Markdown summaries or short status lines as per implementations

End-to-End Examples (Anthropic)
- Example: user → assistant tool_use → tool_result → assistant
  - Tools: `[{ name: "run_shell_command", description: "Shell", input_schema: { type: "object", properties: { command: { type: "string" }, description: { type: "string" }, directory: { type: "string" } }, required: ["command"] } }]`
  - Messages array (createOptions.messages) just before `messages.create` when assistant decides to call a tool:
    - `[
         { role: "user", content: "List files" },
         { role: "assistant", content: [
             { type: "text", text: "Working on it..." },
             { type: "tool_use", id: "call_123", name: "run_shell_command", input: { "command": "ls -la" } }
           ] }
       ]`
  - After tool executes, the tool response is inserted into the next request as a user message with a tool_result block:
    - `{ role: "user", content: [ { type: "tool_result", tool_use_id: "call_123", content: "Command: ls -la\nDirectory: (root)\nOutput: ..." } ] }`

End-to-End Examples (OpenAI Responses)
- Tools: `[{ type: 'function', name: 'run_shell_command', description: 'Shell', parameters: { type: 'object', properties: { command: { type: 'string' }, description: { type: 'string' }, directory: { type: 'string' } }, required: ['command'] }, strict: null }]`
- Input sequence:
  - `{ role: 'user', content: 'List files' }`
  - `{ type: 'function_call', call_id: 'call_123', name: 'run_shell_command', arguments: '{"command":"ls -la"}' }`
  - After tool executes: `{ type: 'function_call_output', call_id: 'call_123', output: 'Command: ls -la\nDirectory: (root)\nOutput: ...' }`

Full Transcripts and Test-Copied Payloads
- Anthropic (from unit tests in `AnthropicProvider.test.ts`)
  - Simple streaming call (no tools): expected call body
    - `{
         model: "claude-sonnet-4-20250514",
         messages: [ { role: "user", content: "Say hello" } ],
         max_tokens: 64000,
         stream: true
       }`
  - With tools provided and tool call in stream: expected call body
    - `{
         model: "claude-sonnet-4-20250514",
         messages: [ { role: "user", content: "What is the weather?" } ],
         max_tokens: 64000,
         stream: true,
         tools: [
           {
             name: "get_weather",
             description: "Get the weather",
             input_schema: { type: "object", properties: {} }
           }
         ]
       }`
  - Streaming events (tool_use → input_json_delta → stop → text)
    - `{"type":"content_block_start","content_block":{"type":"tool_use","id":"tool-123","name":"get_weather"}}`
    - `{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"location\":\"San Francisco\"}"}}`
    - `{"type":"content_block_stop"}`
    - `{"type":"content_block_delta","delta":{"type":"text_delta","text":"Result"}}`

- OpenAI Responses (from `parseResponsesStream.responsesToolCalls.test.ts`)
  - Function call with streamed arguments:
    - SSE lines (verbatim):
      - `data: {"type":"response.output_item.added","sequence_number":1,"output_index":0,"item":{"id":"fc_456","type":"function_call","status":"in_progress","arguments":"","call_id":"call_def456","name":"search_products"}}\n\n`
      - `event: response.function_call_arguments.delta\n`
      - `data: {"type":"response.function_call_arguments.delta","sequence_number":2,"item_id":"fc_456","output_index":0,"delta":"{\\"query\\":"}\n\n`
      - `data: {"type":"response.function_call_arguments.delta","sequence_number":3,"item_id":"fc_456","output_index":0,"delta":"\\"laptop\\","}\n\n`
      - `data: {"type":"response.function_call_arguments.delta","sequence_number":4,"item_id":"fc_456","output_index":0,"delta":"\\"max_price\\":"}\n\n`
      - `data: {"type":"response.function_call_arguments.delta","sequence_number":5,"item_id":"fc_456","output_index":0,"delta":"1500}"}\n\n`
      - `data: {"type":"response.output_item.done","sequence_number":6,"output_index":0,"item":{"id":"fc_456","type":"function_call","status":"completed","arguments":"{\\"query\\":\\"laptop\\",\\"max_price\\":1500}","call_id":"call_def456","name":"search_products"}}\n\n`
  - Usage emitted on completion:
    - `data: {"type":"response.completed","sequence_number":4,"response":{"id":"resp_123","object":"response","model":"o3","status":"completed","usage":{"input_tokens":62,"output_tokens":23,"total_tokens":85}}}\n\n`

Fully Expanded Anthropic OAuth Example (First Turn Injection)
- System field when using OAuth: `"You are Claude Code, Anthropic's official CLI for Claude."`
- Messages injected (only when this is the very first request and a system prompt exists on the app side):
  - First message (user):
    - Content (verbatim prefix from provider):
      ```text
      Important context for using llxprt tools:

      Tool Parameter Reference:
      - read_file uses parameter 'absolute_path' (not 'file_path')
      - write_file uses parameter 'file_path' (not 'path')
      - list_directory uses parameter 'path'
      - replace uses 'file_path', 'old_string', 'new_string'
      - search_file_content (grep) expects regex patterns, not literal text
      - todo_write requires 'todos' array with {id, content, status, priority}
      - All file paths must be absolute (starting with /)

      <LLXPRT_PROMPTS_HERE>
      ```
  - Second message (assistant):
    - Content (verbatim):
      ```text
      I understand the llxprt tool parameters and context. I'll use the correct parameter names for each tool. Ready to help with your tasks.
      ```

- Example full request (first turn, OAuth):
  ```json
  {
    "model": "claude-sonnet-4-20250514",
    "system": "You are Claude Code, Anthropic's official CLI for Claude.",
    "messages": [
      { "role": "user", "content": "Important context for using llxprt tools:\n\nTool Parameter Reference:\n- read_file uses parameter 'absolute_path' (not 'file_path')\n- write_file uses parameter 'file_path' (not 'path')\n- list_directory uses parameter 'path'\n- replace uses 'file_path', 'old_string', 'new_string'\n- search_file_content (grep) expects regex patterns, not literal text\n- todo_write requires 'todos' array with {id, content, status, priority}\n- All file paths must be absolute (starting with /)\n\nMy llxprt prompts: <LLXPRT_PROMPTS_HERE>" },
      { "role": "assistant", "content": "I understand the llxprt tool parameters and context. I'll use the correct parameter names for each tool. Ready to help with your tasks." },
      { "role": "user", "content": "Please list the files in the project root." }
    ],
    "tools": [
      {
        "name": "run_shell_command",
        "description": "Shell",
        "input_schema": {
          "type": "object",
          "properties": {
            "command": { "type": "string", "description": "Exact bash command to execute as `bash -c <command>`" },
            "description": { "type": "string", "description": "Brief description of the command for the user. Be specific and concise. Ideally a single sentence. Can be up to 3 sentences for clarity. No line breaks." },
            "directory": { "type": "string", "description": "(OPTIONAL) Directory to run the command in, if not the project root directory. Must be relative to the project root directory and must already exist." }
          },
          "required": ["command"]
        }
      }
    ],
    "max_tokens": 64000,
    "stream": true
  }
  ```

Note: With OAuth, the HTTP headers must include `Authorization: Bearer <sk-ant-oat...>` and `anthropic-beta: oauth-2025-04-20`. When posting directly (not via SDK), also include `anthropic-version: 2023-06-01` and `Content-Type: application/json`.

Elixir Sample Modules and Tests
- Anthropic tool and message builders (sample)
  - `lib/llxprt/anthropic_builder.ex`
    - ```elixir
      defmodule LLXPRT.AnthropicBuilder do
        @moduledoc false

        @spec tool(%{name: String.t(), description: String.t() | nil, schema: map()}) :: map()
        def tool(%{name: name, description: desc, schema: schema}) do
          %{
            name: name,
            description: desc || "",
            input_schema: Map.merge(%{type: "object"}, schema)
          }
        end

        @spec message(%{role: atom(), content: String.t(), tool_calls: list() | nil, tool_call_id: String.t() | nil}) :: map()
        def message(%{role: :system, content: content}), do: {:system, content}

        def message(%{role: :tool, content: content, tool_call_id: id}) when is_binary(id) do
          %{
            role: "user",
            content: [ %{type: "tool_result", tool_use_id: id, content: content} ]
          }
        end

        def message(%{role: :assistant, content: content, tool_calls: calls}) when is_list(calls) do
          blocks =
            []
            |> then(fn acc -> if content != "", do: acc ++ [%{type: "text", text: content}], else: acc end)
            |> Kernel.++(Enum.map(calls, &tool_use_block/1))

          %{role: "assistant", content: blocks}
        end

        def message(%{role: :assistant, content: content}), do: %{role: "assistant", content: content}
        def message(%{role: :user, content: content}), do: %{role: "user", content: content}

        defp tool_use_block(%{id: id, function: %{name: name, arguments: args}}) do
          input = if args && args != "", do: Jason.decode!(args), else: %{}
          %{type: "tool_use", id: id, name: name, input: input}
        end
      end
      ```

- Responses input builder (sample)
  - `lib/llxprt/responses_builder.ex`
    - ```elixir
      defmodule LLXPRT.ResponsesBuilder do
        @moduledoc false
        @type msg :: %{role: atom(), content: String.t(), tool_calls: list() | nil, tool_call_id: String.t() | nil}

        @spec build_input([msg]) :: [map()]
        def build_input(messages) do
          {role_msgs, calls, outputs} =
            Enum.reduce(messages, {[], [], []}, fn m, {rm, cs, os} ->
              cond do
                m[:role] == :assistant and is_list(m[:tool_calls]) ->
                  new_calls = Enum.map(m.tool_calls, fn tc ->
                    %{
                      type: "function_call",
                      call_id: tc.id,
                      name: tc.function.name,
                      arguments: tc.function.arguments
                    }
                  end)
                  {rm, cs ++ new_calls, os}

                m[:role] == :tool and is_binary(m[:tool_call_id]) and m[:content] ->
                  new_out = %{
                    type: "function_call_output",
                    call_id: m.tool_call_id,
                    output: m.content
                  }
                  {rm, cs, os ++ [new_out]}

                true ->
                  r = %{role: role_str(m.role), content: m.content}
                  {rm ++ [r], cs, os}
              end
            end)

          role_msgs ++ calls ++ outputs
        end

        defp role_str(:user), do: "user"
        defp role_str(:assistant), do: "assistant"
        defp role_str(:system), do: "system"
        defp role_str(:developer), do: "developer"
      end
      ```

- Unit tests (sample)
  - `test/llxprt/anthropic_builder_test.exs`
    - ```elixir
      defmodule LLXPRT.AnthropicBuilderTest do
        use ExUnit.Case

        test "tool mapping" do
          tool = %{name: "get_weather", description: "Get the weather", schema: %{properties: %{}, required: []}}
          out = LLXPRT.AnthropicBuilder.tool(tool)
          assert out.name == "get_weather"
          assert out.input_schema.type == "object"
        end

        test "assistant with tool_calls -> tool_use blocks" do
          calls = [ %{id: "call_1", function: %{name: "run_shell_command", arguments: ~s/{\"command\":\"ls\"}/}} ]
          msg = %{role: :assistant, content: "", tool_calls: calls}
          out = LLXPRT.AnthropicBuilder.message(msg)
          assert out.role == "assistant"
          [tool_use] = Enum.filter(out.content, &(&1.type == "tool_use"))
          assert tool_use.id == "call_1"
          assert tool_use.name == "run_shell_command"
          assert tool_use.input["command"] == "ls"
        end

        test "tool message -> user tool_result" do
          msg = %{role: :tool, content: "OK", tool_call_id: "call_1"}
          out = LLXPRT.AnthropicBuilder.message(msg)
          assert out.role == "user"
          [%{type: "tool_result", tool_use_id: id, content: content}] = out.content
          assert id == "call_1"
          assert content == "OK"
        end
      end
      ```

  - `test/llxprt/responses_builder_test.exs`
    - ```elixir
      defmodule LLXPRT.ResponsesBuilderTest do
        use ExUnit.Case

        test "builds input array with role messages, function calls and outputs" do
          msgs = [
            %{role: :user, content: "List files"},
            %{role: :assistant, content: "", tool_calls: [
              %{id: "call_123", function: %{name: "run_shell_command", arguments: ~s/{\"command\":\"ls -la\"}/}}
            ]},
            %{role: :tool, content: "Command: ls -la", tool_call_id: "call_123"}
          ]

          input = LLXPRT.ResponsesBuilder.build_input(msgs)
          assert Enum.at(input, 0) == %{role: "user", content: "List files"}
          assert Enum.at(input, 1).type == "function_call"
          assert Enum.at(input, 2) == %{type: "function_call_output", call_id: "call_123", output: "Command: ls -la"}
        end
      end
      ```

Remaining Edge Cases and Behaviors
- Model parameter merging (Anthropic): `createOptions` includes `...this.modelParams` before `stream`; caller-set params merge last via `setModelParams`, with precedence over defaults
- Latest model resolution (Anthropic):
  - If model ends with `-latest`, provider resolves to a concrete model using cached `getModels()` results within a 5-minute TTL; if fetch fails, falls back to `'opus'` or `'sonnet'`
- OAuth nuances (Anthropic):
  - OAuth tokens start with `sk-ant-oat`; in this mode, `system` is forced to Claude Code string and llxprt system prompt is injected as first-turn user+assistant messages; models.list not used (static list returned)


Exact Return Payloads (Tool → LLM)
- General rule: tool execution returns a `ToolResult` with an `llmContent` string (or Part list for binary), which is wrapped into a Gemini `functionResponse` Part by `convertToFunctionResponse(toolName, callId, llmContent)`
  - If `llmContent` is string or array of strings: emitted as `functionResponse.response.output: string`
  - If `llmContent` contains binary Part(s): `functionResponse.response = { output: "Binary content of type <mime> was processed.", binaryContent: <Part> }`
  - When converted to Anthropic request, only a text `tool_result.content` is sent (binary not forwarded)
- OpenAI Responses “function_call_output” construction:
  - Built from tool messages: `{ type: 'function_call_output', call_id, output: <sanitized string> }`
  - No metadata fields are attached in llxprt-code (no `exit_code` or `duration_seconds` in the Responses payload)
- web_search: returns a textual result and an internal `sources` array; the text is what is sent back to the model as tool output; there is no “UI-only events” path in llxprt-code
- view_image: not present; no return behavior to document

MCP Integration Details
- Tool naming
  - Base tool name sanitization (`generateValidName`): replace invalid chars with `_`; cap length at 63 chars by middle-compacting with `___`
  - Fully-qualified variant: `server__tool` via `DiscoveredMCPTool.asFullyQualifiedTool()`
  - There is no SHA-1 suffix in llxprt-code; the code does not append hashes
- Schema sanitation
  - ToolFormatter.convertGeminiSchemaToStandard: recursively lowercases `type`, converts nested `properties` and `items`
  - GeminiCompatibleWrapper.convertGeminiSchemaToStandard: extends sanitation to handle `oneOf`, `items` (tuple arrays), `properties`, `additionalProperties` (recursive), `patternProperties`, `dependencies`, and `if/then/else/not`
  - No integer→number coercion beyond lowercasing of type strings; types remain as provided (e.g., “integer” remains “integer”)

Non‑Streaming Anthropic Example (text‑only and with tool_use)
- Request (non-streaming; stream omitted or set to false):
  ```json
  {
    "model": "claude-sonnet-4-20250514",
    "system": "<optional system>",
    "messages": [ { "role": "user", "content": "Generate two lines of greeting." } ],
    "max_tokens": 64000
  }
  ```
- Example response (text-only):
  ```json
  {
    "id": "msg_01A...",
    "type": "message",
    "role": "assistant",
    "model": "claude-sonnet-4-20250514",
    "content": [ { "type": "text", "text": "Hello there!\nHi!" } ],
    "stop_reason": "end_turn",
    "usage": { "input_tokens": 123, "output_tokens": 10 }
  }
  ```
- Example response (with tool_use and then text in a single reply):
  ```json
  {
    "role": "assistant",
    "content": [
      { "type": "tool_use", "id": "call_abc", "name": "run_shell_command", "input": { "command": "ls -la" } },
      { "type": "text", "text": "Listed files above." }
    ],
    "usage": { "input_tokens": 200, "output_tokens": 30 }
  }
  ```
- llxprt mapping to internal IMessage for non-streaming:
  - Aggregates all `text` items into a single `content` string.
  - Converts each `tool_use` to a tool_call entry: `[{ id, type: 'function', function: { name, arguments: JSON.stringify(input) } }]`.
  - Emits usage as `{prompt_tokens, completion_tokens, total_tokens}`.

Streamed OpenAI Responses: full transcript (interleaving text & tool calls)
- SSE event lines (from tests) showing text first, then a function call:
  ```
  data: {"type":"response.output_text.delta","delta":"Let me search for that..."}
  
  data: {"type":"response.output_item.added","sequence_number":2,"output_index":1,"item":{"id":"fc_search","type":"function_call","status":"in_progress","arguments":"","call_id":"call_search","name":"search"}}
  data: {"type":"response.function_call_arguments.delta","sequence_number":3,"item_id":"fc_search","output_index":1,"delta":"{\"query\":\"test\"}"}
  data: {"type":"response.output_item.done","sequence_number":4,"output_index":1,"item":{"id":"fc_search","type":"function_call","status":"completed","arguments":"{\"query\":\"test\"}","call_id":"call_search","name":"search"}}
  ```
- llxprt-assembled messages from this stream:
  - `{ role: 'assistant', content: 'Let me search for that...' }`
  - `{ role: 'assistant', content: '', tool_calls: [{ id: 'call_search', type: 'function', function: { name: 'search', arguments: '{"query":"test"}' } }] }`

Elixir SSE Handler for OpenAI Responses (minimal parser)
- Lightweight parser to consume SSE lines and emit internal messages (assistant text chunks, tool_calls, usage):
  ```elixir
  defmodule Llxprt.OpenAI.ResponsesSSE do
    @moduledoc """
    Minimal SSE event parser for OpenAI Responses API.
    Feed raw chunks via feed/2; it returns {new_state, emitted_messages}.
    """

    defstruct buffer: "", calls: %{}
    @type t :: %__MODULE__{buffer: binary(), calls: map()}

    @doc """
    Feed a binary chunk. Returns {state, messages_to_emit}.
    """
    def feed(%__MODULE__{} = state, chunk) when is_binary(chunk) do
      buffer = state.buffer <> chunk
      {lines, rest} = split_lines(buffer)
      {new_state, emitted} = Enum.reduce(lines, {state, []}, &handle_line/2)
      {%{new_state | buffer: rest}, Enum.reverse(emitted)}
    end

    defp split_lines(buffer) do
      parts = String.split(buffer, "\n")
      {Enum.drop(parts, -1), List.last(parts) || ""}
    end

    defp handle_line(line, {state, acc}) do
      line = String.trim(line)
      cond do
        line == "" or String.starts_with?(line, "event:") -> {state, acc}
        String.starts_with?(line, "data: ") ->
          data = String.replace_prefix(line, "data: ", "")
          case Jason.decode(data) do
            {:ok, %{"type" => type} = evt} -> dispatch_event(type, evt, state, acc)
            _ -> {state, acc}
          end
        true -> {state, acc}
      end
    end

    # Text deltas
    defp dispatch_event("response.output_text.delta", %{"delta" => delta}, state, acc) when is_binary(delta) do
      msg = %{role: :assistant, content: delta}
      {state, [msg | acc]}
    end
    defp dispatch_event("response.message_content.delta", %{"delta" => delta}, state, acc) when is_binary(delta) do
      msg = %{role: :assistant, content: delta}
      {state, [msg | acc]}
    end

    # Function call lifecycle
    defp dispatch_event("response.output_item.added", %{"item" => %{"type" => "function_call"} = item}, state, acc) do
      id = item["id"]
      call_id = item["call_id"] || id
      name = item["name"]
      calls = Map.put(state.calls, id, %{id: call_id, name: name, arguments: ""})
      {%{state | calls: calls}, acc}
    end
    defp dispatch_event("response.function_call_arguments.delta", %{"item_id" => item_id, "delta" => delta}, state, acc) do
      calls = Map.update(state.calls, item_id, %{id: item_id, name: nil, arguments: delta}, fn c -> %{c | arguments: (c.arguments || "") <> delta} end)
      {%{state | calls: calls}, acc}
    end
    defp dispatch_event("response.output_item.done", %{"item" => %{"type" => "function_call", "id" => item_id} = item}, state, acc) do
      call = Map.get(state.calls, item_id, %{id: item_id, name: item["name"], arguments: item["arguments"] || ""})
      tool_calls = [ %{id: call.id, type: "function", function: %{name: call.name || item["name"], arguments: call.arguments}} ]
      msg = %{role: :assistant, content: "", tool_calls: tool_calls}
      calls = Map.delete(state.calls, item_id)
      {%{state | calls: calls}, [msg | acc]}
    end

    # Usage
    defp dispatch_event("response.completed", %{"response" => %{"usage" => usage}}, state, acc) do
      msg = %{role: :assistant, content: "", usage: %{
        prompt_tokens: usage["input_tokens"] || 0,
        completion_tokens: usage["output_tokens"] || 0,
        total_tokens: usage["total_tokens"] || 0
      }}
      {state, [msg | acc]}
    end

    defp dispatch_event(_type, _evt, state, acc), do: {state, acc}
  end
  ```

Integrating the SSE Handler With Mint (recommended)
- Minimal Mint wiring that drives the SSE parser on incoming chunks:
  ```elixir
  defmodule Llxprt.OpenAI.StreamRunner do
    @moduledoc false
    alias Llxprt.OpenAI.ResponsesSSE

    @endpoint "api.openai.com"

    def stream_responses(request_map, api_key) do
      {:ok, conn} = Mint.HTTP.connect(:https, @endpoint, 443)
      headers = [
        {"authorization", "Bearer " <> api_key},
        {"content-type", "application/json; charset=utf-8"},
        {"accept", "text/event-stream"}
      ]
      body = Jason.encode!(request_map)

      {:ok, conn, req_ref} = Mint.HTTP.request(conn, "POST", "/v1/responses", headers, body)
      loop(conn, req_ref, %ResponsesSSE{})
    end

    defp loop(conn, req_ref, state) do
      receive do
        message ->
          case Mint.HTTP.stream(conn, message) do
            {:ok, conn, responses} ->
              {state, emitted} = Enum.reduce(responses, {state, []}, fn
                {:status, ^req_ref, _}, acc -> acc
                {:headers, ^req_ref, _}, acc -> acc
                {:data, ^req_ref, chunk}, {st, em} ->
                  {nst, msgs} = ResponsesSSE.feed(st, chunk)
                  {nst, em ++ msgs}
                {:done, ^req_ref}, {st, em} ->
                  IO.inspect(em, label: "final emitted")
                  {st, em}
                _, acc -> acc
              end)
              # handle emitted messages here
              Enum.each(emitted, &IO.inspect/1)
              loop(conn, req_ref, state)
            {:error, _conn, reason, _responses} -> {:error, reason}
            :unknown -> loop(conn, req_ref, state)
          end
      after
        30_000 -> {:error, :timeout}
      end
    end
  end
  ```

Non‑Streaming OpenAI Chat Example (with tools)
- Request (no streaming) to `/v1/chat/completions`:
  ```json
  {
    "model": "gpt-5",
    "messages": [
      { "role": "user", "content": "List files in the repo." },
      { "role": "assistant", "content": "", "tool_calls": [
        { "id": "call_123", "type": "function", "function": { "name": "run_shell_command", "arguments": "{\"command\":\"ls -la\"}" } }
      ] }
    ],
    "tools": [
      { "type": "function", "function": { "name": "run_shell_command", "description": "Shell", "parameters": {
        "type": "object",
        "properties": { "command": { "type": "string" }, "description": { "type": "string" }, "directory": { "type": "string" } },
        "required": ["command"]
      } } }
    ]
  }
  ```
- Typical response:
  ```json
  {
    "id": "chatcmpl-...",
    "object": "chat.completion",
    "model": "gpt-5",
    "choices": [
      { "index": 0, "finish_reason": "tool_calls", "message": {
        "role": "assistant",
        "content": "",
        "tool_calls": [
          { "id": "call_123", "type": "function", "function": { "name": "run_shell_command", "arguments": "{\"command\":\"ls -la\"}" } }
        ]
      } }
    ],
    "usage": { "prompt_tokens": 120, "completion_tokens": 10, "total_tokens": 130 }
  }
  ```
- Mapping to internal messages:
  - Assistant tool_calls become `{id, type: 'function', function: {name, arguments}}`.
  - After tool executes locally, send a tool message in the next turn to Chat API with `role: 'tool', content: <string>, tool_call_id: <id>`.



Conversation and Prompt Construction
- System instructions
  - Composed by `PromptService`: concatenates core prompt, environment-specific prompts, and tool prompts from a prompt directory (~/.llxprt/prompts). There is no “conditional apply_patch instructions” logic in llxprt-code.
- Environment context
  - Generated via `getEnvironmentContext(config)`: a text Part summarizing date, OS, workspace directories, and folder structure; if full context is enabled, appends content from `read_many_files` tool
  - The format is plain text, not an XML block
- History compaction
  - OpenAI Responses: `buildResponsesRequest` may slice history to preserve coherent tool call/response pairs when stateful mode is used
  - Anthropic: before each call, `validateAndFixMessages` injects synthetic tool responses for any pending tool calls

Concrete Examples
- Full Responses shell turn (tools, input, function_call, function_call_output)
  - Tools:
    - `[{ type: 'function', name: 'run_shell_command', description: 'Shell', parameters: { type: 'object', properties: { command: { type: 'string' }, description: { type: 'string' }, directory: { type: 'string' } }, required: ['command'] }, strict: null }]`
  - Input array (abbrev.):
    - `[{ role: 'user', content: 'List files' }, { type: 'function_call', call_id: 'call_123', name: 'run_shell_command', arguments: '{"command":"ls -la"}' } ... { type: 'function_call_output', call_id: 'call_123', output: 'Command: ls -la\nDirectory: (root)\nOutput: ...' }]`
  - POST https://api.openai.com/v1/responses with Authorization + JSON body as built in `buildResponsesRequest`

- Full Chat Completions shell turn (OpenAI)
  - Request body:
    - `{ model: 'gpt-5', messages: [ { role: 'user', content: 'List files' }, { role: 'assistant', content: '', tool_calls: [ { id: 'call_123', type: 'function', function: { name: 'run_shell_command', arguments: '{"command":"ls -la"}' } } ] } ], tools: [ { type: 'function', function: { name: 'run_shell_command', description: 'Shell', parameters: { ... } } } ], stream: true, stream_options: { include_usage: true } }`
  - Streaming is handled by OpenAI SDK; llxprt-code later yields tool_calls and text deltas; no “reasoning” attachment here

Elixir Porting Notes (Ready-to-use)
- Types and structs
  - Define `t:tool/0` with name, description, and JSON Schema map
  - Define `t:message/0` for roles: `:system | :user | :assistant | :tool` and fields `content :: String.t()`, optional `tool_calls`, `tool_call_id`, and `usage`
  - Define `t:function_call/0` and `t:function_call_output/0` matching Responses API shapes

- Builders
  - Responses tools builder: map native/MCP tools to `%{type: "function", name, description: description || nil, parameters: schema, strict: nil}`
  - Chat tools builder: map to OpenAI or Anthropic formats; for Anthropic: `%{name, description: description || "", input_schema: Map.merge(%{type: "object"}, schema)}`
  - Chat messages encoder (Anthropic): implement the same mapping as in AnthropicProvider:
    - system (API key) → request.system
    - OAuth → inject 2-message preface and set `system` to Claude Code string
    - tool (role) → user message with `tool_result` block
    - assistant with tool_calls → assistant message with `text` + `tool_use` blocks
    - plain text user/assistant → role + content string
  - Example Elixir structs (suggested):
    - `defmodule Tool do
         @type t :: %__MODULE__{name :: String.t(), description :: String.t() | nil, schema :: map()}
         defstruct [:name, :description, :schema]
       end`
    - `defmodule Message do
         @type role :: :system | :user | :assistant | :tool
         @type t :: %__MODULE__{role :: role, content :: String.t(), tool_calls :: list() | nil, tool_call_id :: String.t() | nil, usage :: map() | nil}
         defstruct [:role, :content, :tool_calls, :tool_call_id, :usage]
       end`
    - `defmodule FunctionCall do
         @type t :: %__MODULE__{id :: String.t(), name :: String.t(), arguments :: String.t()}
         defstruct [:id, :name, :arguments]
       end`
    - `defmodule FunctionCallOutput do
         @type t :: %__MODULE__{call_id :: String.t(), output :: String.t()}
         defstruct [:call_id, :output]
       end`

  - Responses builder outline:
    - Assemble `input` as `[%{role: r, content: c} | %{type: "function_call", ...} | %{type: "function_call_output", ...}]` preserving order
    - Add `previous_response_id` and `store: true` only when `parent_id` present
    - Map tools via Responses format (flattened function tool)

  - Chat builder outline:
    - OpenAI: build `%{model, messages, tools, tool_choice, stream, stream_options}`
    - Anthropic: build `%{model, messages: anthropic_blocks, tools: anthropic_tools, max_tokens, system?, stream}`

  - Headers builder:
    - Responses: `[{"Authorization", "Bearer " <> api_key}, {"Content-Type", "application/json; charset=utf-8"}]`
    - Anthropic (OAuth): set auth token; add header `{"anthropic-beta", "oauth-2025-04-20"}`

  - Images helper:
    - Read file bytes; Base64 encode; produce `%{inlineData: %{mimeType: "image/png", data: base64}}` for Gemini
    - For Anthropic tool_result, summarize to text only

  - MCP tools:
    - Qualified name `server <> "__" <> tool`, sanitize with `Regex.replace(~r/[^A-Za-z0-9_.-]/, name, "_")`; if >63 chars, compact middle to maintain suffix/prefix

  - Sanitization (Responses input):
    - Ensure output strings don’t contain U+FFFD; replace or strip as in `ensureJsonSafe`

- Exec payload formatter
  - Mirror `ShellToolInvocation.execute` text summary; include command, directory, stdout/stderr content, error, exit code, signal, background PIDs, PGID

- Images to data URL helper
  - Base64 encode binary file to `inlineData` with mimeType; for Anthropic, strip to text summary when creating `tool_result`

- MCP helpers
  - Name qualification: `"#{server}__#{tool}"`; apply sanitization and length cap to 63 chars with middle-compaction
  - Schema sanitation: recursively lower-case types; handle properties/items/oneOf/additionalProperties/patternProperties/dependencies/if/then/else/not

- Request builders
  - Responses: construct `input` with role messages + function_call + function_call_output entries; set `previous_response_id` and `store: true` iff `parent_id` present; attach tools in Responses format
  - Chat (OpenAI): build body with model, messages, tools, tool_choice, stream flags
  - Anthropic: build body with model, messages (Anthropic blocks), tools (Anthropic), max_tokens, system per auth mode, stream flag

- Headers
  - Responses: `Authorization: Bearer <API_KEY>`, `Content-Type: application/json; charset=utf-8`
  - Chat (OpenAI): SDK handles; pass `apiKey`
  - Anthropic: SDK handles; for OAuth set `authToken` and `defaultHeaders['anthropic-beta'] = 'oauth-2025-04-20'`

- Responses input encoder
  - Encode input as JSON array preserving order: role messages first, then any function_call items, then function_call_output items
  - Ensure tool outputs are strings; sanitize any replacement chars before encoding


Provider Call: messages.create (Exact Options)
- SDK used: `@anthropic-ai/sdk`
- Method: `this.anthropic.messages.create(options)`
- Constructed options object (exact fields set by llxprt-code):
  - `model`: Resolved model id (latest aliases resolved when needed)
  - `messages`: Array of objects with `role` and `content` (see Message Encoding below)
  - `max_tokens`: Computed via `getMaxTokensForModel(model)`
  - `stream`: Boolean (on/off based on ephemeral setting)
  - `system`: Present only when applicable (see Auth/System Prompt rules)
  - `tools`: Present only if tools are provided (converted to Anthropic schema)
- Reference (construction): AnthropicProvider.ts lines around createOptions

Auth Differences (API Key vs OAuth)
- API Key:
  - Client init: `new Anthropic({ apiKey, baseURL?, dangerouslyAllowBrowser: true })`
  - No special default headers are added by llxprt-code.
  - Model list: Uses `anthropic.beta.models.list()` to enumerate models.
  - System prompt: If there’s a system message in user history, it is sent as `system`.
- OAuth:
  - Access token value format detected by prefix: tokens start with `sk-ant-oat`.
  - Client init: `new Anthropic({ authToken, baseURL?, dangerouslyAllowBrowser: true, defaultHeaders: { 'anthropic-beta': 'oauth-2025-04-20' } })`
  - Model list: Does not call API; returns a fixed set in code (Sonnet 4 and Opus 4.1) due to API limitations with OAuth.
  - System prompt forced: `system = "You are Claude Code, Anthropic's official CLI for Claude."`
  - llxprt system prompts are injected as conversation content (first turn only): the provider prepends two messages before the user’s first message:
    1) `user` message with “Important context for using llxprt tools: … Tool Parameter Reference …” plus the original llxprt prompt
    2) `assistant` ack message: “I understand the llxprt tool parameters and context. …”
  - Reference: AnthropicProvider.ts `updateClientWithResolvedAuth`, OAuth logic for `system` and prompt injection

Exact injected context text (first-turn OAuth only):
- User injected message content begins with (verbatim):
  - `Important context for using llxprt tools:\n\nTool Parameter Reference:\n- read_file uses parameter 'absolute_path' (not 'file_path')\n- write_file uses parameter 'file_path' (not 'path')\n- list_directory uses parameter 'path'\n- replace uses 'file_path', 'old_string', 'new_string'\n- search_file_content (grep) expects regex patterns, not literal text\n- todo_write requires 'todos' array with {id, content, status, priority}\n- All file paths must be absolute (starting with /)\n\n<LLXPRT_PROMPTS_HERE>`
- Followed by assistant injected ack (verbatim):
  - `I understand the llxprt tool parameters and context. I'll use the correct parameter names for each tool. Ready to help with your tasks.`

Message Encoding (To Anthropic)
- Internal neutral message type: `IMessage` (role: 'user' | 'assistant' | 'system' | 'tool')
- Anthropic payload message array is constructed with the following exact mappings:
  1) System messages:
     - API key: Extracted once and set into `createOptions.system = <string>`
     - OAuth: Not sent as `system`; instead stored and (on first turn only) injected as a `user` context message (see above)
  2) Tool result messages (internal role: 'tool'):
     - Converted to Anthropic “tool_result” blocks wrapped inside a `user` message:
       - `{ role: 'user', content: [{ type: 'tool_result', tool_use_id: <tool_call_id>, content: <string> }] }`
     - The `<string>` content is derived from the tool’s functionResponse (see Tool Results → FunctionResponse mapping)
  3) Assistant messages that contain tool calls (IMessage.tool_calls array):
     - Transformed to an `assistant` message with a content array including optional leading text and one or more tool_use blocks:
       - Content entries:
         - Optional: `{ type: 'text', text: <assistant_text> }` if present
         - For each tool call: `{ type: 'tool_use', id: <id>, name: <function.name>, input: <parsed JSON of function.arguments> }`
  4) Plain user/assistant text messages:
     - `{ role: 'user' | 'assistant', content: <string> }`
  5) Parts (binary, images, etc.):
     - Not sent to Anthropic. The wrapper only attaches `parts` for Gemini provider. Anthropic receives string content only.

Tools Definition (Anthropic Schema Conversion)
- Input `ITool[]` (OpenAI/Gemini-like) is converted to Anthropic schema by ToolFormatter:
  - For each tool: `{ name, description, input_schema: { type: 'object', ...parameters } }`
- Reference: ToolFormatter.ts case 'anthropic'

Streaming Response Handling (Anthropic → llxprt)
- Streaming type: `Stream<Anthropic.MessageStreamEvent>` from `@anthropic-ai/sdk/streaming`
- Events processed exactly as follows:
  - `message_start`: If `usage` present, yield an assistant message with empty content and a `usage` payload (prompt/completion/total tokens)
  - `content_block_start`: If `content_block.type === 'tool_use'`, begin accumulating current tool call: `{ id, name, input: '' }`
  - `content_block_delta`: Either
    - `text_delta`: yield `{ role: 'assistant', content: <delta.text> }`
    - `input_json_delta` (only when inside an active tool_use): append `partial_json` to current tool call’s `input` string buffer
  - `content_block_stop`: If a tool_use block just ended, parse the accumulated `input` JSON and yield a single assistant message with `tool_calls` array converted to the neutral format:
    - `[{ id, type: 'function', function: { name, arguments: JSON.stringify(parsed_input) } }]`
  - `message_delta`: If `usage` present, merge usage and yield a usage-only assistant message (empty content)
  - `message_stop`: If usage tracked, yield final usage-only assistant message (empty content)
- Reference: AnthropicProvider.ts streaming loop

Context Editing / Consistency Fixups
- To prevent Anthropic errors (“tool_use ids were found without tool_result blocks”), the provider validates the message history before each API call.
- If it finds assistant messages with `tool_calls` not followed by matching tool results, it injects synthetic tool response messages before the next non-system message:
  - `{ role: 'tool', tool_call_id: <id>, content: 'Error: Tool execution was interrupted. Please retry.' }`
- These synthetic tool messages then encode to Anthropic as `user` messages with a `tool_result` block during request construction.
- Reference: AnthropicProvider.ts `validateAndFixMessages`

Exact Payload Examples (From Tests)
- Simple streaming call without tools:
  - Request:
    - `{ model: 'claude-sonnet-4-20250514', messages: [{ role: 'user', content: 'Say hello' }], max_tokens: 64000, stream: true }`
  - Source: AnthropicProvider.test.ts “should stream content…” assertion
- With tools and tool use emitted by model (stream):
  - Request includes tools array:
    - `tools: [{ name: 'get_weather', description: 'Get the weather', input_schema: { type: 'object', properties: {} } }]`
  - Response handling emits tool_calls after reconstructing `input_json_delta` and on `content_block_stop`.
  - Source: AnthropicProvider.test.ts “should handle tool calls in the stream”

Concrete Request/Message Construction Examples (Anthropic)
- Example 1: User asks a question; tools provided
  - Input (neutral llxprt messages):
    - `[{ role: 'user', content: 'What is the weather?' }]`
    - Tools: one tool named `get_weather` with empty parameters
  - Final request to Anthropic:
    - `{
         model: "claude-sonnet-4-20250514",
         messages: [
           { role: "user", content: "What is the weather?" }
         ],
         max_tokens: 64000,
         stream: true,
         tools: [
           {
             name: "get_weather",
             description: "Get the weather",
             input_schema: { type: "object", properties: {} }
           }
         ]
       }`
- Example 2: Tool result insertion
  - Input (neutral llxprt messages) contains a tool response:
    - `[{ role: 'tool', tool_call_id: 'tool_123', content: '{"temp":72}' }]`
  - Final request message constructed for Anthropic:
    - `{
         role: "user",
         content: [
           { type: "tool_result", tool_use_id: "tool_123", content: "{\"temp\":72}" }
         ]
       }`
- Example 3: Assistant message that includes a tool call
  - Input (neutral llxprt assistant with tool_calls):
    - `{
         role: 'assistant',
         content: "Working on it...",
         tool_calls: [
           {
             id: "call_001",
             type: "function",
             function: { name: "get_weather", arguments: "{\"location\":\"SF\"}" }
           }
         ]
       }`
  - Final request message constructed for Anthropic:
    - `{
         role: "assistant",
         content: [
           { type: "text", text: "Working on it..." },
           { type: "tool_use", id: "call_001", name: "get_weather", input: { "location": "SF" } }
         ]
       }`


System Prompt Behavior (When Tools Are Used)
- Tools themselves do not change the system prompt.
- Differences stem from auth mode:
  - API key: If the conversation includes a system message, it is sent via the `system` field on the request.
  - OAuth: The `system` is hard-coded to Claude Code line; llxprt prompt(s) are injected as user/assistant conversation content on the first turn.

Tool Results → What Is Sent Back To The LLM (Anthropic)
- Tools produce a `ToolResult` that llxprt wraps as a Gemini `functionResponse` Part via `convertToFunctionResponse(name, id, llmContent)`.
- The wrapper (`GeminiCompatibleWrapper`) converts these Parts into provider messages:
  - For each functionResponse Part → a provider message `{ role: 'tool', content: <derived-string>, tool_call_id: <id> }`
  - “Derived string” precedence:
    - If `response.binaryContent` present: content = `response.output` or the string “Processed binary content” (binary parts are collected but NOT included for Anthropic)
    - Else if `response` is string: content = that string
    - Else if `response.error`: content = `Error: <message>`
    - Else if `response.llmContent`: stringify
    - Else if `response.output`: stringify
    - Else: `JSON.stringify(response)`
- AnthropicRequest encoding for that tool response:
  - `{ role: 'user', content: [{ type: 'tool_result', tool_use_id: <id>, content: <derived-string> }] }`
  - Images/binary from tool responses are not attached to Anthropic requests (text only). The “binary” summary is what Anthropic sees.

Tools: Inventory and Source Paths (Initial Pass)
- `run_shell_command` — `source/llxprt-code/packages/core/src/tools/shell.ts`
  - Returns: String summary with command, directory, output, error, exit code, signal, PIDs. May be summarized/limited. Provided back as the tool_result `content` string.
- `read_file` — `source/llxprt-code/packages/core/src/tools/read-file.ts`
  - Returns: File content as string. If truncated, a prefixed status block explains how to paginate with `offset`/`limit`.
- `write_file` — `source/llxprt-code/packages/core/src/tools/write-file.ts`
  - Returns: Success or detailed error message as string. In debug mode or via UI, structured diff stats appear in metadata, but Anthropic only receives text in tool_result.
- `replace` — `source/llxprt-code/packages/core/src/tools/edit.ts`
  - Returns: Edit summary or error message string. For large edits, diff stats recorded in metadata; Anthropic receives the textual result.
- `search_file_content` — `source/llxprt-code/packages/core/src/tools/grep.ts`
  - Returns: Matched lines (string) with file/line number context depending on options.
- `list_directory` — `source/llxprt-code/packages/core/src/tools/ls.ts`
  - Returns: Directory listing (string) with metadata depending on options.
- `glob` — `source/llxprt-code/packages/core/src/tools/glob.ts`
  - Returns: Matched file paths as string list (text-only for Anthropic).
- `read_many_files` — `source/llxprt-code/packages/core/src/tools/read-many-files.ts`
  - Returns: Concatenated summaries/contents (string), possibly truncated per file with guidance.
- `todo_read` — `source/llxprt-code/packages/core/src/tools/todo-read.ts`
  - Returns: Current TODO entries (stringified summary). See schema in file.
- `todo_write` — `source/llxprt-code/packages/core/src/tools/todo-write.ts`
  - Returns: Confirmation/summary of written TODO items as string.
- `todo_pause` — `source/llxprt-code/packages/core/src/tools/todo-pause.ts`
  - Returns: Pause acknowledgement or validation error (string).
- `save_memory` — `source/llxprt-code/packages/core/src/tools/memoryTool.ts`
  - Returns: JSON string with `{ success: boolean, message?: string, error?: string }`. Anthropic receives this JSON as the tool_result `content` string.
- `web_fetch` — `source/llxprt-code/packages/core/src/tools/web-fetch.ts`
  - Returns: Text summarization of fetched content, with optional “Sources:” section. Private URLs fall back to raw text extraction.
- `google_web_search` — `source/llxprt-code/packages/core/src/tools/web-search.ts`
  - Returns: Text summary with links/citations as string.

Notes on Images/Binary in Tool Returns
- If a tool produces a binary `Part` (e.g., an image via `inlineData`/`fileData` Parts), `convertToFunctionResponse` wraps it in a functionResponse with a special `binaryContent` field and an `output` string like “Binary content of type <mime> was processed.”
- The wrapper only attaches such Parts to Gemini requests; Anthropic receives only the `output` text summarized in the `tool_result.content` field.

Model Selection and max_tokens
- Latest aliases are optionally resolved by inspecting cached/queried model lists. On failure, falls back to tier names (e.g., 'sonnet').
- `max_tokens` defaults by model id pattern:
  - Claude 4 Sonnet: 64000
  - Claude 4 Opus: 32000
  - Others: pattern-matched; fallback 4096
- Reference: AnthropicProvider.ts `getMaxTokensForModel`

Open Questions / Next Iteration Targets
- Expand each tool’s “Returns” with concrete example payloads (from tests/runs)
- Confirm any Anthropic content block support beyond text/tool_use/tool_result for images if later added
- Capture any per-tool parameter normalization edge cases relevant to Elixir translation
Minimal Elixir HTTP Clients (Req-based)
- Anthropic Messages client (API key and OAuth)
  ```elixir
  defmodule Llxprt.Anthropic.Client do
    @moduledoc """
    Minimal client for Anthropic /v1/messages using Req.
    Supports API key (x-api-key) and OAuth Bearer with oauth beta header.
    """
    @base_url "https://api.anthropic.com/v1"

    @spec headers(%{mode: :api_key, key: String.t()} | %{mode: :oauth, token: String.t()}) :: [{String.t(), String.t()}]
    def headers(%{mode: :api_key, key: key}) do
      [
        {"x-api-key", key},
        {"anthropic-version", "2023-06-01"},
        {"content-type", "application/json"}
      ]
    end

    def headers(%{mode: :oauth, token: token}) do
      [
        {"authorization", "Bearer " <> token},
        {"anthropic-version", "2023-06-01"},
        {"anthropic-beta", "oauth-2025-04-20"},
        {"content-type", "application/json"}
      ]
    end

    @spec post_messages(map(), keyword()) :: {:ok, map()} | {:error, term()}
    def post_messages(body_map, opts) do
      auth = Keyword.fetch!(opts, :auth)
      headers = headers(auth)

      req = Req.new(base_url: @base_url, headers: headers)
      case Req.post(req, url: "/messages", json: body_map) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end
  ```

- OpenAI Responses client
  ```elixir
  defmodule Llxprt.OpenAI.ResponsesClient do
    @moduledoc false
    @base_url "https://api.openai.com/v1"

    @spec headers(String.t()) :: [{String.t(), String.t()}]
    def headers(api_key) do
      [
        {"authorization", "Bearer " <> api_key},
        {"content-type", "application/json; charset=utf-8"}
      ]
    end

    @spec create(map(), String.t()) :: {:ok, map()} | {:error, term()}
    def create(request_map, api_key) do
      req = Req.new(base_url: @base_url, headers: headers(api_key))
      case Req.post(req, url: "/responses", json: request_map) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end
  ```

- OpenAI Chat Completions client
  ```elixir
  defmodule Llxprt.OpenAI.ChatClient do
    @moduledoc false
    @base_url "https://api.openai.com/v1"

    def headers(api_key) do
      [
        {"authorization", "Bearer " <> api_key},
        {"content-type", "application/json"}
      ]
    end

    @spec create(map(), String.t()) :: {:ok, map()} | {:error, term()}
    def create(request_map, api_key) do
      req = Req.new(base_url: @base_url, headers: headers(api_key))
      case Req.post(req, url: "/chat/completions", json: request_map) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end
  ```

- Example usage wiring
  ```elixir
  # Anthropic OAuth first-turn call
  body = %{
    "model" => "claude-sonnet-4-20250514",
    "system" => "You are Claude Code, Anthropic's official CLI for Claude.",
    "messages" => [%{"role" => "user", "content" => "Important context..."}, %{"role" => "assistant", "content" => "I understand..."}, %{"role" => "user", "content" => "List files"}],
    "tools" => [%{"name" => "run_shell_command", "description" => "Shell", "input_schema" => %{"type" => "object", "properties" => %{"command" => %{"type" => "string"}}, "required" => ["command"]}}],
    "max_tokens" => 64000,
    "stream" => true
  }
  {:ok, resp} = Llxprt.Anthropic.Client.post_messages(body, auth: %{mode: :oauth, token: System.fetch_env!("ANTHROPIC_OAUTH_TOKEN")})

  # OpenAI Responses stateless call
  req = %{"model" => "o3-mini", "input" => [%{"role" => "user", "content" => "List files"}], "tools" => [%{"type" => "function", "name" => "run_shell_command", "parameters" => %{"type" => "object", "properties" => %{"command" => %{"type" => "string"}}, "required" => ["command"]}}]}
  {:ok, resp} = Llxprt.OpenAI.ResponsesClient.create(req, System.fetch_env!("OPENAI_API_KEY"))
  ```
