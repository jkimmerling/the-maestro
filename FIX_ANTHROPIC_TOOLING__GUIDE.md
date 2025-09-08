# Fixing Anthropic Tooling: A Hyper-Detailed Guide

This guide provides a definitive, step-by-step breakdown of a successful tool-use interaction with the Anthropic Messages API, based on a verified working log. It replaces all previous guidance.

**Objective**: To provide a "Golden Standard" reference for developers to ensure their implementation for handling tool calls is correct, preventing infinite loops and other errors.

---

## The Golden Standard: A Successful Tool Call Deconstructed

The following three-step process details a complete, successful tool-use cycle. The user asks to summarize a file, and the agent correctly uses the `Read` tool to accomplish this.

### Step 1: The Initial User Request (Request #11)

First, the user sends their prompt. The `claude-code` CLI wraps this in a complex JSON object that includes extensive system prompts, user metadata, and a list of all available tools.

**Key Takeaway:** The initial request must include the `tools` array defining the tools available to the agent.

**Full Request Body Sent to `POST /v1/messages`:**
```json
{
  "model": "claude-opus-4-1-20250805",
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "<system-reminder>...[content truncated]...</system-reminder>"
        },
        {
          "type": "text",
          "text": "<system-reminder>...[content truncated]...</system-reminder>"
        },
        {
          "type": "text",
          "text": "please summarize RAG.md",
          "cache_control": {
            "type": "ephemeral"
          }
        }
      ]
    }
  ],
  "temperature": 1,
  "system": [
    {
      "type": "text",
      "text": "You are Claude Code, Anthropic's official CLI for Claude.",
      "cache_control": {
        "type": "ephemeral"
      }
    },
    {
      "type": "text",
      "text": "\nYou are an interactive CLI tool...[content truncated]...",
      "cache_control": {
        "type": "ephemeral"
      }
    }
  ],
  "tools": [
    {
      "name": "Task",
      "description": "Launch a new agent to handle complex, multi-step tasks autonomously...",
      "input_schema": { ... }
    },
    {
      "name": "Read",
      "description": "Reads a file from the local filesystem...",
      "input_schema": { ... }
    }
    // ... and all other available tools
  ],
  "metadata": {
    "user_id": "user_aaf86a6505aecc8c84e8c868d98abde1f9b06b4130ff81c97b5871221f4ce870_account_cc33fd30-5012-4340-80fb-8f5777826cb4_session_5a262f9c-14fb-4243-8f19-1a241a5f1e50"
  },
  "max_tokens": 32000,
  "stream": true
}
```

### Step 2: The Agent's Response & Tool Use Request (Response to #11)

The API responds with a series of Server-Sent Events (SSE). The crucial parts are:
1.  A `content_block` with a `text` part, where the agent acknowledges the request.
2.  A `content_block` with a `tool_use` part, where the agent specifies which tool it wants to use.
3.  A final `message_delta` event with `stop_reason: "tool_use"`, signaling that it is waiting for the tool result.

**Key Takeaway:** The host application must parse these events to detect the `tool_use` request.

**Key Events from the Streamed Response:**
```text
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"I\'ll read the RAG.md file to provide you with a summary."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

---

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01BFph4BwyMk1PSv8tn7Mqmr","name":"Read","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"file_path\": \"/Users/jasonk/Development/the_maestro/RAG.md\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

---


event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use",...}}

event: message_stop
data: {"type":"message_stop"}
```

### Step 3: The Host's Corrective Action (Request #36)

This is the most critical step and the one that **must be replicated perfectly**. After executing the `Read` tool locally, the client (your Elixir framework) makes a **new** request to the API. This request contains the *entire conversation history*, plus a new `user` turn that provides the result of the tool.

**Key Takeaways:**
1.  The conversation history is maintained and resent.
2.  A new message with `role: "user"` is appended.
3.  The `content` of this new message is an array containing a single `tool_result` object.
4.  The `tool_result` object **must** contain the `tool_use_id` from the agent's previous turn.
5.  The `content` of the `tool_result` object **must be the actual, raw output from the executed tool**.

**Full Request Body Sent to `POST /v1/messages`:**
```json
{
  "model": "claude-opus-4-1-20250805",
  "messages": [
    // 1. Original User Message
    {
      "role": "user",
      "content": [ ... , { "type": "text", "text": "please summarize RAG.md" } ]
    },
    // 2. Assistant's Tool Use Message
    {
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": "I\'ll read the RAG.md file to provide you with a summary."
        },
        {
          "type": "tool_use",
          "id": "toolu_01BFph4BwyMk1PSv8tn7Mqmr",
          "name": "Read",
          "input": {
            "file_path": "/Users/jasonk/Development/the_maestro/RAG.md"
          },
          "cache_control": { "type": "ephemeral" }
        }
      ]
    },
    // 3. CRITICAL: The new User Message with the Tool Result
    {
      "role": "user",
      "content": [
        {
          "tool_use_id": "toolu_01BFph4BwyMk1PSv8tn7Mqmr",
          "type": "tool_result",
          "content": "     1→## **Executive Summary**\n     2→\n     3→This comprehensive plan outlines a hybrid architecture...[...the entire content of RAG.md...]...",
          "cache_control": {
            "type": "ephemeral"
          }
        }
      ]
    }
  ],
  "temperature": 1,
  "system": [ ... ],
  "tools": [ ... ],
  "metadata": { ... },
  "max_tokens": 32000,
  "stream": true
}
```

### Final Step: The Agent's Summarization (Response to #36)

Having received the file content in the correct `tool_result` format, the agent now has the context to complete the request. It responds with the summary, and the `stop_reason` is `end_turn`.

**Key Events from the Final Streamed Response:**
```text
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"## RAG.md Summary\n\nThis document outlines a comprehensive..."}}

...


event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn",...}}


event: message_stop
data: {"type":"message_stop"}
```

---

## Deeper Analysis of the Failing Log (`oauth_read_file.log`)

Beyond the primary failure, the failing log reveals other significant deviations from the golden standard.

### **Critical Failure: Incorrect Tool Result**

This remains the primary, loop-causing bug. Your framework is sending a hardcoded error message instead of executing the tool.

-   **Your `tool_result`:**
    ```json
    {
      "content": "unsupported tool: read",
      "tool_use_id": "toolu_01PZVDVuNqNBvz1jyXqSFT1r",
      "type": "tool_result"
    }
    ```
-   **Required `tool_result`:**
    ```json
    {
      "content": "[actual content of RAG.md]",
      "tool_use_id": "toolu_01PZVDVuNqNBvz1jyXqSFT1r",
      "type": "tool_result"
    }
    ```

### **Secondary Issue #1: Dropped Conversation History**

This is a major structural error. In every request after the first one, **you are dropping the entire conversation history**.

The `messages` array should be an append-only log of the entire conversation. Your implementation, however, sends a new `messages` array on every turn that only contains the context for that specific turn.

-   **Your (Incorrect) Second Request's `messages` array:**
    ```json
    [
        {
            "content": [{"text": "please summarize RAG.md", "type": "text"}],
            "role": "user"
        },
        {
            "content": [{"id": "...", "input": {...}, "name": "Read", "type": "tool_use"}],
            "role": "assistant"
        },
        {
            "content": [{"content": "unsupported tool: read", "tool_use_id": "...", "type": "tool_result"}],
            "role": "user"
        }
    ]
    ```
    This is wrong. It re-sends the initial prompt as if it were new, and it's missing the assistant's *textual* response from the previous turn.

-   **Golden Standard `messages` array (on the 3rd turn):**
    ```json
    [
        // Turn 1
        {
            "role": "user",
            "content": [ { "type": "text", "text": "please summarize RAG.md" } ]
        },
        // Turn 2
        {
            "role": "assistant",
            "content": [
                { "type": "text", "text": "I\'ll read the RAG.md file..." },
                { "type": "tool_use", "id": "...", "name": "Read", "input": {...} }
            ]
        },
        // Turn 3 (The new part)
        {
            "role": "user",
            "content": [ { "type": "tool_result", "tool_use_id": "...", "content": "..." } ]
        }
    ]
    ```

### **Secondary Issue #2: Missing System Prompt**

Your initial request correctly includes the `system` prompt. However, **all subsequent requests in the log omit the `system` block entirely.**

To ensure the agent maintains its persona and follows high-level instructions consistently, the `system` prompt should be included in every request of the conversation.

---


## Final Action Plan

1.  **CRITICAL: Implement Tool Execution:** Stop sending "unsupported tool". Your Elixir code must execute the requested tool and place the real result into the `tool_result` content block.
2.  **CRITICAL: Maintain Full Conversation History:** The `messages` array must be an append-only log. Each new request to the API must contain all previous `user` and `assistant` turns, in the correct order.
3.  **RECOMMENDED: Persist System Prompt:** Include the original `system` prompt in every API request within the same conversation.