# 🚨 COMPLETE OAUTH API BASELINE - ZERO DRIFT TOLERANCE

**CRITICAL: These are the EXACT OAuth API calls that MUST NOT change after refactoring**

Any deviation from these captures = REVERT IMMEDIATELY

## VALIDATION COMMANDS

**Test all providers:**
```bash
# Anthropic OAuth test
STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 mix run -e "
messages = [%{\"role\" => \"user\", \"content\" => \"test\"}]
TheMaestro.AgentLoop.run_turn(:anthropic, \"personal_oauth_claude\", \"claude-3-5-sonnet-20241022\", messages)
"

# OpenAI OAuth test  
STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 mix run -e "
messages = [%{\"role\" => \"user\", \"content\" => \"test\"}]
TheMaestro.AgentLoop.run_turn(:openai, \"personal_oauth_openai\", \"gpt-4o\", messages)
"

# Gemini OAuth test
STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 mix run -e "
messages = [%{\"role\" => \"user\", \"content\" => \"test\"}]
TheMaestro.AgentLoop.run_turn(:gemini, \"personal_oauth_gemini\", \"gemini-2.0-flash-exp\", messages)
"
```

---

## 1. ANTHROPIC OAUTH - BASELINE

### URL & METHOD
```
POST /v1/messages?beta=true
```
**CRITICAL:** MUST use `?beta=true` for OAuth sessions

### REQUIRED HEADERS (ALL MUST BE PRESENT)
```json
{
  "accept": ["application/json"],
  "accept-encoding": ["gzip, deflate, br"],
  "accept-language": ["*"],
  "anthropic-beta": ["claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14"],
  "anthropic-dangerous-direct-browser-access": ["true"],
  "anthropic-version": ["2023-06-01"],
  "authorization": ["Bearer sk-ant-oat01-..."],
  "connection": ["keep-alive"],
  "content-type": ["application/json"],
  "sec-fetch-mode": ["cors"],
  "user-agent": ["claude-cli/1.0.81 (external, cli)"],
  "x-app": ["cli"],
  "x-stainless-arch": ["arm64"],
  "x-stainless-helper-method": ["stream"],
  "x-stainless-lang": ["js"],
  "x-stainless-os": ["MacOS"],
  "x-stainless-package-version": ["0.60.0"],
  "x-stainless-retry-count": ["0"],
  "x-stainless-runtime": ["node"],
  "x-stainless-runtime-version": ["v20.19.4"],
  "x-stainless-timeout": ["600"]
}
```

### CRITICAL HEADER VALUES
- `anthropic-dangerous-direct-browser-access`: MUST be `"true"`
- `anthropic-beta`: MUST include ALL features exactly: `"claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14"`
- `user-agent`: MUST start with `"claude-cli/"`
- `authorization`: MUST be `"Bearer sk-ant-oat01-..."`
- ALL `x-stainless-*` headers MUST be present with exact values

### REQUIRED BODY STRUCTURE
```json
{
  "max_tokens": 512,
  "messages": [...],
  "metadata": {
    "user_id": "user_[hash]_account_cli_session_[uuid]"
  },
  "model": "claude-3-5-sonnet-20241022",
  "stream": true,
  "system": [
    {
      "cache_control": {"type": "ephemeral"},
      "text": "You are Claude Code, Anthropic's official CLI for Claude.",
      "type": "text"
    }
  ],
  "tools": [... ALL CLAUDE CODE TOOLS ...]
}
```

**CRITICAL BODY FIELDS:**
- `metadata.user_id`: MUST match pattern `"user_[hash]_account_cli_session_[uuid]"`
- `system`: MUST contain Claude Code system prompt with `cache_control.type = "ephemeral"`
- `tools`: MUST contain complete Claude Code tool definitions
- `stream`: MUST be `true`

---

## 2. OPENAI OAUTH - BASELINE

### URL & METHOD
```
POST https://chatgpt.com/backend-api/codex/responses
```
**CRITICAL:** Uses ChatGPT backend, not standard OpenAI API

### REQUIRED HEADERS (ALL MUST BE PRESENT)
```json
{
  "accept": ["text/event-stream"],
  "authorization": ["Bearer eyJhbGciOiJSUzI1NiIs..."],
  "chatgpt-account-id": ["9c44b38c-8b76-4290-9323-d089f0999028"],
  "content-type": ["application/json"],
  "openai-beta": ["responses=experimental"],
  "openai-organization": ["org-ITGn7KJlfM2zhSVi2W9xKuxU"],
  "originator": ["codex_cli_rs"],
  "session_id": ["8cf307fb-25e5-44a5-94f9-4699fa974ed2"],
  "user-agent": ["TheMaestro/1.0 (Conversation Test)"],
  "x-client-version": ["1.0.0"]
}
```

### CRITICAL HEADER VALUES
- `authorization`: MUST be JWT Bearer token starting with `"Bearer eyJ"`
- `chatgpt-account-id`: MUST be present for OAuth sessions
- `openai-beta`: MUST include `"responses=experimental"`
- `originator`: MUST be `"codex_cli_rs"`
- `session_id`: MUST be valid UUID format
- `accept`: MUST be `"text/event-stream"`

### REQUIRED BODY STRUCTURE
```json
{
  "input": [
    {
      "content": [
        {
          "text": "<conversation>\n\nuser: [prompt]\n\n</conversation>",
          "type": "input_text"
        }
      ],
      "role": "user",
      "type": "message"
    }
  ],
  "instructions": "You are a coding agent running in the Codex CLI...",
  "model": "gpt-4o",
  "parallel_tool_calls": false,
  "prompt_cache_key": "[session_id]",
  "store": false,
  "stream": true,
  "text": {"verbosity": "medium"},
  "tool_choice": "auto",
  "tools": [... CODEX TOOLS ...]
}
```

**CRITICAL BODY FIELDS:**
- `input[0].content[0].text`: MUST wrap user prompt in `"<conversation>\n\nuser: [prompt]\n\n</conversation>"`
- `instructions`: MUST contain full Codex CLI instructions
- `tools`: MUST contain Codex tool definitions (`shell`, `apply_patch`)
- `stream`: MUST be `true`

---

## 3. GEMINI OAUTH - BASELINE

### URL & METHOD
```
POST https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse
```
**CRITICAL:** Uses internal CloudCode endpoint, not public Gemini API

### REQUIRED HEADERS (ALL MUST BE PRESENT)
```json
{
  "accept": ["application/json"],
  "authorization": ["Bearer ya29.a0AS3H6Nw..."],
  "x-goog-api-client": ["gl-node/20.19.4"]
}
```

### CRITICAL HEADER VALUES
- `authorization`: MUST be OAuth Bearer token starting with `"Bearer ya29."`
- `x-goog-api-client`: MUST be `"gl-node/20.19.4"`

### REQUIRED BODY STRUCTURE  
```json
{
  "model": "gemini-2.5-pro",
  "project": "even-setup-7wxx5",
  "request": {
    "contents": [
      {
        "parts": [{"text": "[prompt]"}],
        "role": "user"
      }
    ],
    "generationConfig": {
      "temperature": 0,
      "topP": 1
    },
    "session_id": "[uuid]",
    "tools": [... GEMINI TOOLS ...]
  },
  "user_prompt_id": "[uuid]"
}
```

**CRITICAL BODY FIELDS:**
- `project`: MUST be valid Google Cloud project ID
- `model`: MUST be `"gemini-2.5-pro"` (not public model name)
- `tools`: MUST contain function declarations for shell/directory tools
- `session_id` and `user_prompt_id`: MUST be valid UUIDs

---

## VALIDATION SCRIPT

Save as `validate_oauth_baseline.sh`:

```bash
#!/bin/bash
set -e

echo "🔍 VALIDATING OAUTH API CALLS..."

validate_anthropic() {
  echo "Testing Anthropic OAuth..."
  OUTPUT=$(STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 timeout 15s mix run -e "
    messages = [%{\"role\" => \"user\", \"content\" => \"test\"}]
    TheMaestro.AgentLoop.run_turn(:anthropic, \"personal_oauth_claude\", \"claude-3-5-sonnet-20241022\", messages)
  " 2>&1 || true)
  
  # Check critical requirements
  if ! echo "$OUTPUT" | grep -q "anthropic-dangerous-direct-browser-access"; then
    echo "❌ CRITICAL: Missing anthropic-dangerous-direct-browser-access"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "claude-code-20250219,oauth-2025-04-20"; then
    echo "❌ CRITICAL: Missing/changed anthropic-beta features"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "/v1/messages?beta=true"; then
    echo "❌ CRITICAL: Wrong Anthropic endpoint"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "x-stainless"; then
    echo "❌ CRITICAL: Missing x-stainless headers"
    exit 1
  fi
  
  echo "✅ Anthropic OAuth validated"
}

validate_openai() {
  echo "Testing OpenAI OAuth..."
  OUTPUT=$(STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 timeout 15s mix run -e "
    messages = [%{\"role\" => \"user\", \"content\" => \"test\"}]
    TheMaestro.AgentLoop.run_turn(:openai, \"personal_oauth_openai\", \"gpt-4o\", messages)
  " 2>&1 || true)
  
  if ! echo "$OUTPUT" | grep -q "chatgpt.com/backend-api/codex/responses"; then
    echo "❌ CRITICAL: Wrong OpenAI endpoint"  
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "chatgpt-account-id"; then
    echo "❌ CRITICAL: Missing chatgpt-account-id"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "originator.*codex_cli_rs"; then
    echo "❌ CRITICAL: Missing/wrong originator"
    exit 1
  fi
  
  echo "✅ OpenAI OAuth validated"
}

validate_gemini() {
  echo "Testing Gemini OAuth..."  
  OUTPUT=$(STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 timeout 15s mix run -e "
    messages = [%{\"role\" => \"user\", \"content\" => \"test\"}]
    TheMaestro.AgentLoop.run_turn(:gemini, \"personal_oauth_gemini\", \"gemini-2.0-flash-exp\", messages)
  " 2>&1 || true)
  
  if ! echo "$OUTPUT" | grep -q "cloudcode-pa.googleapis.com"; then
    echo "❌ CRITICAL: Wrong Gemini endpoint"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "x-goog-api-client"; then
    echo "❌ CRITICAL: Missing x-goog-api-client"
    exit 1
  fi
  
  echo "✅ Gemini OAuth validated"
}

# Run all validations
validate_anthropic
validate_openai  
validate_gemini

echo "🎉 ALL OAUTH API VALIDATIONS PASSED!"
```

Make executable: `chmod +x validate_oauth_baseline.sh`

---

## EMERGENCY PROCEDURES

**If validation fails:**

1. **STOP ALL WORK IMMEDIATELY**
2. **Revert changes:** `git checkout HEAD~1`
3. **Run validation again** 
4. **Find the exact change that broke the API**
5. **Fix ONLY that specific change**
6. **DO NOT CONTINUE until validation passes**

---

## FILES

- Complete baseline: `COMPLETE_OAUTH_BASELINE.md`
- Validation script: `validate_oauth_baseline.sh`
- Raw captures: `*_oauth_baseline.log`

---

**⚠️  FINAL WARNING: These OAuth integrations are EXTREMELY fragile. Each provider has proprietary requirements that took significant effort to reverse-engineer. ANY changes to headers, endpoints, or request formats will break authentication and render the application unusable.**