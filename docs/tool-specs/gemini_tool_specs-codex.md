Gemini CLI Tooling: Exact Call/Message Specs (Work‑In‑Progress)

Status: initial pass. This file will be expanded iteratively with more tools and wire examples.

Scope

- Exact on‑wire structure Gemini CLI uses for tool calling, tool results, and chat history mutations.
- Differences between API Key/Vertex vs OAuth (Code Assist) paths.
- Concrete JSON examples and file/identifier paths to the source.
- First batch of tools fully specified; remaining tools will be added in follow‑ups.

Architecture Overview

- Core flow:
  - Model tools (aka function declarations) are gathered from the tool registry and provided to the model in `generationConfig.tools`.
  - When the model emits a `functionCall`, the CLI schedules and executes the corresponding tool.
  - Tool results are converted into Gemini `functionResponse` parts, then appended to the conversation as a new user message before the next model call.

- Key files:
  - Tool registry and types: `packages/core/src/tools/tool-registry.ts`, `packages/core/src/tools/tools.ts`
  - Tool scheduler: `packages/core/src/core/coreToolScheduler.ts`
  - Chat wrapper: `packages/core/src/core/geminiChat.ts`
  - Turn loop and tool call extraction: `packages/core/src/core/turn.ts`
  - Client lifecycle and where tools are attached: `packages/core/src/core/client.ts`
  - OAuth (Code Assist) transport: `packages/core/src/code_assist/server.ts`, `packages/core/src/code_assist/converter.ts`
  - API Key/Vertex transport: `packages/core/src/core/contentGenerator.ts`, `packages/core/src/core/loggingContentGenerator.ts`

Where Tools Are Declared and Exposed to the Model

- The model receives tools via `generationConfig.tools` as a single element array with `functionDeclarations`:

  - Source: `packages/core/src/core/client.ts`
    - `setTools()` and `startChat()` build:

      ```ts
      const toolDeclarations = toolRegistry.getFunctionDeclarations();
      const tools: Tool[] = [{ functionDeclarations: toolDeclarations }];
      this.getChat().setTools(tools);
      // or included directly in the initial generation config in startChat()
      ```

- Each tool implements `DeclarativeTool` and exposes a `schema: FunctionDeclaration` derived from its `parameterSchema`:

  - Source: `packages/core/src/tools/tools.ts` (class `DeclarativeTool`)
  - The `schema` that goes to the model:

    ```ts
    get schema(): FunctionDeclaration {
      return {
        name: this.name,
        description: this.description,
        parametersJsonSchema: this.parameterSchema,
      };
    }
    ```

Exact Request Payloads to the Model

- Non‑streaming/streaming share the same request shape. The CLI constructs:

  - `model`: string, from config
  - `contents`: full curated history plus the current user prompt
  - `config` (aka `generationConfig`): includes `systemInstruction`, `tools` (declarations), `thinkingConfig`, etc.

- For API key / Vertex (using `@google/genai`):

  - Source of call: `packages/core/src/core/geminiChat.ts`
    - Non‑streaming:

      ```ts
      this.contentGenerator.generateContent(
        {
          model: modelToUse,
          contents: requestContents, // Content[]
          config: { ...this.generationConfig, ...params.config },
        },
        prompt_id,
      )
      ```

    - Streaming:

      ```ts
      this.contentGenerator.generateContentStream(
        {
          model: modelToUse,
          contents: requestContents,
          config: { ...this.generationConfig, ...params.config },
        },
        prompt_id,
      )
      ```

  - For API key/Vertex the underlying transport is `GoogleGenAI.models` (see `packages/core/src/core/contentGenerator.ts`). The CLI passes the typed `GenerateContentParameters` directly; the `@google/genai` SDK serializes the on‑wire JSON.

- For OAuth (Code Assist) flow:

  - Calls go to `cloudcode-pa.googleapis.com/v1internal:{method}` with OAuth bearer managed by `google-auth-library`:
    - Source: `packages/core/src/code_assist/server.ts`
    - Non‑streaming (POST body):

      ```json
      {
        "model": "<model-name>",
        "project": "<gcp-project-id>",
        "user_prompt_id": "<prompt-id>",
        "request": {
          "contents": [
            { "role": "user", "parts": [ { "text": "..." } ] },
            { "role": "model", "parts": [ { "text": "..." } ] },
            { "role": "user", "parts": [ { "text": "current prompt" } ] }
          ],
          "systemInstruction": { "text": "<system prompt>" },
          "cachedContent": null,
          "tools": [ { "functionDeclarations": [ { "name": "read_file", "description": "...", "parametersJsonSchema": { "type": "object", "properties": {"absolute_path": {"type": "string"}}, "required": ["absolute_path"] } }, { "name": "write_file" } ] } ],
          "toolConfig": null,
          "labels": null,
          "safetySettings": null,
          "generationConfig": {
            "temperature": 0,
            "topP": 1,
            "thinkingConfig": { "thinkingBudget": -1, "includeThoughts": true }
          },
          "session_id": "<session-id>"
        }
      }
      ```

    - Streaming uses the same body with `?alt=sse` and yields SSE lines `data: {json}\n\n`. JSON chunks map back to `GenerateContentResponse` via the converter (`packages/core/src/code_assist/converter.ts`).

How Tool Calls Are Emitted by the Model and Captured

- The model emits tool calls as parts with `functionCall` inside the `GenerateContentResponse` candidate.
- Extraction:
  - Source: `packages/core/src/utils/generateContentResponseUtilities.ts` and `packages/core/src/core/turn.ts`
  - `Turn.run()` checks `resp.functionCalls` and yields `ToolCallRequest` events with:

    ```ts
    interface ToolCallRequestInfo {
      callId: string; // from FunctionCall.id or generated
      name: string;   // FunctionCall.name
      args: Record<string, unknown>; // FunctionCall.args
      isClientInitiated: boolean;    // false for model-initiated
      prompt_id: string;             // tracking
    }
    ```

Executing Tools and Sending Results Back to the Model

- Scheduling/execution:
  - Source: `packages/core/src/core/coreToolScheduler.ts`
  - For each scheduled call, the tool’s `ToolInvocation.execute()` returns a `ToolResult`:

    ```ts
    interface ToolResult {
      llmContent: PartListUnion;      // what goes back to the LLM
      returnDisplay: string | FileDiff;// concise UI display or diff payload
      error?: { message: string; type?: ToolErrorType };
    }
    ```

- Conversion into a `functionResponse` part:
  - Source: `convertToFunctionResponse()` in `coreToolScheduler.ts`
  - Rules:
    - If `llmContent` is a string ⇒ one `functionResponse` part with `{ response: { output: "<string>" } }`.
    - If `llmContent` is Part[] ⇒ prepend one `functionResponse` part with `{ response: { output: "Tool execution succeeded." } }` then append the provided parts as-is (e.g., text, `inlineData`, etc.).
    - If `llmContent` is a single Part object:
      - If that part already is a `functionResponse`, it is passed through after extracting embedded content (if present) into text.
      - If it’s `inlineData`/`fileData`, emit a `functionResponse` with a short status and include the binary part.

- Exact `functionResponse` structure:

  ```json
  {
    "functionResponse": {
      "id": "<tool-call-id>",
      "name": "<tool-name>",
      "response": { "output": "<string>" }
    }
  }
  ```

- How results are injected into the next request:
  - Results are appended to the chat history as a new `Content` authored by `user`:

    ```json
    {
      "role": "user",
      "parts": [
        { "functionResponse": { "id": "fc1", "name": "read_file", "response": { "output": "<summary>" } } },
        { "text": "…" },
        { "inlineData": { "mimeType": "image/png", "data": "<base64>" } }
      ]
    }
    ```

Binary/Image Returns: Exact Format

- Tools that return binary (images, PDFs, audio, video) produce `llmContent` with an `inlineData` part.
  - Source: `packages/core/src/utils/fileUtils.ts` (`processSingleFileContent`)
  - Example for an image returned by `read_file`:

    ```json
    {
      "functionResponse": {
        "id": "fc-img-1",
        "name": "read_file",
        "response": { "output": "Binary content of type image/png was processed." }
      }
    },
    {
      "inlineData": {
        "mimeType": "image/png",
        "data": "<base64-bytes>"
      }
    }
    ```

System Prompt and Context Handling

- System prompt:
  - Set once when starting chat using `getCoreSystemPrompt(userMemory)`.
  - Source: `packages/core/src/core/prompts.ts`; applied in `client.startChat()`.
  - Does not dynamically change just because tools are used.

- Context:
  - History is curated to remove invalid model chunks and to deduplicate AFC history (`geminiChat.ts`).
  - IDE and directory context are injected as user messages before the first turn (`client.ts`).
  - Tool responses are added as user messages containing the `functionResponse` part plus any additional parts.

Auth Paths: API Key/Vertex vs OAuth (Code Assist)

- Common high‑level shape (model, contents, generation config with tools).

- API Key / Vertex (`@google/genai`):
  - Source: `packages/core/src/core/contentGenerator.ts`
  - Constructed request is the typed `GenerateContentParameters` object passed into the SDK. The SDK performs the HTTP serialization.
  - Headers: `User-Agent: GeminiCLI/<version>`; optionally `x-gemini-api-privileged-user-id` when usage stats enabled.

- OAuth (Code Assist):
  - Source: `packages/core/src/code_assist/server.ts`, `packages/core/src/code_assist/converter.ts`
  - Non‑streaming: POST to `https://cloudcode-pa.googleapis.com/v1internal:generateContent` with the JSON body shown above.
  - Streaming: POST to `…:streamGenerateContent?alt=sse`; parse `data: {json}` lines.
  - Converter maps the standard `GenerateContentParameters` to the Code Assist wire shape (notably `model`, `project`, `user_prompt_id`, `request.*`).

Built‑In Tools (Batch 1)

- read_file
  - Source: `packages/core/src/tools/read-file.ts`
  - Parameters: `{ absolute_path: string; offset?: number; limit?: number }`
  - Returns:
    - Text files: `llmContent: string` (possibly truncated; message includes line range and next `offset` guidance).
    - Images/PDF/Audio/Video: `llmContent: { inlineData: { mimeType, data(base64) } }`.
    - Error shapes populate `error` and `returnDisplay`.

- write_file
  - Source: `packages/core/src/tools/write-file.ts`
  - Parameters: `{ file_path: string; content: string }`
  - Returns:
    - `llmContent: string` success message; `returnDisplay: { fileDiff, fileName, originalContent, newContent, diffStat }`.
    - Errors set `error` with specific `ToolErrorType`.

- replace (simple text edit)
  - Source: `packages/core/src/tools/edit.ts`
  - Parameters: `{ file_path: string; old_string: string; new_string: string; expected_replacements?: number }`
  - Returns: success message + `returnDisplay` diff payload as above. Errors encode mismatch/no‑occurrence conditions.

- smart_edit (context‑aware edit with instruction)
  - Source: `packages/core/src/tools/smart-edit.ts`
  - Parameters: `{ file_path: string; instruction: string; old_string: string; new_string: string }`
  - Returns: success message + `returnDisplay` diff payload.

- list_directory
  - Source: `packages/core/src/tools/ls.ts`
  - Parameters: `{ path: string; ignore?: string[]; file_filtering_options?: { respect_git_ignore?: boolean; respect_gemini_ignore?: boolean } }`
  - Returns: `llmContent: string` directory listing; succinct `returnDisplay`.

- glob
  - Source: `packages/core/src/tools/glob.ts`
  - Parameters: `{ pattern: string; path?: string; case_sensitive?: boolean; respect_git_ignore?: boolean }`
  - Returns: `llmContent: string` with matched absolute paths.

- search_file_content (grep and ripgrep variants)
  - Grep: `packages/core/src/tools/grep.ts`
  - RipGrep: `packages/core/src/tools/ripGrep.ts`
  - Parameters: `{ pattern: string; path?: string; include?: string }`
  - Returns: `llmContent: string` with grouped matches by file and line numbers.

- read_many_files
  - Source: `packages/core/src/tools/read-many-files.ts`
  - Parameters: `{ paths: string[]; include?: string[]; exclude?: string[]; useDefaultExcludes?: boolean; file_filtering_options?: { … } }`
  - Returns: `llmContent: PartListUnion` where text concatenations are separated by `--- {filePath} ---`; may include `inlineData` parts for explicitly requested binary files.

- run_shell_command
  - Source: `packages/core/src/tools/shell.ts`
  - Parameters: `{ command: string; description?: string; directory?: string }`
  - Returns: `llmContent: string` with Command/Directory/Output/Error/Exit Code/Signal/Background PIDs/PGID; streaming updates via scheduler’s `updateOutput`.

- web_fetch
  - Source: `packages/core/src/tools/web-fetch.ts`
  - Parameters: `{ prompt: string }` (URLs + instructions inline)
  - Returns: `llmContent: string` summarizing fetched content or fallback path. Uses either Gemini URL tooling (`{ tools: [{ urlContext: {} }] }`) or a local fetch fallback which then calls the model with the raw page text.

- google_web_search
  - Source: `packages/core/src/tools/web-search.ts`
  - Parameters: `{ query: string }`
  - Returns: `llmContent: string` with results; adds inline numeric citation markers and a Sources section derived from `groundingMetadata`.

- save_memory
  - Source: `packages/core/src/tools/memoryTool.ts`
  - Parameters: `{ fact: string }`
  - Returns: JSON string success or error; writes into `~/.gemini/GEMINI.md` under `## Gemini Added Memories`.

Tool Result → functionResponse: End‑to‑End Example

- Model calls `read_file`:

  ```json
  // From model (response chunk)
  {
    "candidates": [
      {
        "content": {
          "role": "model",
          "parts": [
            {
              "functionCall": {
                "id": "fc1",
                "name": "read_file",
                "args": { "absolute_path": "/abs/path/diagram.png" }
              }
            }
          ]
        }
      }
    ]
  }
  ```

- Scheduler executes the tool and injects the result as a new user message for the next turn:

  ```json
  {
    "role": "user",
    "parts": [
      {
        "functionResponse": {
          "id": "fc1",
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

Notes and Next Steps

- Remaining tools to document in detail in the next iteration: `edit.ts` vs `smart-edit.ts` deeper diff stats; `web-search` vs `web-fetch` grounding metadata fields; MCP tool bridging (`packages/core/src/tools/mcp-*.ts`) with exact Part[] transforms; full telemetry fields for tool decisions.
- Will add complete request/response samples for API Key/Vertex (`@google/genai`) on‑wire JSON shape using SDK‑equivalent structures and any observed HTTP headers.


Deep Source Mapping: Endpoints, Headers, Streaming

- OAuth (Code Assist) Transport
  - Base URL: `https://cloudcode-pa.googleapis.com`
  - API version: `v1internal`
  - Methods:
    - Non‑streaming: `POST /v1internal:generateContent`
    - Streaming: `POST /v1internal:streamGenerateContent?alt=sse`
    - Count tokens: `POST /v1internal:countTokens`
  - Headers (explicit in client code):
    - `Content-Type: application/json`
    - `User-Agent: GeminiCLI/<version> (<platform>; <arch>)`
    - Authorization: added by google-auth-library (OAuth bearer)
    - Optional proxy via undici ProxyAgent (set at process level if configured)
  - Streaming event decoding (SSE):
    - Each line with prefix `data: ` is buffered.
    - Blank line denotes end of current JSON object block.
    - Non‑`data: ` lines are an error. See `packages/core/src/code_assist/server.ts` `requestStreamingPost()`.

- API Key / Vertex via `@google/genai`
  - The CLI constructs typed `GenerateContentParameters` objects and passes them directly to `GoogleGenAI.models`.
  - Endpoints are resolved internally by the SDK (not hardcoded in this repo). The CLI cannot directly show HTTP endpoints.
  - Headers set by CLI before SDK invocation:
    - `User-Agent: GeminiCLI/<version> (<platform>; <arch>)`
    - Optional: `x-gemini-api-privileged-user-id: <installation-id>` when usage stats are enabled.
  - Vertex toggled by `vertexai: true`; when false, uses Gemini API (API key path). Both are mediated by the SDK.

- Request bodies
  - Shared typed shape (both transports):
    - `{ model, contents, config }` passed into `generateContent`/`generateContentStream`.
    - `config.systemInstruction` is a string or Content.
    - `config.tools` is `[ { functionDeclarations: FunctionDeclaration[] } ]`.
    - For 2.5 models the CLI may set `thinkingConfig: { thinkingBudget: -1, includeThoughts: true }` by default.
  - OAuth wire shape (Code Assist): nesting under `request` plus `project`, `user_prompt_id`, `session_id`. See earlier JSON blob.

- Conditional “store/include” rules
  - Not applicable in Gemini CLI. There is no explicit “store” or “include” policy knob in the request object. History compaction is handled client‑side (see below).

Reasoning/Thoughts Handling

- Thinking config: When model supports thinking, CLI sets `thinkingConfig` and requests thoughts.
- Streaming Thoughts: When a streamed chunk’s first part is a `thought` part, the server surfaces a `GeminiEventType.Thought` event containing a subject and description extracted from the text (bolded subject convention). See `packages/core/src/core/turn.ts`.
- History persistence: Thought parts are removed when recording history. In `geminiChat.recordHistory()`, model parts are filtered with `!part.thought` before being persisted; CountTokens conversion also strips thought metadata into normal text when needed.

Complete Tool Inventory & Inclusion Logic

- Built‑ins (all under `packages/core/src/tools/`):
  - read_file, write_file, edit (replace), smart-edit, list_directory (ls), glob, search_file_content (two variants: grep and ripGrep), read_many_files, run_shell_command (shell), web_fetch, google_web_search (web-search), save_memory (memoryTool).
- MCP tools:
  - Discovered at runtime from configured MCP servers via `mcp-client.ts` using `mcpToTool(mcpClient)`.
  - For each `functionDeclaration`, CLI validates parameter schema types (see `hasValidTypes`) and registers a `DiscoveredMCPTool` with sanitized name.

- Inclusion to model:
  - All registered tools (built‑ins + discovered) are included in a single `tools` element with `functionDeclarations` for both non‑streaming and streaming calls. There is no separate “Chat vs Responses” tool set; both paths use the same tool list for a turn.

Tool JSON Definitions: Selected Exact Schemas/Descriptions

- run_shell_command (ShellTool)
  - File: `packages/core/src/tools/shell.ts`
  - Name: `run_shell_command`
  - Description (platform‑specific; verbatim behavior summarized):
    - On Windows: executes `cmd.exe /c <command>`; background via `start /b`.
    - On POSIX: executes `bash -c <command>`; background via `&`; process group PGID is exposed; can be signaled via `kill -- -PGID`.
    - Returns the following information: Command, Directory, Output (stdout), Error, Exit Code, Signal, Background PIDs, Process Group PGID. Output may be streamed to the UI via `updateOutput` once per second.
  - Parameters schema:
    - `command: string` – exact shell command (required)
    - `description?: string` – brief human description (optional)
    - `directory?: string` – optional workspace directory name (relative to workspace set) (optional)
  - Confirmation behavior: prompts for root command approval; approvals add commands to an allowlist; AUTO_EDIT approval bypasses.

- read_file
  - Parameters: `{ absolute_path: string, offset?: number, limit?: number }`
  - Behavior: For text, returns string content; truncation indicated with range and offset guidance. For binary/image/pdf/audio/video, returns `inlineData { mimeType, data }`.

- google_web_search
  - Parameters: `{ query: string }`
  - Behavior: Calls model with `{ tools: [{ googleSearch: {} }] }`; response text plus “Sources” based on `groundingMetadata.groundingChunks`. Adds citation markers into text using `groundingSupports` byte indices.

- web_fetch
  - Parameters: `{ prompt: string }` (URLs + instructions)
  - Behavior: Prefer `{ tools: [{ urlContext: {} }] }` path; fallback to local fetch (with GitHub raw URL rewrite for blob URLs) then call model with summarized page text; returns text and “Sources” similar to web_search when available.

Exact Return Payloads for Tools

- FunctionResponse wiring (authoritative):
  - String output ⇒ one part: `{ functionResponse: { id, name, response: { output: "..." } } }`.
  - Part[] output ⇒ prepend one functionResponse part `{ response: { output: "Tool execution succeeded." } }`, then append the parts.
  - Single Part output ⇒
    - If it is a `functionResponse`, pass through (if nested content exists, text is extracted).
    - If `inlineData`/`fileData`, add status functionResponse part and include the binary part as a sibling.
  - There is no `metadata` object added to function responses by the CLI.

- Examples:
  - Binary image from read_file returns a functionResponse with a brief status plus an adjacent `inlineData` part with image bytes (base64). Image is included in the same user message that carries the tool response; there is no delayed “next turn data URL” behavior.
  - google_web_search returns tool content (text) to the model; not UI‑only.

MCP Integration Details

- Tool naming and qualification:
  - Raw tool names are sanitized via `generateValidName(name)` which replaces invalid characters `[^A-Za-z0-9_.-]` with `_` and enforces a maximum length of 63 characters by truncating the middle to `___` (first 28 chars + `___` + last 32 chars).
  - When name conflicts or disambiguation are required, CLI can expose fully qualified names `serverName__toolName` (see `asFullyQualifiedTool`).

- Schema gating (sanitation/validation):
  - The CLI requires JSON Schemas to have type information; it skips tools whose parameter schemas are missing types.
  - Validation algorithm `hasValidTypes(schema)`:
    - If no top‑level `type`, accept only if a combiner (`anyOf|allOf|oneOf`) exists and each subschema in the combiner passes validation.
    - For `type: object`, recursively validate `properties`.
    - For `type: array`, validate `items` recursively.
    - Otherwise valid.
  - Cyclic schema detection exists in `hasCycleInSchema` for improved error messaging when model errors mention maximum schema depth exceeded.

Conversation & Prompt Construction

- System instruction composition:
  - Default prompt assembled by `getCoreSystemPrompt(userMemory)`. Optional override via `GEMINI_SYSTEM_MD` path; optional write‑to‑file via `GEMINI_WRITE_SYSTEM_MD`. No `apply_patch`‑specific text is injected.
- Environment context user message:
  - Injected at chat start as a single user `Part { text: ... }` describing today’s date, platform, working directories, and folder structure. If `fullContext` is enabled, the content of `read_many_files` is appended.
- History:
  - Initial seed: an env context user message and a simple model acknowledgement.
  - Tool responses are added as a single user message containing the functionResponse part plus any additional parts.
  - History is curated to remove invalid streamed chunks and to deduplicate AFC history slices.
  - Chat compression can be triggered by token threshold; uses a dedicated system instruction and a follow‑up `sendMessage` to create a summary, then starts a fresh chat with the summary plus remaining tail history.

Concrete Examples

- Responses‑style turn (non‑streaming) with Shell
  - Request (conceptual, typed):
    ```ts
    await contentGenerator.generateContent({
      model,
      contents: [ ...history, { role: 'user', parts: [{ text: "Run `ls -la`" }] }],
      config: {
        systemInstruction,
        tools: [{ functionDeclarations: toolRegistry.getFunctionDeclarations() }],
      },
    }, prompt_id)
    ```
  - Model response (simplified candidate):
    ```json
    {
      "candidates":[{
        "content":{
          "role":"model",
          "parts":[{"functionCall":{"id":"fc1","name":"run_shell_command","args":{"command":"ls -la"}}}]
        }
      }]}
    ```
  - Tool execution converts to user message:
    ```json
    {
      "role":"user",
      "parts":[{"functionResponse":{"id":"fc1","name":"run_shell_command","response":{"output":"Command: ls -la\nDirectory: (root)\nOutput: ...\nError: (none)\nExit Code: 0\nSignal: (none)\nBackground PIDs: (none)\nProcess Group PGID: 12345"}}]
    }
    ```

- Streaming turn (Chat‑like) with events
  - Turn.run yields:
    - Thought events (optional)
    - Content events (text)
    - ToolCallRequest { callId, name, args }
    - ToolCallResponse { callId, responseParts[] }
    - Finished { finishReason }

Elixir Porting Notes (Ready‑to‑Use)

- Types
  - Define structs mirroring GenAI:
    - `%Part{text :: String.t | nil, function_call :: map() | nil, function_response :: map() | nil, inline_data :: %{mime_type: String.t, data: String.t} | nil}`
    - `%Content{role :: :user | :model, parts :: [Part]}`
    - `%FunctionDeclaration{name :: String.t, description :: String.t, parameters_json_schema :: map()}`
    - `%ToolResult{llm_content :: String | [Part] | Part, return_display :: String | map(), error :: nil | %{message: String.t, type: atom()}}`

- Building tools array
  - Responses/Streaming: always
    ```elixir
    def tools_for_model(tool_schemas), do: [%{functionDeclarations: tool_schemas}]
    ```

- Mapping chat to messages
  - Seed history: env context user message, then model ack.
  - On tool call: append one `%Content{role: :user, parts: [function_response_part | extra_parts]}`.

- Exec payload formatter (Shell parity)
  - Compose a multi‑line string with the exact keys in the same order:
    "Command:", "Directory:", "Output:", "Error:", "Exit Code:", "Signal:", "Background PIDs:", "Process Group PGID:".
  - Stream updates no more than once per second.

- Images to data URL helper
  - To mirror inlineData usage as a data URL for UI (if desired):
    `"data:" <> mime <> ";base64," <> base64`

- MCP name qualification and schema gating
  - Name sanitizer:
    ```elixir
    def sanitize_tool_name(name) do
      valid = Regex.replace(~r/[^A-Za-z0-9_.-]/, name, "_")
      if String.length(valid) > 63 do
        String.slice(valid, 0, 28) <> "___" <> String.slice(valid, -32, 32)
      else
        valid
      end
    end
    ```
  - Qualified form: `server <> "__" <> tool` when needed.
  - Schema gating (types required): recursively ensure `type` present at object root or in combiner subschemas; validate `properties` and `items` recursively.

- Request builders
  - Responses (non‑streaming): build `%{model: model, contents: contents, config: %{systemInstruction: sys, tools: tools}}` and JSON‑encode.
  - Streaming: same body; use SSE parsing logic `data: <json>` lines separated by blank lines.
  - Headers: set `Content-Type`, `User-Agent`; add OAuth bearer or API key according to transport.

Not Present in Gemini CLI (for clarity)

- Tools named `view_image`, `update_plan`, `apply_patch`, `exec_command` (separate from run_shell_command), `write_stdin` do not exist in this codebase. These appear to be outside Gemini CLI scope and would be custom to your agent framework.
- FunctionCallOutput with `{"output":"...","metadata":{...}}` is not used. The CLI always uses `{ response: { output: string } }` without metadata for functionResponse parts.
- “Responses vs Chat” as distinct APIs with different tool lists or headers is not a Gemini CLI concept; both non‑streaming and streaming use the same tool list and generation config.


MCP Tools: Part[] Transforms and Confirmation Flow

- Confirmation:
  - Each discovered MCP tool wraps a CallableTool and defers `shouldConfirmExecute` to a ToolMcpConfirmationDetails object.
  - Details include: `type: 'mcp'`, `serverName`, `toolName` (original server name), `toolDisplayName` (exposed name), and `onConfirm(outcome)` which can add the server or tool to an allowlist if “always” is chosen.
  - Source: packages/core/src/tools/mcp-tool.ts (DiscoveredMCPToolInvocation.shouldConfirmExecute)

- Response transform to GenAI Parts:
  - The MCP SDK returns a Part[] whose first element is a functionResponse with a nested `response.content: ContentBlock[]` per MCP spec.
  - Gemini CLI transforms these MCP blocks to GenAI parts:
    - `text` → `{ text }`
    - `image`/`audio` → `[ { text: "[Tool 'name' provided the following image/audio data with mime-type: <mime>]" }, { inlineData: { mimeType, data } } ]`
    - `resource` with `text` → `{ text }`
    - `resource` with `blob` → same pattern as image/audio using `inlineData`
    - `resource_link` → `{ text: "Resource Link: <title|name> at <uri>" }`
  - Display string for UI is a flattened string of the above (images/audio become bracketed descriptions).
  - Source: packages/core/src/tools/mcp-tool.ts (transformMcpContentToParts, getStringifiedResultForDisplay)

- Tool naming:
  - Names sanitized to `[A-Za-z0-9_.-]`, truncated to 63 chars by replacing the middle with `___` (28 + ___ + 32).
  - Fully qualified name when needed: `serverName__serverToolName`.
  - Source: packages/core/src/tools/mcp-tool.ts (generateValidName, asFullyQualifiedTool)


Edit/Smart‑Edit/Write‑File: Modifiable Flows, Diff Stats, IDE Confirmations

- Tools involved: replace (edit.ts), smart_edit (smart-edit.ts), write_file (write-file.ts)
- Confirmation details (ToolEditConfirmationDetails):
  - `type: 'edit'`, `title`, `fileName`, `filePath`, `fileDiff` (unified diff text), `originalContent`, `newContent`, optional `ideConfirmation: Promise<DiffUpdateResult>`.
  - If IDE is connected, the tool opens a diff and waits; the onConfirm handler can adopt edited content from IDE, updating params before execution.
  - AUTO_EDIT mode can bypass confirmations.
- Diff stats:
  - On success, returnDisplay may include `{ fileDiff, fileName, originalContent, newContent, diffStat }`.
  - `diffStat` fields: `ai_added_lines`, `ai_removed_lines`, `user_added_lines`, `user_removed_lines`.
  - Telemetry attaches these into ToolCallEvent.metadata when present.
- ModifiableDeclarativeTool:
  - Tools implement `getModifyContext/1` to enable ModifyWithEditor outcome; CoreToolScheduler orchestrates modify/confirm cycles and updates args with `setArgsInternal`.
- Sources: packages/core/src/tools/edit.ts, smart-edit.ts, write-file.ts; scheduler: packages/core/src/core/coreToolScheduler.ts


Telemetry Relevant to Tool Decisions

- ToolCallEvent fields (emitted after terminal states success/error/cancel):
  - `function_name`, `function_args`, `duration_ms`, `success`, `decision` (derived from confirmation outcome), `error`, `error_type`, `prompt_id`, `tool_type: 'native'|'mcp'`, optional `metadata` (diff stats when available).
  - Sources: packages/core/src/telemetry/types.ts (ToolCallEvent), packages/core/src/telemetry/loggers.ts (logToolCall)
- API events:
  - ApiRequestEvent, ApiResponseEvent (token counts, including `toolUsePromptTokenCount`, `thoughtsTokenCount`), ApiErrorEvent.
  - Sources: packages/core/src/telemetry/types.ts, loggers.ts


SDK‑Equivalent JSON (API Key Path)

- The CLI passes a typed object to @google/genai; the SDK serializes HTTP. Equivalent JSON body mirrors:

```json
{
  "model": "gemini-2.0-flash",
  "contents": [
    { "role": "user", "parts": [{ "text": "env context..." }] },
    { "role": "model", "parts": [{ "text": "Got it. Thanks for the context!" }] },
    { "role": "user", "parts": [{ "text": "Run `ls -la`" }] }
  ],
  "config": {
    "systemInstruction": "<system prompt>",
    "tools": [ { "functionDeclarations": [
      { "name": "run_shell_command", "description": "...", "parametersJsonSchema": { "type": "object", "properties": { "command": {"type":"string"} }, "required": ["command"] } }
    ] } ],
    "thinkingConfig": { "thinkingBudget": -1, "includeThoughts": true }
  }
}
```

- Headers observed from CLI: `User-Agent: GeminiCLI/<version> (<platform>; <arch>)`, optionally `x-gemini-api-privileged-user-id` when telemetry is enabled.


Code Assist Streaming Example (SSE)

- Request: `POST https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse` with the OAuth body as documented earlier.
- Response stream (reconstructed):

```
data: {"response":{"candidates":[{"content":{"role":"model","parts":[{"text":"Thinking..."}]}}],"usageMetadata":{"promptTokenCount":123}}}

data: {"response":{"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"id":"fc1","name":"run_shell_command","args":{"command":"ls -la"}}}]}}]}}

data: {"response":{"automaticFunctionCallingHistory":[{"role":"model","parts":[{"functionCall":{"id":"fc1","name":"run_shell_command","args":{"command":"ls -la"}}}]}]}} 

data: {"response":{"candidates":[{"content":{"role":"model","parts":[{"text":"Listed files; next step..."}]},"finishReason":"STOP"}]}}

```

- The client buffers lines starting with `data: ` until a blank line, then parses as JSON and yields a GenerateContentResponse per block.


Built‑in Tools Table (path → params → returns)

- read_file → packages/core/src/tools/read-file.ts
  - Params: `{ absolute_path: string, offset?: number, limit?: number }`
  - Returns: `string` for text; `{ inlineData: { mimeType, data } }` for binary/image/pdf/audio/video; `returnDisplay` short message; errors typed.

- write_file → packages/core/src/tools/write-file.ts
  - Params: `{ file_path: string, content: string }`
  - Returns: success message; `returnDisplay` FileDiff with diffStat; errors typed.

- replace (edit) → packages/core/src/tools/edit.ts
  - Params: `{ file_path: string, old_string: string, new_string: string, expected_replacements?: number }`
  - Returns: success message; FileDiff; strict occurrence validation; errors typed.

- smart_edit → packages/core/src/tools/smart-edit.ts
  - Params: `{ file_path: string, instruction: string, old_string: string, new_string: string }`
  - Returns: success message; FileDiff; self‑correction attempts; CRLF restoration when needed.

- list_directory → packages/core/src/tools/ls.ts
  - Params: `{ path: string, ignore?: string[], file_filtering_options?: { respect_git_ignore?: boolean, respect_gemini_ignore?: boolean } }`
  - Returns: textual listing; filtered counts; errors typed.

- glob → packages/core/src/tools/glob.ts
  - Params: `{ pattern: string, path?: string, case_sensitive?: boolean, respect_git_ignore?: boolean }`
  - Returns: list of absolute paths as text; recent files first sorting.

- search_file_content (grep) → packages/core/src/tools/grep.ts
  - Params: `{ pattern: string, path?: string, include?: string }`
  - Returns: grouped matches with file and line numbers; JS fallback and git/system grep strategies.

- search_file_content (ripGrep) → packages/core/src/tools/ripGrep.ts
  - Params: `{ pattern: string, path?: string, include?: string }`
  - Returns: grouped matches; limited to 20,000 results; uses bundled ripgrep binary path.

- read_many_files → packages/core/src/tools/read-many-files.ts
  - Params: `{ paths: string[], include?: string[], exclude?: string[], useDefaultExcludes?: boolean, file_filtering_options?: {...} }`
  - Returns: PartListUnion combining multiple files separated by `--- {filePath} ---`; includes inlineData for explicitly requested binary (image/pdf).

- run_shell_command → packages/core/src/tools/shell.ts
  - Params: `{ command: string, description?: string, directory?: string }`
  - Returns: multi‑line string with: Command, Directory, Output, Error, Exit Code, Signal, Background PIDs, Process Group PGID; live updates throttled to 1s.

- web_fetch → packages/core/src/tools/web-fetch.ts
  - Params: `{ prompt: string }`
  - Returns: text summary; URLs processed either via `urlContext` tool or local fallback; includes “Sources” section when grounding metadata present.

- google_web_search → packages/core/src/tools/web-search.ts
  - Params: `{ query: string }`
  - Returns: text with inline numeric citations and a Sources section.

- save_memory → packages/core/src/tools/memoryTool.ts
  - Params: `{ fact: string }`
  - Returns: JSON string success or error; writes to ~/.gemini/GEMINI.md in a “Gemini Added Memories” section.


Elixir Code: Structs, Encoders, Builders, and MCP Adapter

- Core structs
```elixir
defmodule Codex.Gemini.Part do
  @enforce_keys []
  defstruct [:text, :function_call, :function_response, :inline_data]
end

defmodule Codex.Gemini.Content do
  @enforce_keys [:role, :parts]
  defstruct [:role, parts: []]
end

defmodule Codex.Gemini.FunctionDeclaration do
  @enforce_keys [:name, :description]
  defstruct [:name, :description, :parameters_json_schema]
end

defmodule Codex.Gemini.ToolResult do
  @enforce_keys [:llm_content, :return_display]
  defstruct [:llm_content, :return_display, :error]
end
```

Concrete MCP functionDeclarations Examples (from tests)

- Example list returned by an MCP server (one valid, one invalid) as used in tests:

```json
{
  "functionDeclarations": [
    {
      "name": "validTool",
      "parametersJsonSchema": {
        "type": "object",
        "properties": {
          "param1": { "type": "string" }
        }
      }
    },
    {
      "name": "invalidTool",
      "parametersJsonSchema": {
        "type": "object",
        "properties": {
          "param1": { "description": "a param with no type" }
        }
      }
    }
  ]
}
```

- The CLI will register only `validTool` and will skip `invalidTool` (missing types). If conflict or disambiguation is needed, a fully qualified name can be used, e.g. `pythonTools__validTool`.

Tool → LLM Content Typology Matrix (pre-conversion)

- read_file:
  - Text files: string
  - Image/PDF/Audio/Video: Part with `{ inlineData: { mimeType, data } }`
- read_many_files:
  - Concatenated text across files: string (as parts of a PartListUnion)
  - Explicitly requested binary (image/pdf): Part with `inlineData`
- write_file, edit (replace), smart_edit:
  - Success/failure messages: string
  - returnDisplay: FileDiff object (UI)
- list_directory, glob, search_file_content (grep/ripGrep):
  - Structured plain text summary: string
- run_shell_command:
  - Multi-line summary: string; can stream intermediate output via updateOutput callback
- web_fetch, google_web_search:
  - Plain text summary enriched with “Sources” when grounding metadata present: string
- save_memory:
  - JSON string success/error (e.g., `{ "success": true, "message": "..." }`)

Note: After tool execution, the scheduler converts these llmContent values into functionResponse parts per the rules above; inlineData parts are included as sibling parts in the same user message.

Non‑Streaming OAuth (Code Assist) End‑to‑End JSON Example

Request (body to `POST https://cloudcode-pa.googleapis.com/v1internal:generateContent`):

```json
{
  "model": "gemini-2.0-flash",
  "project": "my-gcp-project",
  "user_prompt_id": "sess-123#turn-4",
  "request": {
    "contents": [
      { "role": "user", "parts": [ { "text": "This is the Gemini CLI. We are setting up the context..." } ] },
      { "role": "model", "parts": [ { "text": "Got it. Thanks for the context!" } ] },
      { "role": "user", "parts": [ { "text": "List directory and read README.md" } ] }
    ],
    "systemInstruction": { "text": "<system prompt text here>" },
    "tools": [ {
      "functionDeclarations": [
        {
          "name": "run_shell_command",
          "description": "Executes a shell command (platform-specific details)",
          "parametersJsonSchema": {
            "type": "object",
            "properties": {
              "command": { "type": "string", "description": "Exact command" },
              "description": { "type": "string" },
              "directory": { "type": "string" }
            },
            "required": ["command"]
          }
        },
        {
          "name": "read_file",
          "description": "Reads a file; handles text and binary (image/pdf/audio/video)",
          "parametersJsonSchema": {
            "type": "object",
            "properties": {
              "absolute_path": { "type": "string" },
              "offset": { "type": "number" },
              "limit": { "type": "number" }
            },
            "required": ["absolute_path"]
          }
        }
      ]
    } ],
    "generationConfig": {
      "temperature": 0,
      "topP": 1,
      "thinkingConfig": { "thinkingBudget": -1, "includeThoughts": true }
    },
    "session_id": "sess-123"
  }
}
```

Headers:
- `Content-Type: application/json`
- `Authorization: Bearer <oauth-token>` (injected by google-auth-library)
- `User-Agent: GeminiCLI/<version> (<platform>; <arch>)`

Note on API key path: when using @google/genai with `apiKey` configured, the SDK will include the appropriate API key header(s). The CLI sets only `User-Agent` and the optional `x-gemini-api-privileged-user-id` header for telemetry correlation.


Built‑ins Summary Table (compact)

| Tool | File | Params schema (excerpt) | Example llmContent snippet |
|---|---|---|---|
| `read_file` | packages/core/src/tools/read-file.ts | `{ "type":"object","properties":{"absolute_path":{"type":"string"},"offset":{"type":"number"},"limit":{"type":"number"}},"required":["absolute_path"] }` | Text: `"<file contents or truncated block>"` Binary: `{ "inlineData": { "mimeType":"image/png","data":"<base64>" } }` |
| `write_file` | packages/core/src/tools/write-file.ts | `{ "type":"object","properties":{"file_path":{"type":"string"},"content":{"type":"string"}},"required":["file_path","content"] }` | `"Successfully created and wrote to new file: /abs/path.txt."` |
| `replace` | packages/core/src/tools/edit.ts | `{ "type":"object","properties":{"file_path":{"type":"string"},"old_string":{"type":"string"},"new_string":{"type":"string"},"expected_replacements":{"type":"number"}},"required":["file_path","old_string","new_string"] }` | `"Successfully modified file: /abs/path.ex (1 replacements)."` or error string |
| `smart_edit` | packages/core/src/tools/smart-edit.ts | `{ "type":"object","properties":{"file_path":{"type":"string"},"instruction":{"type":"string"},"old_string":{"type":"string"},"new_string":{"type":"string"}},"required":["file_path","instruction","old_string","new_string"] }` | `"Successfully modified file: /abs/path.ts (1 replacements)."` |
| `list_directory` | packages/core/src/tools/ls.ts | `{ "type":"object","properties":{"path":{"type":"string"},"ignore":{"type":"array","items":{"type":"string"}},"file_filtering_options":{"type":"object","properties":{"respect_git_ignore":{"type":"boolean"},"respect_gemini_ignore":{"type":"boolean"}}}},"required":["path"] }` | `"Directory listing for /abs: \n[DIR] src\nREADME.md"` |
| `glob` | packages/core/src/tools/glob.ts | `{ "type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"case_sensitive":{"type":"boolean"},"respect_git_ignore":{"type":"boolean"}},"required":["pattern"] }` | `"Found 3 file(s) matching '**/*.md' within /repo: \n/abs/README.md\n/abs/docs/a.md..."` |
| `search_file_content` (grep) | packages/core/src/tools/grep.ts | `{ "type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"include":{"type":"string"}},"required":["pattern"] }` | `"Found 2 matches for pattern 'foo' in path ".":\n---\nFile: src/a.ts\nL12: const foo=...\n---"` |
| `search_file_content` (ripGrep) | packages/core/src/tools/ripGrep.ts | same as grep | Same, plus `(results limited to 20000 matches)` when truncated |
| `read_many_files` | packages/core/src/tools/read-many-files.ts | `{ "type":"object","properties":{"paths":{"type":"array","items":{"type":"string"}},"include":{"type":"array","items":{"type":"string"}},"exclude":{"type":"array","items":{"type":"string"}},"recursive":{"type":"boolean"},"useDefaultExcludes":{"type":"boolean"},"file_filtering_options":{"type":"object","properties":{"respect_git_ignore":{"type":"boolean"},"respect_gemini_ignore":{"type":"boolean"}}}},"required":["paths"] }` | `"--- path/to/file1.ts ---\n<content>\n--- path/to/file2.md ---\n<content>\n--- End of content ---"` and inlineData parts for explicitly requested image/pdf |
| `run_shell_command` | packages/core/src/tools/shell.ts | `{ "type":"object","properties":{"command":{"type":"string"},"description":{"type":"string"},"directory":{"type":"string"}},"required":["command"] }` | `"Command: ls -la\nDirectory: (root)\nOutput: ...\nError: (none)\nExit Code: 0\nSignal: (none)\nBackground PIDs: (none)\nProcess Group PGID: 12345"` |
| `web_fetch` | packages/core/src/tools/web-fetch.ts | `{ "type":"object","properties":{"prompt":{"type":"string"}},"required":["prompt"] }` | `"<summary from fetched URLs>\n\nSources:\n[1] Title (https://...)"` |
| `google_web_search` | packages/core/src/tools/web-search.ts | `{ "type":"object","properties":{"query":{"type":"string"}},"required":["query"] }` | `"Web search results for \"kubernetes\":\n...\n\nSources:\n[1] Title (https://...)"` |
| `save_memory` | packages/core/src/tools/memoryTool.ts | `{ "type":"object","properties":{"fact":{"type":"string"}},"required":["fact"] }` | `"{ \"success\": true, \"message\": \"Okay, I've remembered that: \"My favorite color is blue\"\" }"` |

- Tools array builder
```elixir
def tools_for_model(function_decls) when is_list(function_decls) do
  [%{functionDeclarations: function_decls}]
end
```

- FunctionResponse helpers
```elixir
def function_response_part(call_id, name, output_str) do
  %{functionResponse: %{id: call_id, name: name, response: %{output: output_str}}}
end

def wrap_tool_result(call_id, name, llm_content) when is_binary(llm_content) do
  [function_response_part(call_id, name, llm_content)]
end

def wrap_tool_result(call_id, name, parts) when is_list(parts) do
  [function_response_part(call_id, name, "Tool execution succeeded.") | parts]
end

def wrap_tool_result(call_id, name, part) when is_map(part) do
  # If it’s inline_data/file_data style, prepend a status
  [function_response_part(call_id, name, "Binary content processed.") | [part]]
end
```

- Exec payload formatter (Shell parity)
```elixir
def format_shell_result(%{
      command: cmd, directory: dir, output: out, error: err,
      exit_code: code, signal: sig, background_pids: pids, pgid: pgid
    }) do
  [
    "Command: #{cmd}",
    "Directory: #{dir || "(root)"}",
    "Output: #{out || "(empty)"}",
    "Error: #{err || "(none)"}",
    "Exit Code: #{inspect(code) |> default_none}",
    "Signal: #{inspect(sig) |> default_none}",
    "Background PIDs: #{(pids && pids != [] && Enum.join(pids, ", ")) || "(none)"}",
    "Process Group PGID: #{pgid || "(none)"}"
  ] |> Enum.join("\n")
end

defp default_none("nil"), do: "(none)"
defp default_none(other), do: other
```

- Image data URL helper (optional for UI)
```elixir
def data_url(mime, base64), do: "data:" <> mime <> ";base64," <> base64
```

- MCP adapter: name sanitizer and schema gating
```elixir
def sanitize_tool_name(name) do
  valid = Regex.replace(~r/[^A-Za-z0-9_.-]/, name, "_")
  if String.length(valid) > 63, do: String.slice(valid, 0, 28) <> "___" <> String.slice(valid, -32, 32), else: valid
end

def fully_qualified(server, tool), do: server <> "__" <> tool

def has_valid_types(schema) when is_map(schema) do
  cond do
    Map.has_key?(schema, "type") ->
      case schema["type"] do
        "object" ->
          props = Map.get(schema, "properties", %{})
          Enum.all?(Map.values(props), &has_valid_types/1)
        "array" -> has_valid_types(Map.get(schema, "items"))
        _ -> true
      end
    true ->
      subs = Enum.flat_map(["anyOf","allOf","oneOf"], fn k -> List.wrap(schema[k]) end)
      subs != [] and Enum.all?(subs, &has_valid_types/1)
  end
end
def has_valid_types(_), do: true
```

- Request builders
```elixir
def build_request(model, contents, system_instruction, tools) do
  %{
    model: model,
    contents: contents,
    config: %{systemInstruction: system_instruction, tools: tools}
  }
end

def headers(user_agent, oauth_token \\ nil, api_key \\ nil) do
  base = [{"User-Agent", user_agent}, {"Content-Type", "application/json"}]
  base = if oauth_token, do: [{"Authorization", "Bearer " <> oauth_token} | base], else: base
  base = if api_key, do: [{"x-goog-api-key", api_key} | base], else: base
  base
end
```
