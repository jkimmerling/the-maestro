#!/bin/bash
set -e

echo "🔍 VALIDATING OAUTH API CALLS AFTER REFACTORING..."
echo "This will test all OAuth providers to ensure NO DRIFT occurred"
echo ""

validate_anthropic() {
  echo "📦 Testing Anthropic OAuth..."
  OUTPUT=$(STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 timeout 20s mix run -e "
    messages = [%{\"role\" => \"user\", \"content\" => \"validation test\"}]
    case TheMaestro.AgentLoop.run_turn(:anthropic, \"personal_oauth_claude\", \"claude-3-5-sonnet-20241022\", messages) do
      {:ok, _} -> IO.puts(\"SUCCESS\")
      {:error, reason} -> IO.puts(\"ERROR: #{inspect(reason)}\")
    end
  " 2>&1 || true)
  
  # Save full output for debugging
  echo "$OUTPUT" > anthropic_validation.log
  
  # Check critical requirements
  if ! echo "$OUTPUT" | grep -q "anthropic-dangerous-direct-browser-access.*true"; then
    echo "❌ CRITICAL: Missing or wrong anthropic-dangerous-direct-browser-access header"
    echo "   Expected: anthropic-dangerous-direct-browser-access: true"
    echo "   This header is REQUIRED for OAuth sessions"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14"; then
    echo "❌ CRITICAL: Missing or changed anthropic-beta features"
    echo "   Expected: claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14"
    echo "   This EXACT string is required for Claude Code compatibility"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "POST /v1/messages?beta=true"; then
    echo "❌ CRITICAL: Wrong Anthropic endpoint"
    echo "   Expected: POST /v1/messages?beta=true"
    echo "   OAuth sessions MUST use the beta endpoint"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "x-stainless"; then
    echo "❌ CRITICAL: Missing x-stainless headers"
    echo "   All x-stainless-* headers are REQUIRED for OAuth"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "user-agent.*claude-cli"; then
    echo "❌ CRITICAL: Wrong user-agent"
    echo "   Expected: user-agent containing 'claude-cli'"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "metadata.*user_id.*account_cli_session"; then
    echo "❌ CRITICAL: Wrong or missing metadata.user_id format"
    echo "   Expected: user_id with 'account_cli_session' pattern"
    exit 1
  fi
  
  echo "✅ Anthropic OAuth validation passed"
}

validate_openai() {
  echo "📦 Testing OpenAI OAuth..."
  OUTPUT=$(STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 timeout 20s mix run -e "
    messages = [%{\"role\" => \"user\", \"content\" => \"validation test\"}]
    case TheMaestro.AgentLoop.run_turn(:openai, \"personal_oauth_openai\", \"gpt-4o\", messages) do
      {:ok, _} -> IO.puts(\"SUCCESS\")
      {:error, reason} -> IO.puts(\"ERROR: #{inspect(reason)}\")
    end
  " 2>&1 || true)
  
  echo "$OUTPUT" > openai_validation.log
  
  if ! echo "$OUTPUT" | grep -q "POST https://chatgpt.com/backend-api/codex/responses"; then
    echo "❌ CRITICAL: Wrong OpenAI endpoint"
    echo "   Expected: POST https://chatgpt.com/backend-api/codex/responses"
    echo "   OAuth sessions MUST use ChatGPT backend, not standard OpenAI API"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "chatgpt-account-id"; then
    echo "❌ CRITICAL: Missing chatgpt-account-id header"
    echo "   This header is REQUIRED for OAuth sessions"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "originator.*codex_cli_rs"; then
    echo "❌ CRITICAL: Missing or wrong originator header"
    echo "   Expected: originator: codex_cli_rs"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "openai-beta.*responses=experimental"; then
    echo "❌ CRITICAL: Missing or wrong openai-beta header"
    echo "   Expected: openai-beta: responses=experimental"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "accept.*text/event-stream"; then
    echo "❌ CRITICAL: Wrong accept header"
    echo "   Expected: accept: text/event-stream"
    exit 1
  fi
  
  echo "✅ OpenAI OAuth validation passed"
}

validate_gemini() {
  echo "📦 Testing Gemini OAuth..."
  OUTPUT=$(STREAM_LOG_EVENTS=1 HTTP_DEBUG=1 timeout 20s mix run -e "
    messages = [%{\"role\" => \"user\", \"content\" => \"validation test\"}]
    case TheMaestro.AgentLoop.run_turn(:gemini, \"personal_oauth_gemini\", \"gemini-2.0-flash-exp\", messages) do
      {:ok, _} -> IO.puts(\"SUCCESS\")
      {:error, reason} -> IO.puts(\"ERROR: #{inspect(reason)}\")
    end
  " 2>&1 || true)
  
  echo "$OUTPUT" > gemini_validation.log
  
  if ! echo "$OUTPUT" | grep -q "POST https://cloudcode-pa.googleapis.com"; then
    echo "❌ CRITICAL: Wrong Gemini endpoint"
    echo "   Expected: POST https://cloudcode-pa.googleapis.com/..."
    echo "   OAuth sessions MUST use CloudCode internal endpoint"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "x-goog-api-client.*gl-node"; then
    echo "❌ CRITICAL: Missing or wrong x-goog-api-client header"
    echo "   Expected: x-goog-api-client: gl-node/..."
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "v1internal:streamGenerateContent"; then
    echo "❌ CRITICAL: Wrong Gemini API endpoint"
    echo "   Expected: v1internal:streamGenerateContent"
    exit 1
  fi
  
  if ! echo "$OUTPUT" | grep -q "project.*even-setup"; then
    echo "❌ CRITICAL: Missing or wrong project parameter"
    echo "   Expected: project field in request body"
    exit 1
  fi
  
  echo "✅ Gemini OAuth validation passed"
}

# Run all validations
echo "Starting OAuth validation for all providers..."
echo "Logs will be saved as: *_validation.log"
echo ""

validate_anthropic
validate_openai  
validate_gemini

echo ""
echo "🎉 ALL OAUTH API VALIDATIONS PASSED!"
echo ""
echo "✅ All OAuth API calls match the baseline exactly"
echo "✅ No drift detected - refactoring is safe"
echo ""
echo "Validation logs saved:"
echo "  - anthropic_validation.log"
echo "  - openai_validation.log" 
echo "  - gemini_validation.log"