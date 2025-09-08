# Guide: Debugging and Fixing Tool Call Conversation Loops

This document provides a detailed analysis of a common failure pattern where an AI agent becomes stuck in a loop while using tools, particularly for multi-step tasks like reading a large file. By comparing a failing and a succeeding conversation log, we can identify the root cause and implement a robust fix.

**Scenario:** The agent is asked to summarize the file `RAG.md`. It correctly identifies that it needs to read the file in chunks. However, instead of summarizing after reading all chunks, it gets stuck in a loop, reading the file over and over.

**Objective:** Fix the underlying client-side logic to ensure the conversation history is managed correctly, allowing the agent to complete multi-step tool-based tasks.

---

## 1. Analysis of the Problem

The root cause is twofold, both related to how the client application constructs the `input` payload for the API on subsequent requests *after* receiving a tool call from the model.

### Issue 1: Malformed `function_call_output` Message

The most critical error is that the message containing the result of the tool execution is not structured correctly. The API expects a message object with a specific `type`.

- **The Broken Request (`oauth_read_file.log`)**
  The client sends the tool's output back as a plain JSON object, missing the required `type` attribute.

  **Incorrect JSON sent to the model:**
  ```json
  {
      "call_id": "call_NbkYqhjw8M5gsZV4pOGqwYOJ",
      "output": "{\"metadata\":{...},\"output\":\"## **Executive Summary**...\"}"
  }
  ```
  The model does not recognize this as a valid part of the conversation history and ignores it, failing to "see" the content of the file that was just read.

- **The Correct Request (`openai_api_flow__read_file.log`)**
  A correctly formatted message includes `"type": "function_call_output"`.

  **Correct JSON that should be sent to the model:**
  ```json
  {
      "type": "function_call_output",
      "call_id": "call_NbkYqhjw8M5gsZV4pOGqwYOJ",
      "output": "{\"metadata\":{...},\"output\":\"## **Executive Summary**...\"}"
  }
  ```

### Issue 2: Incorrect Conversation History Management

The second error is that the client is not building upon the existing conversation. It discards old turns, causing the model to lose context.

- **The Broken Flow (`oauth_read_file.log`)**
  The client reconstructs the history on each turn using only the *original* user prompt and the *most recent* tool interaction.

  - **Input for Request #2:** `[original_user_prompt, assistant_msg_1, tool_call_1, tool_output_1]`
  - **Input for Request #3:** `[original_user_prompt, assistant_msg_2, tool_call_2, tool_output_2]`

  Notice how the results from Turn 1 (`assistant_msg_1`, `tool_call_1`, `tool_output_1`) are **missing** from the input for Request #3. The model has no memory that it already read the first chunk of the file.

- **The Correct Flow (`openai_api_flow__read_file.log`)**
  The client **appends** each new interaction to the history, creating a complete, chronological log.

  - **Input for Request #2:** `[original_user_prompt, assistant_msg_1, tool_call_1, tool_output_1]`
  - **Input for Request #3:** `[original_user_prompt, assistant_msg_1, tool_call_1, tool_output_1, assistant_msg_2, tool_call_2, tool_output_2]`

  With this complete history, the model can see all the chunks it has read and knows when it's time to proceed with the final summary.

---

## 2. Step-by-Step Guide to the Fix

The goal is to implement proper state management for the conversation history on the client-side.

### Step 1: Correctly Structure the `function_call_output`

Before sending the result of a tool back to the model, ensure it is wrapped in a message object with `type: "function_call_output"`.

**CURRENT (WRONG):**
```json
{
  "call_id": "...",
  "output": "..."
}
```

**GOAL (CORRECT):**
```json
{
  "type": "function_call_output",
  "call_id": "...",
  "output": "..."
}
```

### Step 2: Implement Correct History Accumulation

The conversation history must be maintained as a list of message objects that grows with each turn. Do not discard previous turns.

Below is a turn-by-turn example of how the `input` array in the request body should be constructed.

#### Turn 1: User's Initial Request

The client sends the user's prompt.

```json
// POST /codex/responses
{
  "input": [
    {
      "type": "message",
      "role": "user",
      "content": [{"type": "input_text", "text": "please summarize RAG.md"}]
    }
  ],
  "tools": [...] 
}
```

#### Turn 1: Model's Response (Tool Call)

The model responds with a message and a tool call.

```json
// SSE events from model
{
  "type": "message",
  "role": "assistant",
  "content": [{"type": "output_text", "text": "I’ll open RAG.md in chunks..."}]
},
{
  "type": "function_call",
  "name": "read_file_chunk",
  "call_id": "call_1",
  "arguments": "{\"path\":\"RAG.md\",\"start_line\":1,\"max_lines\":250}"
}
```

#### Turn 2: Client's Request (Sending First Tool Result)

The client executes the `read_file_chunk` tool. It then constructs a **new** request body containing the **full history** so far, including the correctly formatted tool output.

```json
// POST /codex/responses
{
  "input": [
    // 1. Original User Message
    {
      "type": "message",
      "role": "user",
      "content": [{"type": "input_text", "text": "please summarize RAG.md"}]
    },
    // 2. Assistant's Message from Turn 1
    {
      "type": "message",
      "role": "assistant",
      "content": [{"type": "output_text", "text": "I’ll open RAG.md in chunks..."}]
    },
    // 3. The Function Call from Turn 1
    {
      "type": "function_call",
      "name": "read_file_chunk",
      "call_id": "call_1",
      "arguments": "{\"path\":\"RAG.md\",\"start_line\":1,\"max_lines\":250}"
    },
    // 4. The NEW, CORRECTLY FORMATTED Tool Output
    {
      "type": "function_call_output",
      "call_id": "call_1",
      "output": "{\"metadata\":{\"eof\":false,\"next_start\":251,...},\"output\":\"## Executive Summary...\"}"
    }
  ],
  "tools": [...] 
}
```

#### Turn 2: Model's Response (Another Tool Call)

The model sees the first chunk. Since `eof` was false, it calls the tool again for the next chunk.

```json
// SSE events from model
{
  "type": "function_call",
  "name": "read_file_chunk",
  "call_id": "call_2",
  "arguments": "{\"path\":\"RAG.md\",\"start_line\":251,\"max_lines\":250}"
}
```
*(Note: The model may or may not send a text message here. The logic remains the same.)*

#### Turn 3: Client's Request (Sending Second Tool Result)

The client executes the second tool call and **appends the new interactions** to the already existing history.

```json
// POST /codex/responses
{
  "input": [
    // --- Everything from the previous turn ---
    {"type": "message", "role": "user", ...},
    {"type": "message", "role": "assistant", ...},
    {"type": "function_call", "call_id": "call_1", ...},
    {"type": "function_call_output", "call_id": "call_1", ...},
    // --- Appended interactions from Turn 2 ---
    // 5. The Function Call from Turn 2
    {
      "type": "function_call",
      "name": "read_file_chunk",
      "call_id": "call_2",
      "arguments": "{\"path\":\"RAG.md\",\"start_line\":251,\"max_lines\":250}"
    },
    // 6. The NEW, CORRECTLY FORMATTED Output for the second call
    {
      "type": "function_call_output",
      "call_id": "call_2",
      "output": "{\"metadata\":{\"eof\":true,...},\"output\":\"# Phase 4: Learning from Corrections...\"}"
    }
  ],
  "tools": [...] 
}
```

---

## 3. Verification

After implementing these changes, the model's behavior in Turn 3 will change. Because the `input` now contains the content from both file chunks and the final tool output includes `"eof": true`, the model will have the full context. It will understand that the file has been completely read and will proceed to generate the final summary instead of calling the `read_file_chunk` tool again, thus breaking the loop.
