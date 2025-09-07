# 🚨 CRITICAL: OAuth API Baseline Documentation

**ZERO DRIFT TOLERANCE - ANY CHANGES ARE BREAKING**

This document captures the EXACT OAuth API calls that MUST remain unchanged after any refactoring. Every header, every parameter, every endpoint MUST match exactly.

## How to Use This Document

### Before Refactoring:
1. Run: `STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 mix run -e "[test_code]"` to capture current API calls
2. Compare output against this baseline
3. Any differences = STOP REFACTORING

### After Refactoring:
1. Run same commands
2. Compare output character-by-character against this baseline  
3. ANY differences = REVERT IMMEDIATELY

## ANTHROPIC OAUTH - CAPTURED BASELINE

### CRITICAL REQUIREMENTS - MUST NOT CHANGE:

**URL:** 
```
POST /v1/messages?beta=true
```
- MUST use `beta=true` parameter for OAuth
- MUST be POST method
- MUST be to `/v1/messages` endpoint

**HEADERS - ALL MUST BE PRESENT:**
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

**CRITICAL HEADER DETAILS:**
- `anthropic-beta` MUST include ALL features: `claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14`
- `anthropic-dangerous-direct-browser-access` MUST be `"true"`
- `user-agent` MUST start with `claude-cli`
- ALL `x-stainless-*` headers MUST be present with exact values
- `authorization` MUST be Bearer token starting with `sk-ant-oat01-`

**REQUEST BODY STRUCTURE - ALL FIELDS REQUIRED:**
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
  "tools": [...]
}
```

**REQUIRED BODY FIELDS:**
- `metadata.user_id` MUST follow pattern `user_[hash]_account_cli_session_[uuid]`
- `system` array MUST contain Claude Code system prompt
- `tools` array MUST contain all Claude Code tools
- `stream` MUST be `true`
- `cache_control.type` MUST be `"ephemeral"`

## OPENAI OAUTH - TO BE CAPTURED

**TODO:** Run this command and capture output:
```bash
STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 mix run -e "
messages = [%{\"role\" => \"user\", \"content\" => \"say hello\"}]
case TheMaestro.AgentLoop.run_turn(:openai, \"personal_oauth_openai\", \"gpt-4o\", messages) do
  {:ok, res} -> IO.puts(\"Success\")
  {:error, reason} -> IO.puts(\"Error: #{inspect(reason)}\")
end
"
```

## GEMINI OAUTH - TO BE CAPTURED

**TODO:** Run this command and capture output:
```bash
STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 mix run -e "
messages = [%{\"role\" => \"user\", \"content\" => \"say hello\"}]
case TheMaestro.AgentLoop.run_turn(:gemini, \"personal_oauth_gemini\", \"gemini-2.0-flash-exp\", messages) do
  {:ok, res} -> IO.puts(\"Success\")  
  {:error, reason} -> IO.puts(\"Error: #{inspect(reason)}\")
end
"
```

## VALIDATION SCRIPT

Create this script to validate after refactoring:

```bash
#!/bin/bash
# validate_oauth_apis.sh

echo "🔍 Validating OAuth API calls after refactoring..."

# Test Anthropic
echo "Testing Anthropic OAuth..."
ANTHROPIC_OUTPUT=$(STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 mix run -e "
messages = [%{\"role\" => \"user\", \"content\" => \"test\"}]
case TheMaestro.AgentLoop.run_turn(:anthropic, \"personal_oauth_claude\", \"claude-3-5-sonnet-20241022\", messages) do
  {:ok, _} -> IO.puts(\"SUCCESS\")
  {:error, reason} -> IO.puts(\"ERROR: #{inspect(reason)}\")
end
" 2>&1)

# Check for required headers
if echo "$ANTHROPIC_OUTPUT" | grep -q "anthropic-dangerous-direct-browser-access"; then
  echo "✅ Anthropic dangerous browser access header present"
else
  echo "❌ CRITICAL: Missing anthropic-dangerous-direct-browser-access header"
  exit 1
fi

if echo "$ANTHROPIC_OUTPUT" | grep -q "claude-code-20250219,oauth-2025-04-20"; then
  echo "✅ Anthropic beta features present"  
else
  echo "❌ CRITICAL: Missing or changed anthropic-beta features"
  exit 1
fi

if echo "$ANTHROPIC_OUTPUT" | grep -q "x-stainless"; then
  echo "✅ Anthropic stainless headers present"
else
  echo "❌ CRITICAL: Missing x-stainless headers"
  exit 1
fi

if echo "$ANTHROPIC_OUTPUT" | grep -q "/v1/messages?beta=true"; then
  echo "✅ Anthropic endpoint correct"
else
  echo "❌ CRITICAL: Wrong Anthropic endpoint"  
  exit 1
fi

echo "✅ All OAuth API validations passed!"
```

## EMERGENCY ROLLBACK

If validation fails:

1. **STOP ALL WORK IMMEDIATELY**
2. Revert all changes: `git checkout HEAD~1` 
3. Run validation again
4. Identify what changed
5. Fix the specific change that broke the API call
6. **DO NOT CONTINUE** until validation passes

## FILE LOCATIONS

- This baseline: `/path/to/OAUTH_API_BASELINE.md`
- Validation script: `/path/to/validate_oauth_apis.sh`
- Captured responses: `/path/to/oauth_api_captures/`

---

**⚠️  WARNING: These API calls are EXTREMELY brittle. Anthropic, OpenAI, and Gemini have specific requirements that MUST be met exactly. Any deviation will cause authentication failures and broken integrations.**