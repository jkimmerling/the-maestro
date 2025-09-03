# Provider Tool Interaction Examples

This document provides concrete examples of a full tool-use cycle for three different providers: Gemini, Anthropic, and Codex (using the OpenAI Responses API). The goal is to illustrate the exact on-wire request and response formats to aid in the development of a translation layer.

Each example follows a four-step process:
1.  **User Request:** The initial prompt from the user.
2.  **Model Tool Call:** The model's response, requesting a tool be called.
3.  **Tool Result Submission:** The client executes the tool and submits the result back to the model.
4.  **Final Model Response:** The model's answer, incorporating the tool's output.

---

## 1. Gemini API

### Example A: Shell Command (`run_shell_command`)

**1. User Request**

The user's prompt is sent as the last message in the `contents` array.

```json
POST /v1beta/models/gemini-1.5-pro:generateContent
{
  "contents": [
    {
      "role": "user",
      "parts": [ { "text": "Please list the files in the current directory." } ]
    }
  ],
  "tools": [
    {
      "functionDeclarations": [
        {
          "name": "run_shell_command",
          "description": "Executes a shell command.",
          "parametersJsonSchema": {
            "type": "object",
            "properties": {
              "command": { "type": "string" }
            },
            "required": ["command"]
          }
        }
      ]
    }
  ]
}
```

**2. Model Tool Call**

The model responds with a `functionCall` part.

```json
{
  "candidates": [
    {
      "content": {
        "role": "model",
        "parts": [
          {
            "functionCall": {
              "id": "fc-12345",
              "name": "run_shell_command",
              "args": {
                "command": "ls -F"
              }
            }
          }
        ]
      }
    }
  ]
}
```

**3. Tool Result Submission**

The client executes `ls -F` and sends the output back in a `user` role message containing a `functionResponse` part.

```json
POST /v1beta/models/gemini-1.5-pro:generateContent
{
  "contents": [
    {
      "role": "user",
      "parts": [ { "text": "Please list the files in the current directory." } ]
    },
    {
      "role": "model",
      "parts": [
        { "functionCall": { "id": "fc-12345", "name": "run_shell_command", "args": { "command": "ls -F" } } }
      ]
    },
    {
      "role": "user",
      "parts": [
        {
          "functionResponse": {
            "id": "fc-12345",
            "name": "run_shell_command",
            "response": {
              "output": "Command: ls -F\nDirectory: (root)\nOutput: README.md\nsrc/\npackage.json\n"
            }
          }
        }
      ]
    }
  ]
}
```

**4. Final Model Response**

```json
{
  "candidates": [
    {
      "content": {
        "role": "model",
        "parts": [
          {
            "text": "Okay, I see the following files and directories: README.md, src/, and package.json."
          }
        ]
      }
    }
  ]
}
```

### Example B: File Read (`read_file`)

**1. User Request**

```json
POST /v1beta/models/gemini-1.5-pro:generateContent
{
  "contents": [
    { "role": "user", "parts": [ { "text": "What is in the README?" } ] }
  ],
  "tools": [ { "functionDeclarations": [ { "name": "read_file", "description": "Reads a file.", "parametersJsonSchema": { "type": "object", "properties": { "absolute_path": { "type": "string" } }, "required": ["absolute_path"] } } ] } ]
}
```

**2. Model Tool Call**

```json
{
  "candidates": [ { "content": { "role": "model", "parts": [ { "functionCall": { "id": "fc-67890", "name": "read_file", "args": { "absolute_path": "/path/to/README.md" } } } ] } } ]
}
```

**3. Tool Result Submission**

```json
POST /v1beta/models/gemini-1.5-pro:generateContent
{
  "contents": [
    { "role": "user", "parts": [ { "text": "What is in the README?" } ] },
    { "role": "model", "parts": [ { "functionCall": { "id": "fc-67890", "name": "read_file", "args": { "absolute_path": "/path/to/README.md" } } } ] },
    { "role": "user", "parts": [ { "functionResponse": { "id": "fc-67890", "name": "read_file", "response": { "output": "# Project Title\nThis is a sample project." } } } ] }
  ]
}
```

**4. Final Model Response**

```json
{
  "candidates": [ { "content": { "role": "model", "parts": [ { "text": "The README contains a title, '# Project Title', and a description, 'This is a sample project.'" } ] } } ]
}
```

---

## 2. Anthropic API

### Example A: Shell Command (`run_shell_command`)

**1. User Request**

```json
POST /v1/messages
{
  "model": "claude-3-opus-20240229",
  "messages": [
    { "role": "user", "content": "Please list the files in the current directory." }
  ],
  "tools": [
    {
      "name": "run_shell_command",
      "description": "Executes a shell command.",
      "input_schema": {
        "type": "object",
        "properties": { "command": { "type": "string" } },
        "required": ["command"]
      }
    }
  ]
}
```

**2. Model Tool Call**

The model responds with a `tool_use` content block.

```json
{
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "Okay, I will list the files."
    },
    {
      "type": "tool_use",
      "id": "tool-use-12345",
      "name": "run_shell_command",
      "input": {
        "command": "ls -F"
      }
    }
  ]
}
```

**3. Tool Result Submission**

The client sends a new `user` message containing a `tool_result` block.

```json
POST /v1/messages
{
  "model": "claude-3-opus-20240229",
  "messages": [
    { "role": "user", "content": "Please list the files in the current directory." },
    {
      "role": "assistant",
      "content": [
        { "type": "text", "text": "Okay, I will list the files." },
        { "type": "tool_use", "id": "tool-use-12345", "name": "run_shell_command", "input": { "command": "ls -F" } }
      ]
    },
    {
      "role": "user",
      "content": [
        {
          "type": "tool_result",
          "tool_use_id": "tool-use-12345",
          "content": "README.md\nsrc/\npackage.json"
        }
      ]
    }
  ]
}
```

**4. Final Model Response**

```json
{
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "I found these files and directories: README.md, src/, and package.json."
    }
  ]
}
```

### Example B: File Read (`read_file`)

**1. User Request**

```json
POST /v1/messages
{
  "model": "claude-3-opus-20240229",
  "messages": [ { "role": "user", "content": "What is in the README?" } ],
  "tools": [ { "name": "read_file", "description": "Reads a file.", "input_schema": { "type": "object", "properties": { "absolute_path": { "type": "string" } }, "required": ["absolute_path"] } } ]
}
```

**2. Model Tool Call**

```json
{
  "role": "assistant",
  "content": [ { "type": "tool_use", "id": "tool-use-67890", "name": "read_file", "input": { "absolute_path": "/path/to/README.md" } } ]
}
```

**3. Tool Result Submission**

```json
POST /v1/messages
{
  "model": "claude-3-opus-20240229",
  "messages": [
    { "role": "user", "content": "What is in the README?" },
    { "role": "assistant", "content": [ { "type": "tool_use", "id": "tool-use-67890", "name": "read_file", "input": { "absolute_path": "/path/to/README.md" } } ] },
    { "role": "user", "content": [ { "type": "tool_result", "tool_use_id": "tool-use-67890", "content": "# Project Title\nThis is a sample project." } ] }
  ]
}
```

**4. Final Model Response**

```json
{
  "role": "assistant",
  "content": [ { "type": "text", "text": "The README file contains the title '# Project Title' and the description 'This is a sample project.'" } ]
}
```

---

## 3. Codex (OpenAI Responses API)

### Example A: Shell Command (`shell`)

**1. User Request**

The request uses an `input` array of `ResponseItem` objects and an `instructions` string for the system prompt.

```json
POST /v1/responses
{
  "model": "gpt-5",
  "instructions": "You are a helpful assistant.",
  "input": [
    {
      "type": "message",
      "role": "user",
      "content": [ { "type": "input_text", "text": "Please list the files in the current directory." } ]
    }
  ],
  "tools": [
    {
      "type": "function",
      "name": "shell",
      "description": "Runs a shell command.",
      "parameters": {
        "type": "object",
        "properties": { "command": { "type": "array", "items": { "type": "string" } } },
        "required": ["command"]
      }
    }
  ]
}
```

**2. Model Tool Call**

The model responds with a `function_call` `ResponseItem`.

```json
{
  "type": "response.output_item.done",
  "item": {
    "type": "function_call",
    "call_id": "call_12345",
    "name": "shell",
    "arguments": "{\"command\":[\"ls\", \"-F\"]}"
  }
}
```

**3. Tool Result Submission**

The client executes the command and submits the result as a `function_call_output` item in the `input` array of the next request.

```json
POST /v1/responses
{
  "model": "gpt-5",
  "instructions": "You are a helpful assistant.",
  "input": [
    { "type": "message", "role": "user", "content": [ { "type": "input_text", "text": "Please list the files in the current directory." } ] },
    { "type": "function_call", "call_id": "call_12345", "name": "shell", "arguments": "{\"command\":[\"ls\", \"-F\"]}" },
    {
      "type": "function_call_output",
      "call_id": "call_12345",
      "output": "{\"output\":\"README.md\\nsrc/\\npackage.json\\n\",\"metadata\":{\"exit_code\":0}}"
    }
  ]
}
```

**4. Final Model Response**

The model responds with a final text message.

```json
{
  "type": "response.output_item.done",
  "item": {
    "type": "message",
    "role": "assistant",
    "content": [
      {
        "type": "output_text",
        "text": "Certainly. The files are: README.md, src/, and package.json."
      }
    ]
  }
}
```

### Example B: File Read (`read_file`)

**1. User Request**

```json
POST /v1/responses
{
  "model": "gpt-5",
  "instructions": "You are a helpful assistant.",
  "input": [ { "type": "message", "role": "user", "content": [ { "type": "input_text", "text": "What is in the README?" } ] } ],
  "tools": [ { "type": "function", "name": "read_file", "description": "Reads a file.", "parameters": { "type": "object", "properties": { "path": { "type": "string" } }, "required": ["path"] } } ]
}
```

**2. Model Tool Call**

```json
{
  "type": "response.output_item.done",
  "item": {
    "type": "function_call",
    "call_id": "call_67890",
    "name": "read_file",
    "arguments": "{\"path\":\"/path/to/README.md\"}"
  }
}
```

**3. Tool Result Submission**

```json
POST /v1/responses
{
  "model": "gpt-5",
  "instructions": "You are a helpful assistant.",
  "input": [
    { "type": "message", "role": "user", "content": [ { "type": "input_text", "text": "What is in the README?" } ] },
    { "type": "function_call", "call_id": "call_67890", "name": "read_file", "arguments": "{\"path\":\"/path/to/README.md\"}" },
    { "type": "function_call_output", "call_id": "call_67890", "output": "{\"output\":\"# Project Title\\nThis is a sample project.\"}" }
  ]
}
```

**4. Final Model Response**

```json
{
  "type": "response.output_item.done",
  "item": {
    "type": "message",
    "role": "assistant",
    "content": [ { "type": "output_text", "text": "The README says: '# Project Title' followed by 'This is a sample project.'" } ]
  }
}
```
