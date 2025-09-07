# DRY Refactoring Plan for TheMaestro

## Executive Summary
This document outlines a comprehensive refactoring plan to improve code organization, reduce duplication, and establish better separation of concerns in the TheMaestro codebase, while ensuring API calls remain unchanged and brittle integrations are preserved.

## Current Issues Identified

### 1. Directory Organization Issues
- 20 files directly in `/lib/the_maestro/` causing clutter
- Mixed concerns (OAuth, auth, conversations, agents) in root directory
- No clear domain boundaries

### 2. Code Duplication Across Providers
Each provider (Anthropic, OpenAI, Gemini) has nearly identical implementations for:
- `create_session/1` - 90% duplicated logic
- `delete_session/1` - 100% duplicated logic  
- `test_connection/1` - 95% duplicated logic
- `validate_api_key/1` - Similar patterns with minor provider-specific validation
- Error handling patterns repeated across modules

### 3. Anti-Pattern Violations
Based on Elixir documentation review:
- **Primitive Obsession**: Using maps/strings where structs would be clearer
- **Long Parameter Lists**: Some functions passing 5+ arguments
- **Mixed Responsibilities**: Auth module handles OAuth, tokens, and persistence

## Proposed Directory Structure

```
lib/the_maestro/
├── core/                    # Core business logic
│   ├── agents/             
│   │   ├── agent_loop.ex
│   │   ├── agents.ex
│   │   └── personas.ex
│   ├── conversations/
│   │   └── conversations.ex
│   └── prompts/
│       └── prompts.ex
│
├── auth/                    # Authentication domain
│   ├── oauth/
│   │   ├── callback_plug.ex
│   │   ├── callback_runtime.ex
│   │   ├── state.ex
│   │   └── token_refresh_worker.ex (if exists)
│   ├── persistence/
│   │   └── saved_authentication.ex
│   ├── auth.ex            # Main auth coordinator
│   └── vault.ex
│
├── providers/              # Keep existing structure
│   ├── anthropic/
│   ├── openai/
│   ├── gemini/
│   ├── behaviours/
│   ├── http/
│   └── shared/            # NEW: Shared provider utilities
│       ├── api_key_helper.ex
│       ├── session_helper.ex
│       └── connection_tester.ex
│
├── infrastructure/         # System-level concerns
│   ├── application.ex
│   ├── repo.ex
│   ├── mailer.ex
│   └── config_migration.ex
│
├── utils/                  # Cross-cutting utilities
│   ├── debug_log.ex
│   ├── streaming.ex
│   └── types.ex
│
└── tools/                  # Keep existing tools directory
```

## Shared Code Extraction Plan

### 1. API Key Provider Helper Module
**File**: `/lib/the_maestro/providers/shared/api_key_helper.ex`

```elixir
defmodule TheMaestro.Providers.Shared.APIKeyHelper do
  @moduledoc """
  Shared utilities for API key providers.
  IMPORTANT: Only extraction of common patterns, no changes to actual API calls.
  """
  
  alias TheMaestro.Provider
  alias TheMaestro.SavedAuthentication
  
  # Common create_session logic with provider-specific callbacks
  def create_session(provider, opts, validate_fn) do
    name = Keyword.get(opts, :name)
    credentials = Keyword.get(opts, :credentials) || %{}
    api_key = extract_api_key(credentials)
    
    with :ok <- Provider.validate_session_name(name),
         :ok <- validate_fn.(api_key),
         {:ok, _sa} <- persist_session(provider, name, api_key, credentials) do
      {:ok, name}
    else
      {:error, _} = err -> err
    end
  end
  
  # Common delete_session logic
  def delete_session(provider, auth_type, session_id) do
    case SavedAuthentication.delete_named_session(provider, auth_type, session_id) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, _} = err -> err
    end
  end
  
  defp extract_api_key(credentials) do
    Map.get(credentials, "api_key") || Map.get(credentials, :api_key)
  end
  
  defp persist_session(provider, name, api_key, credentials) do
    SavedAuthentication.upsert_named_session(provider, :api_key, name, %{
      credentials: build_credentials(provider, api_key, credentials),
      expires_at: nil
    })
  end
  
  defp build_credentials(:gemini, api_key, credentials) do
    # Gemini-specific: include user_project if present
    user_project = Map.get(credentials, "user_project") || Map.get(credentials, :user_project)
    %{api_key: api_key, user_project: user_project}
  end
  
  defp build_credentials(_, api_key, _), do: %{api_key: api_key}
end
```

### 2. Connection Test Helper
**File**: `/lib/the_maestro/providers/shared/connection_tester.ex`

```elixir
defmodule TheMaestro.Providers.Shared.ConnectionTester do
  @moduledoc """
  Shared connection testing logic.
  Endpoints remain provider-specific and unchanged.
  """
  
  def test_connection(req, endpoint) do
    case Req.request(req, method: :get, url: endpoint) do
      {:ok, %Req.Response{status: 200}} ->
        :ok
        
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, format_body(body)}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp format_body(body) when is_binary(body), do: body
  defp format_body(body), do: Jason.encode!(body)
end
```

### 3. Refactored Provider Modules (Example: Anthropic)
```elixir
defmodule TheMaestro.Providers.Anthropic.APIKey do
  @behaviour TheMaestro.Providers.Behaviours.Auth
  @behaviour TheMaestro.Providers.Behaviours.APIKeyProvider
  
  alias TheMaestro.Providers.Shared.{APIKeyHelper, ConnectionTester}
  alias TheMaestro.Providers.Http.ReqClientFactory
  
  @impl true
  def create_session(opts) when is_list(opts) do
    APIKeyHelper.create_session(:anthropic, opts, &validate_api_key/1)
  end
  def create_session(_), do: {:error, :invalid_options}
  
  @impl true
  def delete_session(session_id) when is_binary(session_id) do
    APIKeyHelper.delete_session(:anthropic, :api_key, session_id)
  end
  
  @impl true
  def validate_api_key(api_key) when is_binary(api_key) do
    if String.trim(api_key) == "", do: {:error, :invalid_api_key}, else: :ok
  end
  def validate_api_key(_), do: {:error, :invalid_api_key}
  
  @impl true
  def create_client(api_key, opts \\ []) do
    with :ok <- validate_api_key(api_key),
         {:ok, req} <- ReqClientFactory.create_client(:anthropic, :api_key, opts) do
      # CRITICAL: Keep provider-specific header exactly as is
      req = Req.Request.put_header(req, "x-api-key", api_key)
      {:ok, req}
    end
  end
  
  @impl true
  def test_connection(%Req.Request{} = req) do
    # CRITICAL: Keep provider-specific endpoint exactly as is
    ConnectionTester.test_connection(req, "/v1/models")
  end
  
  @impl true
  def refresh_tokens(_session_id), do: {:error, :not_applicable}
end
```

## Implementation Safety Guidelines

### CRITICAL: What NOT to Change
1. **API Headers**: Each provider's specific header format must remain exactly as is:
   - Anthropic: `"x-api-key"`
   - OpenAI: `"authorization", "Bearer " <> api_key`
   - Gemini: `"x-goog-api-key"`

2. **API Endpoints**: Keep all provider-specific endpoints unchanged:
   - Anthropic: `/v1/models`, `/v1/messages`
   - OpenAI: `/v1/models`, `/v1/chat/completions`
   - Gemini: `/v1beta/models`

3. **Request Body Structures**: No changes to JSON request bodies
4. **OAuth Flows**: Keep all OAuth implementation details intact
5. **Streaming Logic**: Do not modify any streaming-specific code

### What CAN be Safely Refactored
1. **Common validation logic** (session names, basic input validation)
2. **Error handling patterns** (return tuple formatting)
3. **Database persistence calls** (SavedAuthentication interactions)
4. **Logging patterns**
5. **Test connection response handling** (while keeping endpoints intact)

## Migration Strategy

### Phase 1: Create Shared Modules (No Breaking Changes)
1. Create `/providers/shared/` directory
2. Implement helper modules with extracted common logic
3. Write comprehensive tests for helper modules
4. No changes to existing modules yet

### Phase 2: Update Provider Modules (With Fallback)
1. Update one provider at a time (start with least critical)
2. Keep original logic commented for quick rollback
3. Run full test suite after each provider update
4. Monitor for any API call failures

### Phase 3: Directory Reorganization
1. Create new directory structure
2. Move files one domain at a time:
   - Start with `/utils/` (least risky)
   - Then `/infrastructure/`
   - Then `/auth/`
   - Finally `/core/`
3. Update all module references
4. Run full test suite and integration tests

### Phase 4: Cleanup
1. Remove commented old code after stability period
2. Update documentation
3. Add module documentation for new structure

## Testing Requirements

### Before ANY Changes
```bash
# Capture baseline
mix test > baseline_test_results.txt
mix credo --strict > baseline_credo.txt
mix dialyzer > baseline_dialyzer.txt
```

### After Each Phase
```bash
# Run full test suite
mix test

# Check for compilation warnings
mix compile --warnings-as-errors

# Run static analysis
mix credo --strict
mix dialyzer

# Manual API testing for each provider
# (Create test script if not exists)
```

## Rollback Plan
1. All changes in separate branch: `dry-refactor`
2. Keep original code commented for 1 week after deployment
3. Feature flag for using new shared modules (if applicable)
4. Database backup before any SavedAuthentication schema changes
5. Ability to hot-swap back to original modules if issues detected

## Success Metrics
- [ ] 50% reduction in duplicated code across providers
- [ ] All existing tests pass without modification
- [ ] No changes to API request/response formats
- [ ] Improved module cohesion (measured by credo)
- [ ] Clearer directory structure (developer survey)
- [ ] No production incidents related to refactoring

## Timeline Estimate
- Phase 1: 2-3 hours (create shared modules)
- Phase 2: 4-6 hours (update providers with testing)
- Phase 3: 2-3 hours (directory reorganization)
- Phase 4: 1 hour (cleanup)
- Total: ~2 days with thorough testing

## Notes and Warnings
- This refactoring focuses on DRY principles while maintaining 100% API compatibility
- Any changes to API calls, headers, or request formats are STRICTLY FORBIDDEN
- Provider-specific validation logic (e.g., OpenAI's "sk-" prefix check) must remain in provider modules
- Consider adding integration tests before starting if they don't exist