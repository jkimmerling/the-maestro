# 🚨 EMERGENCY COURSE CORRECT PRD
# Universal Provider Architecture Overhaul

**Document Type:** Emergency Product Requirements Document  
**Priority:** CRITICAL  
**Status:** ACTIVE  
**Version:** 1.0  
**Date:** 2025-08-30  

---

## 📋 EXECUTIVE SUMMARY

**CRITICAL SITUATION:** Epic 1 (stories 1.1-1.6) has resulted in severe architectural fragmentation that prevents scalable provider integration and violates core system requirements. Immediate course correction required.

**SOLUTION:** Complete architectural overhaul implementing universal provider interface with dynamic module resolution, standardized authentication patterns, and comprehensive end-to-end testing for ALL provider/auth combinations.

**IMPACT:** Transform fragmented implementation into modular, extensible system supporting drop-in provider integration while meeting all universal requirements (token refresh, named auths, model listing, streaming).

---

## 🚨 CRITICAL SITUATION ASSESSMENT

### Current State Analysis - **FRAGMENTATION IDENTIFIED**

#### Files Created/Modified Across Stories 1.1-1.6

**CREATED FILES:**
```
lib/the_maestro/providers/client.ex              # Generic Tesla HTTP client (1.1)
lib/the_maestro/providers/anthropic_config.ex    # Provider-specific config (1.2)
lib/the_maestro/providers/openai_config.ex       # Provider-specific config (1.5)
lib/the_maestro/auth.ex                           # Mixed OAuth functions (1.4, 1.6)
lib/the_maestro/streaming.ex                     # Generic streaming interface (1.6)
lib/the_maestro/streaming/anthropic_handler.ex   # Provider streaming (1.6)
lib/the_maestro/streaming/openai_handler.ex      # Provider streaming (1.6)
lib/the_maestro/streaming/gemini_handler.ex      # Provider streaming (1.6)
lib/the_maestro/streaming/stream_handler.ex      # Generic streaming behavior (1.6)
lib/the_maestro/saved_authentication.ex          # Credential storage (1.4)
lib/the_maestro/workers/token_refresh_worker.ex  # Background refresh (1.4)
```

**MODIFIED FILES:**
```
lib/the_maestro/application.ex     # Added 3 separate Finch pools
config/dev.exs                     # Provider-specific settings
config/test.exs                    # Provider-specific settings  
config/prod.exs                    # Provider-specific settings
mix.exs                           # Dependencies for Tesla, Finch
```

#### **CRITICAL FRAGMENTATION ISSUES**

1. **❌ NO CENTRAL PROVIDER INTERFACE**
   - Each provider requires different function calls
   - No standardized API across providers
   - Hard-coded provider switching throughout codebase

2. **❌ AUTH LOGIC SCATTERED** 
   - OAuth mixed in single `Auth` module with provider conditionals
   - No consistent authentication patterns
   - Provider-specific configs duplicated with similar patterns

3. **❌ NO DYNAMIC MODULE LOADING**
   - Static imports and hard-coded references
   - Cannot add new providers without code changes
   - Violates open/closed principle

4. **❌ CONFIGURATION CHAOS**
   - 3 separate config modules with duplicated patterns
   - Environment-specific duplication across providers
   - No unified configuration management

5. **❌ MISSING UNIVERSAL REQUIREMENTS**
   - Token refresh: Only Anthropic implemented
   - Named auths: Not implemented for any provider
   - Model listing: Not implemented for any provider
   - Context management: Not implemented

6. **❌ INCOMPLETE STREAMING STANDARDIZATION**
   - Recently added streaming but not applied to all providers
   - E2E testing incomplete
   - No validation of streaming architecture compliance

### Performance & Maintainability Risks

**TECHNICAL DEBT QUANTIFICATION:**
- **Code Duplication:** ~40% across provider configs and auth patterns
- **Testing Gaps:** Missing E2E tests for 83% of provider/auth combinations
- **Maintenance Overhead:** 3x increase per new provider addition
- **Bug Risk:** High due to scattered auth logic and duplicate patterns

**USER IMPACT:**
- Cannot use multiple OAuth sessions per provider
- No token refresh for OpenAI OAuth (security risk)
- No model listing capability (limits user choice)
- Inconsistent streaming behavior across providers

---

## 🏗️ UNIVERSAL PROVIDER ARCHITECTURE SPECIFICATION

### Core Design Principles

1. **Universal Interface**: Single entry point for all provider operations
2. **Dynamic Resolution**: Atom-based module path generation
3. **Provider Isolation**: Complete separation of provider-specific logic
4. **Drop-in Integration**: New providers work without core changes
5. **Feature Parity**: All providers support all authentication types and features

### Generic Provider Interface Design

#### **Primary Interface Module: `TheMaestro.Provider`**

```elixir
defmodule TheMaestro.Provider do
  @moduledoc """
  Universal provider interface for all LLM providers.
  Supports dynamic module resolution and standardized operations.
  """

  # Authentication Management
  @spec create_session(provider(), auth_type(), keyword()) :: {:ok, session_id()} | {:error, term()}
  def create_session(provider, auth_type, opts \\ [])

  @spec delete_session(provider(), auth_type(), session_id()) :: :ok | {:error, term()}
  def delete_session(provider, auth_type, session_id)

  @spec refresh_tokens(provider(), session_id()) :: {:ok, tokens()} | {:error, term()}
  def refresh_tokens(provider, session_id)

  # Model Management  
  @spec list_models(provider(), auth_type(), session_id()) :: {:ok, [model()]} | {:error, term()}
  def list_models(provider, auth_type, session_id)

  # Streaming Conversations
  @spec stream_chat(provider(), session_id(), messages(), keyword()) :: {:ok, stream()} | {:error, term()}
  def stream_chat(provider, session_id, messages, opts \\ [])

  # Context Management
  @spec list_context_chunks(provider(), session_id(), context_id()) :: {:ok, [chunk()]} | {:error, term()}
  def list_context_chunks(provider, session_id, context_id)

  @spec delete_context_chunk(provider(), session_id(), context_id(), chunk_id()) :: :ok | {:error, term()}
  def delete_context_chunk(provider, session_id, context_id, chunk_id)

  # Provider Discovery
  @spec list_providers() :: [provider()]
  def list_providers()

  @spec provider_capabilities(provider()) :: %{auth_types: [auth_type()], features: [feature()]}
  def provider_capabilities(provider)
end
```

#### **Usage Examples:**

```elixir
# Create named OAuth sessions
{:ok, "work_claude"} = TheMaestro.Provider.create_session(:anthropic, :oauth, name: "work_claude")
{:ok, "dev_gpt"} = TheMaestro.Provider.create_session(:openai, :oauth, name: "dev_gpt")  

# Create named API key sessions
{:ok, "prod_anthropic"} = TheMaestro.Provider.create_session(:anthropic, :api_key, 
  name: "prod_anthropic", api_key: "sk-ant-...")

# List models for any auth type
{:ok, models} = TheMaestro.Provider.list_models(:anthropic, :oauth, "work_claude")
{:ok, models} = TheMaestro.Provider.list_models(:openai, :api_key, "prod_gpt")

# Stream conversations with any provider
{:ok, stream} = TheMaestro.Provider.stream_chat(:anthropic, "work_claude", messages,
  context_id: "chat_123", system_prompt: "You are a helpful assistant")

# Refresh tokens automatically
{:ok, new_tokens} = TheMaestro.Provider.refresh_tokens(:openai, "dev_gpt")

# Manage context chunks
{:ok, chunks} = TheMaestro.Provider.list_context_chunks(:anthropic, "work_claude", "chat_123")
:ok = TheMaestro.Provider.delete_context_chunk(:anthropic, "work_claude", "chat_123", "chunk_5")
```

### Dynamic Module Resolution System

#### **Module Path Generation Algorithm:**

```elixir
defmodule TheMaestro.Provider.Resolver do
  @moduledoc """
  Dynamic module resolution for provider operations.
  Maps atoms to module paths and validates capabilities.
  """

  # Core resolution logic
  @spec resolve_module(provider(), operation()) :: {:ok, module()} | {:error, :module_not_found}
  def resolve_module(provider, operation) do
    module_name = build_module_path(provider, operation)
    
    case Code.ensure_loaded?(module_name) do
      true -> {:ok, module_name}
      false -> {:error, :module_not_found}
    end
  end

  # Examples of dynamic resolution:
  # resolve_module(:anthropic, :oauth) -> TheMaestro.Providers.Anthropic.OAuth
  # resolve_module(:openai, :streaming) -> TheMaestro.Providers.OpenAI.Streaming  
  # resolve_module(:gemini, :models) -> TheMaestro.Providers.Gemini.Models
end
```

### Provider Folder Structure

```
lib/the_maestro/providers/
├── provider.ex                    # Generic interface
├── resolver.ex                    # Dynamic module resolution
├── behaviors/
│   ├── oauth_provider.ex          # OAuth behavior definition
│   ├── api_key_provider.ex        # API key behavior definition
│   ├── streaming_provider.ex      # Streaming behavior definition
│   └── model_provider.ex          # Model listing behavior definition
├── anthropic/
│   ├── oauth.ex                   # OAuth implementation
│   ├── api_key.ex                 # API key implementation  
│   ├── streaming.ex               # Streaming implementation
│   ├── models.ex                  # Model listing implementation
│   └── config.ex                  # Provider configuration
├── openai/  
│   ├── oauth.ex                   # OAuth implementation
│   ├── api_key.ex                 # API key implementation
│   ├── streaming.ex               # Streaming implementation
│   ├── models.ex                  # Model listing implementation
│   └── config.ex                  # Provider configuration
└── gemini/
    ├── oauth.ex                   # OAuth implementation (TBD)
    ├── api_key.ex                 # API key implementation
    ├── streaming.ex               # Streaming implementation  
    ├── models.ex                  # Model listing implementation
    └── config.ex                  # Provider configuration
```

---

## 🔐 PROVIDER-SPECIFIC REQUIREMENTS

### Universal Authentication Framework

#### **Named Authentication Management**
- Support multiple concurrent authentications per provider
- User-defined session names (e.g., "work_claude", "personal_gpt", "dev_gemini")
- Session persistence across application restarts
- Automatic cleanup of expired sessions

#### **Token Refresh Automation**
- Automatic OAuth token refresh for ALL providers
- Background token refresh jobs (extend existing worker)
- Grace period handling before token expiration
- Retry logic for failed refresh attempts
- User notification for manual re-authentication when needed

### Anthropic Provider Requirements

#### **OAuth Implementation (`TheMaestro.Providers.Anthropic.OAuth`)**
- **Authorization Flow:** Manual code paste pattern
- **Client ID:** `"9d1c250a-e61b-44d9-88ed-5944d1962f5e"`
- **Authorization Endpoint:** `"https://claude.ai/oauth/authorize"`
- **Token Endpoint:** `"https://console.anthropic.com/v1/oauth/token"`
- **Redirect URI:** `"https://console.anthropic.com/oauth/code/callback"`
- **Scopes:** `["org:create_api_key", "user:profile", "user:inference"]`
- **Request Format:** JSON

```elixir
# E2E Test Flow for Anthropic OAuth:
{:ok, {auth_url, pkce_params}} = Anthropic.OAuth.generate_url(session_name)
IO.puts("Visit: #{auth_url}")
auth_code = IO.gets("Paste authorization code: ") |> String.trim()
{:ok, tokens} = Anthropic.OAuth.exchange_code(auth_code, pkce_params, session_name)
{:ok, api_key} = Anthropic.OAuth.extract_api_key(tokens, session_name)
```

#### **API Key Implementation (`TheMaestro.Providers.Anthropic.ApiKey`)**  
- Direct API key authentication with `x-api-key` header
- Support for multiple named API key sessions
- API key validation and error handling

#### **Streaming Implementation (`TheMaestro.Providers.Anthropic.Streaming`)**
- Use existing `TheMaestro.Streaming.AnthropicHandler`
- Content block delta processing
- Tool use streaming support
- Usage statistics tracking

### OpenAI Provider Requirements

#### **OAuth Implementation (`TheMaestro.Providers.OpenAI.OAuth`)**
- **Authorization Flow:** Callback server pattern  
- **Client ID:** `"app_EMoamEEZ73f0CkXaXp7hrann"`
- **Authorization Endpoint:** `"https://auth.openai.com/oauth/authorize"`
- **Token Endpoint:** `"https://auth.openai.com/oauth/token"`
- **Redirect URI:** `"http://localhost:8080/auth/callback"` (configurable port)
- **Scopes:** `["openid", "profile", "email", "offline_access"]`
- **Request Format:** Form-encoded

```elixir
# E2E Test Flow for OpenAI OAuth:
{:ok, {auth_url, pkce_params, server_pid}} = OpenAI.OAuth.start_callback_server(session_name)
IO.puts("Visit: #{auth_url}")
{:ok, auth_code} = OpenAI.OAuth.wait_for_callback(server_pid, timeout: :infinity)
{:ok, tokens} = OpenAI.OAuth.exchange_code(auth_code, pkce_params, session_name)  
{:ok, api_key} = OpenAI.OAuth.extract_api_key(tokens, session_name)
OpenAI.OAuth.stop_callback_server(server_pid)
```

#### **API Key Implementation (`TheMaestro.Providers.OpenAI.ApiKey`)**
- Bearer token authentication
- Support for multiple named API key sessions
- API key validation and organization handling

#### **Streaming Implementation (`TheMaestro.Providers.OpenAI.Streaming`)**
- Use existing `TheMaestro.Streaming.OpenAIHandler`  
- Text delta processing with reasoning JSON
- Function call assembly and state management
- Usage statistics extraction

### Gemini Provider Requirements

#### **OAuth Implementation (`TheMaestro.Providers.Gemini.OAuth`)**
- **Status:** TO BE RESEARCHED AND IMPLEMENTED
- **Research Required:** Google OAuth 2.0 patterns for Gemini API access
- **Estimated Pattern:** Google Cloud OAuth with service account or user credentials
- **Scopes:** TBD based on Gemini API requirements

#### **API Key Implementation (`TheMaestro.Providers.Gemini.ApiKey`)**
- API key authentication via query parameter or header
- Support for multiple named API key sessions
- Google API key validation patterns

#### **Streaming Implementation (`TheMaestro.Providers.Gemini.Streaming`)**
- Use existing `TheMaestro.Streaming.GeminiHandler`
- Candidate content processing  
- Function call object handling
- Usage metadata extraction

---

## 🧪 COMPREHENSIVE E2E TEST SPECIFICATIONS

### Universal E2E Test Requirements

#### **Standardized Test Prompt**
```elixir
@standard_test_prompt "How would you write a FastAPI application that handles Stripe-based subscriptions? Include error handling and webhook verification."
```

#### **Universal Validation Criteria**
- Complete response reception (no truncation)
- Proper message structure validation  
- Usage statistics verification
- Streaming functionality confirmation
- Error recovery testing
- Performance benchmarking

### Provider-Specific E2E Test Implementations

#### **OpenAI OAuth E2E Test** 
**File:** `scripts/test_openai_oauth_streaming_e2e.exs`

```elixir
# Complete OpenAI OAuth + Streaming E2E Test
defmodule OpenAIE2ETest do
  @test_prompt "How would you write a FastAPI application that handles Stripe-based subscriptions? Include error handling and webhook verification."
  
  def run_full_test(session_name \\ "e2e_test_openai") do
    # Step 1: Generate OAuth URL and start callback server
    {:ok, {auth_url, pkce_params, server_pid}} = 
      TheMaestro.Providers.OpenAI.OAuth.start_callback_server(session_name, port: 8080)
    
    IO.puts("\n🔗 STEP 1: Visit OAuth URL")
    IO.puts("#{auth_url}")
    IO.puts("\n⏳ Waiting for authorization callback (no timeout)...")
    
    # Step 2: Wait for callback with authorization code
    {:ok, auth_code} = TheMaestro.Providers.OpenAI.OAuth.wait_for_callback(server_pid, timeout: :infinity)
    IO.puts("✅ Authorization code received: #{String.slice(auth_code, 0, 10)}...")
    
    # Step 3: Exchange code for tokens
    {:ok, oauth_tokens} = TheMaestro.Providers.OpenAI.OAuth.exchange_code(auth_code, pkce_params, session_name)
    IO.puts("✅ OAuth tokens obtained")
    
    # Step 4: Extract API key using OpenAI's 2-stage process
    {:ok, api_key} = TheMaestro.Providers.OpenAI.OAuth.extract_api_key(oauth_tokens, session_name)
    IO.puts("✅ API key extracted: #{String.slice(api_key, 0, 10)}...")
    
    # Step 5: Create streaming session
    {:ok, stream_session} = TheMaestro.Provider.create_session(:openai, :oauth, name: session_name)
    IO.puts("✅ Streaming session created: #{stream_session}")
    
    # Step 6: Send streaming request
    messages = [%{"role" => "user", "content" => @test_prompt}]
    {:ok, stream} = TheMaestro.Provider.stream_chat(:openai, stream_session, messages)
    
    IO.puts("\n🌊 STEP 6: Processing streaming response...")
    response_chunks = []
    
    # Step 7: Process stream through generic architecture
    stream
    |> TheMaestro.Streaming.parse_stream(:openai, session: stream_session)
    |> Enum.reduce({[], %{}}, fn message, {chunks, stats} ->
      case message.type do
        :content -> 
          IO.write(message.content)
          {[message | chunks], stats}
        :usage ->
          {chunks, Map.merge(stats, message.usage)}
        _ ->
          {chunks, stats}
      end
    end)
    |> then(fn {final_chunks, final_stats} ->
      IO.puts("\n\n✅ STEP 7: Stream processing complete")
      validate_e2e_results(final_chunks, final_stats, @test_prompt)
    end)
    
    # Step 8: Cleanup
    TheMaestro.Providers.OpenAI.OAuth.stop_callback_server(server_pid)
    TheMaestro.Provider.delete_session(:openai, :oauth, stream_session)
    
    IO.puts("✅ E2E test complete - cleanup finished")
  end
  
  defp validate_e2e_results(chunks, stats, test_prompt) do
    # Validation logic for complete pipeline
    total_response = chunks |> Enum.reverse() |> Enum.map(&(&1.content)) |> Enum.join("")
    
    validations = [
      {"Complete response received", String.length(total_response) > 100},
      {"FastAPI mentioned", String.contains?(total_response, "FastAPI")},
      {"Stripe mentioned", String.contains?(total_response, "Stripe")},
      {"Error handling mentioned", String.contains?(total_response, "error")},
      {"Usage stats available", map_size(stats) > 0},
      {"Token count > 0", Map.get(stats, :total_tokens, 0) > 0}
    ]
    
    IO.puts("\n📊 VALIDATION RESULTS:")
    Enum.each(validations, fn {check, passed} ->
      status = if passed, do: "✅", else: "❌"
      IO.puts("#{status} #{check}")
    end)
    
    all_passed = Enum.all?(validations, fn {_, passed} -> passed end)
    IO.puts("\n🎯 OVERALL RESULT: #{if all_passed, do: "✅ PASS", else: "❌ FAIL"}")
  end
end

# Run the test
OpenAIE2ETest.run_full_test()
```

#### **Anthropic OAuth E2E Test**
**File:** `scripts/test_anthropic_oauth_streaming_e2e.exs`

```elixir
# Complete Anthropic OAuth + Streaming E2E Test  
defmodule AnthropicE2ETest do
  @test_prompt "How would you write a FastAPI application that handles Stripe-based subscriptions? Include error handling and webhook verification."
  
  def run_full_test(session_name \\ "e2e_test_anthropic") do
    # Step 1: Generate OAuth URL
    {:ok, {auth_url, pkce_params}} = 
      TheMaestro.Providers.Anthropic.OAuth.generate_url(session_name)
    
    IO.puts("\n🔗 STEP 1: Visit OAuth URL")
    IO.puts("#{auth_url}")
    IO.puts("\n📋 After authorization, you'll see a page with a code.")
    
    # Step 2: Manual code input
    auth_code = IO.gets("Paste the authorization code: ") |> String.trim()
    IO.puts("✅ Authorization code received: #{String.slice(auth_code, 0, 10)}...")
    
    # Step 3: Exchange code for tokens
    {:ok, oauth_tokens} = TheMaestro.Providers.Anthropic.OAuth.exchange_code(auth_code, pkce_params, session_name)
    IO.puts("✅ OAuth tokens obtained")
    
    # Step 4: Extract API key
    {:ok, api_key} = TheMaestro.Providers.Anthropic.OAuth.extract_api_key(oauth_tokens, session_name)
    IO.puts("✅ API key extracted: #{String.slice(api_key, 0, 15)}...")
    
    # Step 5: Create streaming session
    {:ok, stream_session} = TheMaestro.Provider.create_session(:anthropic, :oauth, name: session_name)
    IO.puts("✅ Streaming session created: #{stream_session}")
    
    # Step 6 & 7: Stream and validate (same logic as OpenAI)
    run_streaming_validation(:anthropic, stream_session, @test_prompt)
    
    # Step 8: Cleanup
    TheMaestro.Provider.delete_session(:anthropic, :oauth, stream_session)
    IO.puts("✅ E2E test complete - cleanup finished")
  end
end
```

#### **API Key E2E Tests**
**Files:** `scripts/test_{provider}_api_key_streaming_e2e.exs`

```elixir
# API Key E2E test template for all providers
defmodule APIKeyE2ETest do
  def run_test(provider, api_key, session_name) do
    # Step 1: Create API key session
    {:ok, session} = TheMaestro.Provider.create_session(provider, :api_key, 
      name: session_name, api_key: api_key)
    
    # Step 2: Validate authentication
    {:ok, models} = TheMaestro.Provider.list_models(provider, :api_key, session)
    IO.puts("✅ Authentication valid - #{length(models)} models available")
    
    # Step 3: Stream test
    run_streaming_validation(provider, session, @test_prompt)
    
    # Step 4: Cleanup
    TheMaestro.Provider.delete_session(provider, :api_key, session)
  end
end
```

### Cross-Provider Feature Testing

#### **Model Listing Validation**
```elixir
# Test model listing for all provider/auth combinations
providers = [:anthropic, :openai, :gemini]
auth_types = [:oauth, :api_key]

for provider <- providers, auth_type <- auth_types do
  {:ok, session} = create_test_session(provider, auth_type)
  {:ok, models} = TheMaestro.Provider.list_models(provider, auth_type, session)
  validate_model_list(provider, models)
end
```

#### **Token Refresh Testing**
```elixir  
# Test automatic token refresh for all OAuth sessions
oauth_sessions = get_all_oauth_sessions()

for {provider, session_id} <- oauth_sessions do
  {:ok, old_tokens} = get_current_tokens(provider, session_id)
  {:ok, new_tokens} = TheMaestro.Provider.refresh_tokens(provider, session_id)
  validate_token_refresh(old_tokens, new_tokens)
end
```

#### **Context Management Testing**
```elixir
# Test context chunk management for all providers
for provider <- [:anthropic, :openai, :gemini] do
  {:ok, session} = create_test_session(provider, :oauth)
  {:ok, stream} = start_test_conversation(provider, session)
  context_id = extract_context_id(stream)
  
  {:ok, chunks} = TheMaestro.Provider.list_context_chunks(provider, session, context_id)
  :ok = TheMaestro.Provider.delete_context_chunk(provider, session, context_id, hd(chunks).id)
  
  validate_context_management(provider, session, context_id)
end
```

---

## 🗺️ IMPLEMENTATION ROADMAP

### Phase 1: Foundation Architecture (Week 1)

#### **1.1: Generic Provider Interface Creation**
**Duration:** 2 days
**Files to Create:**
- `lib/the_maestro/providers/provider.ex` - Main interface module
- `lib/the_maestro/providers/resolver.ex` - Dynamic module resolution
- `lib/the_maestro/providers/behaviors/` - All behavior definitions

**Tasks:**
- [ ] Implement `TheMaestro.Provider` module with all interface functions
- [ ] Create dynamic module resolution algorithm
- [ ] Define behaviors for OAuth, API key, streaming, models
- [ ] Add comprehensive @spec declarations and documentation
- [ ] Create basic error handling and validation

#### **1.2: Provider Behavior Definitions**
**Duration:** 1 day  
**Files to Create:**
- `lib/the_maestro/providers/behaviors/oauth_provider.ex`
- `lib/the_maestro/providers/behaviors/api_key_provider.ex`
- `lib/the_maestro/providers/behaviors/streaming_provider.ex`
- `lib/the_maestro/providers/behaviors/model_provider.ex`

**Tasks:**
- [ ] Define OAuth behavior callbacks and types
- [ ] Define API key behavior callbacks and types  
- [ ] Define streaming behavior callbacks and types
- [ ] Define model listing behavior callbacks and types
- [ ] Add behavior compliance validation

#### **1.3: Session Management System**
**Duration:** 1 day
**Files to Modify/Create:**
- Extend `lib/the_maestro/saved_authentication.ex`
- Create session registry and lifecycle management

**Tasks:**
- [ ] Implement named session support
- [ ] Add session persistence across restarts
- [ ] Create session cleanup and expiration logic
- [ ] Add session validation and error handling

### Phase 2: Provider-Specific Migration (Week 2)

#### **2.1: Anthropic Provider Migration**
**Duration:** 2 days
**Files to Create:**
- `lib/the_maestro/providers/anthropic/oauth.ex`
- `lib/the_maestro/providers/anthropic/api_key.ex`  
- `lib/the_maestro/providers/anthropic/streaming.ex`
- `lib/the_maestro/providers/anthropic/models.ex`
- `lib/the_maestro/providers/anthropic/config.ex`

**Tasks:**
- [ ] Migrate existing OAuth logic from `TheMaestro.Auth`
- [ ] Implement API key authentication
- [ ] Integrate with existing streaming handler
- [ ] Implement model listing capability
- [ ] Add comprehensive error handling and validation

#### **2.2: OpenAI Provider Migration**  
**Duration:** 2 days
**Files to Create:**
- `lib/the_maestro/providers/openai/oauth.ex` (callback server pattern)
- `lib/the_maestro/providers/openai/api_key.ex`
- `lib/the_maestro/providers/openai/streaming.ex`
- `lib/the_maestro/providers/openai/models.ex`
- `lib/the_maestro/providers/openai/config.ex`

**Tasks:**
- [ ] Migrate existing OAuth logic with callback server implementation
- [ ] Implement API key authentication
- [ ] Integrate with existing streaming handler
- [ ] Implement model listing capability
- [ ] Add comprehensive error handling and validation

#### **2.3: Gemini Provider Implementation**
**Duration:** 2 days  
**Files to Create:**
- `lib/the_maestro/providers/gemini/oauth.ex` (research + implement)
- `lib/the_maestro/providers/gemini/api_key.ex`
- `lib/the_maestro/providers/gemini/streaming.ex`
- `lib/the_maestro/providers/gemini/models.ex`  
- `lib/the_maestro/providers/gemini/config.ex`

**Tasks:**
- [ ] Research Google OAuth patterns for Gemini
- [ ] Implement OAuth authentication flow
- [ ] Implement API key authentication
- [ ] Integrate with existing streaming handler
- [ ] Implement model listing capability

### Phase 3: Universal Features (Week 3)

#### **3.1: Token Refresh System**
**Duration:** 2 days
**Files to Modify:**
- `lib/the_maestro/workers/token_refresh_worker.ex`
- All provider OAuth modules

**Tasks:**
- [ ] Extend token refresh worker for all providers
- [ ] Implement automatic refresh scheduling
- [ ] Add grace period handling and retry logic
- [ ] Create user notifications for manual re-auth
- [ ] Add comprehensive error handling

#### **3.2: Model Listing Implementation**
**Duration:** 1 day  
**Tasks:**
- [ ] Implement model listing for all providers  
- [ ] Add model metadata and capabilities
- [ ] Create model caching for performance
- [ ] Add model validation and filtering

#### **3.3: Context Management System**
**Duration:** 2 days
**Files to Create:**
- Context management modules for each provider

**Tasks:**
- [ ] Implement context chunk listing
- [ ] Add context chunk deletion
- [ ] Create context search and filtering
- [ ] Add context analytics and insights

### Phase 4: Enhanced Features (Week 4)

#### **4.1: Retry Loop System**
**Duration:** 1 day
**Tasks:**
- [ ] Implement automatic retry with exponential backoff
- [ ] Add intelligent error classification
- [ ] Create retry policies per provider
- [ ] Add user control over retry behavior

#### **4.2: Quality Audit Integration**  
**Duration:** 1 day
**Tasks:**
- [ ] Integrate Gemini for code quality auditing
- [ ] Add best practices validation
- [ ] Create quality scoring and recommendations
- [ ] Add audit report generation

#### **4.3: Parameter Validation System**
**Duration:** 1 day
**Tasks:**
- [ ] Add input parameter validation for all functions
- [ ] Create validation messages and suggestions  
- [ ] Implement best practices checking
- [ ] Add parameter optimization recommendations

### Phase 5: Comprehensive Testing (Week 5)

#### **5.1: E2E Test Suite Implementation**
**Duration:** 3 days
**Files to Create:**
- `scripts/test_openai_oauth_streaming_e2e.exs`
- `scripts/test_anthropic_oauth_streaming_e2e.exs`
- `scripts/test_gemini_oauth_streaming_e2e.exs`
- `scripts/test_{provider}_api_key_streaming_e2e.exs` (for each provider)

**Tasks:**
- [ ] Implement OpenAI OAuth E2E test with callback server
- [ ] Implement Anthropic OAuth E2E test with manual code
- [ ] Implement Gemini OAuth E2E test (based on research)
- [ ] Implement API key E2E tests for all providers
- [ ] Add cross-provider feature testing
- [ ] Create test automation and CI integration

#### **5.2: Performance and Load Testing**
**Duration:** 1 day
**Tasks:**
- [ ] Add performance benchmarks for all operations
- [ ] Create load testing for concurrent sessions
- [ ] Add memory and resource usage monitoring  
- [ ] Create performance regression testing

#### **5.3: Documentation and Training**
**Duration:** 1 day
**Tasks:**
- [ ] Create comprehensive API documentation
- [ ] Add usage examples and best practices
- [ ] Create migration guide from old API
- [ ] Add troubleshooting and debugging guides

---

## 🔄 MIGRATION STRATEGY

### Backward Compatibility Plan

#### **Phase 1: Dual API Support**
- Maintain existing `TheMaestro.Auth` functions during migration
- Add deprecation warnings to old API functions
- Route old API calls through new provider interface
- Ensure all existing tests continue to pass

#### **Phase 2: Gradual Migration**  
- Update internal code to use new provider interface
- Migrate existing saved authentications to new session format
- Update configuration to new unified format
- Test backward compatibility thoroughly

#### **Phase 3: Legacy API Removal**
- Remove deprecated functions after full migration
- Clean up old configuration patterns
- Update all documentation and examples
- Perform final validation of migration

### Data Migration Requirements

#### **Authentication Data Migration**
```elixir
# Migrate existing saved authentications to new session format
defmodule MigrationWorker do
  def migrate_authentications() do
    # Convert existing Anthropic OAuth tokens
    existing_anthropic = get_anthropic_tokens()
    migrate_to_named_session(:anthropic, :oauth, existing_anthropic, "default_anthropic")
    
    # Convert existing OpenAI OAuth tokens  
    existing_openai = get_openai_tokens()
    migrate_to_named_session(:openai, :oauth, existing_openai, "default_openai")
    
    # Handle API key migrations
    migrate_api_keys_to_sessions()
  end
end
```

#### **Configuration Migration**
```elixir
# Convert provider-specific configs to unified format
config :the_maestro, TheMaestro.Providers,
  anthropic: %{
    oauth: %{client_id: "...", scopes: [...], endpoints: %{...}},
    api_key: %{header_name: "x-api-key", validation: %{...}}
  },
  openai: %{
    oauth: %{client_id: "...", scopes: [...], endpoints: %{...}},  
    api_key: %{auth_type: :bearer, validation: %{...}}
  },
  gemini: %{
    oauth: %{client_id: "...", scopes: [...], endpoints: %{...}},
    api_key: %{param_name: "key", validation: %{...}}
  }
```

### Testing Strategy During Migration

#### **Parallel Testing**
- Run old API tests alongside new API tests
- Compare outputs between old and new implementations  
- Validate that new interface produces identical results
- Monitor performance during migration

#### **Rollback Procedures**
- Maintain ability to roll back to old API at any point
- Keep old authentication data alongside new sessions
- Create rollback scripts for configuration changes
- Test rollback procedures before each phase

---

## ✅ SUCCESS CRITERIA & ACCEPTANCE CRITERIA

### Universal Provider Interface Success Criteria

#### **AC 1: Single Entry Point**
- [ ] All provider operations accessible through `TheMaestro.Provider` module
- [ ] No direct calls to provider-specific modules required
- [ ] Consistent API across all providers and authentication types
- [ ] Complete @spec declarations with comprehensive error handling

#### **AC 2: Dynamic Module Resolution**  
- [ ] New providers can be added without modifying core interface code
- [ ] Module paths generated dynamically from provider and operation atoms
- [ ] Provider capabilities discoverable through interface
- [ ] Graceful handling of missing or invalid providers

#### **AC 3: Drop-in Provider Support**
- [ ] New provider addition requires only implementing defined behaviors
- [ ] No changes to application.ex or configuration structure required
- [ ] Automatic discovery and registration of new providers
- [ ] Provider validation and compliance checking

### Authentication & Session Management Success Criteria

#### **AC 4: Named Authentication Sessions**
- [ ] Support for multiple concurrent authentications per provider
- [ ] User-defined session names with validation and uniqueness
- [ ] Session persistence across application restarts
- [ ] Session lifecycle management (creation, validation, cleanup, expiration)

#### **AC 5: Universal Token Refresh**
- [ ] Automatic token refresh implemented for ALL OAuth providers
- [ ] Background refresh jobs with configurable schedules
- [ ] Grace period handling and retry logic for failures
- [ ] User notifications and manual re-authentication flows

#### **AC 6: Complete Feature Parity**
- [ ] Model listing available for ALL provider/auth combinations
- [ ] Streaming conversations enabled for ALL providers
- [ ] Context management (list, delete chunks) for ALL providers
- [ ] Error handling and recovery consistent across providers

### Comprehensive E2E Testing Success Criteria

#### **AC 7: Provider-Specific E2E Tests**  
- [ ] OpenAI OAuth E2E test with callback server implementation
- [ ] Anthropic OAuth E2E test with manual authorization code flow
- [ ] Gemini OAuth E2E test (pattern TBD based on research)
- [ ] API key E2E tests for all three providers
- [ ] All tests validate complete pipeline: auth → model listing → streaming → validation

#### **AC 8: Universal Test Validation**
- [ ] Standardized test prompt used across all provider tests
- [ ] Complete response reception validation (no truncation)
- [ ] Usage statistics verification for all streaming tests
- [ ] Error recovery and interruption handling testing
- [ ] Performance benchmarking and regression detection

#### **AC 9: Cross-Provider Feature Testing**
- [ ] Model listing validation across all provider/auth combinations  
- [ ] Token refresh testing for all OAuth implementations
- [ ] Context management testing across all providers
- [ ] Named session functionality testing
- [ ] Concurrent session support validation

### Performance & Quality Success Criteria

#### **AC 10: Performance Requirements**
- [ ] API response times <200ms for session operations
- [ ] Streaming latency <100ms for first token
- [ ] Memory usage <50MB additional for provider interface  
- [ ] Support for 100+ concurrent named sessions

#### **AC 11: Code Quality Standards**
- [ ] All modules pass `mix format` and `mix credo --strict`
- [ ] Comprehensive @spec declarations for all public functions
- [ ] Test coverage >90% for new provider interface code
- [ ] Complete documentation with examples and troubleshooting

#### **AC 12: Enhanced Features**
- [ ] Automatic retry loops with intelligent error classification
- [ ] Gemini code quality audit integration and reporting
- [ ] Parameter validation with best practices recommendations  
- [ ] Context analytics and management insights

### Migration & Compatibility Success Criteria

#### **AC 13: Backward Compatibility**
- [ ] All existing API calls continue to work during migration
- [ ] No data loss during authentication migration process
- [ ] Configuration migration completed without service interruption
- [ ] Comprehensive rollback procedures tested and documented

#### **AC 14: Documentation & Training**  
- [ ] Complete API documentation with usage examples
- [ ] Migration guide for developers using old API
- [ ] Best practices documentation for new provider additions
- [ ] Troubleshooting guide for common issues

---

## 📊 RISK ASSESSMENT & MITIGATION

### High-Risk Areas

#### **Risk 1: OAuth Implementation Complexity**
- **Impact:** High - OAuth flows vary significantly between providers
- **Probability:** Medium - OpenAI callback server, Anthropic manual code, Gemini TBD
- **Mitigation:** Phase-by-phase implementation, comprehensive E2E testing, fallback to API key auth

#### **Risk 2: Data Migration Failures**
- **Impact:** High - Could lose existing authentication data  
- **Probability:** Low - Well-tested migration procedures
- **Mitigation:** Backup all data before migration, parallel data storage, tested rollback procedures

#### **Risk 3: Performance Degradation**
- **Impact:** Medium - Additional abstraction layer could impact performance
- **Probability:** Low - Minimal overhead from dynamic resolution  
- **Mitigation:** Performance benchmarking, caching strategies, optimization profiles

### Medium-Risk Areas

#### **Risk 4: Gemini OAuth Research Unknown**
- **Impact:** Medium - Could delay Gemini provider implementation
- **Probability:** Medium - Google OAuth patterns may be complex
- **Mitigation:** Early research phase, fallback to API key only, phased rollout

#### **Risk 5: Streaming Integration Complexity**  
- **Impact:** Medium - Existing streaming handlers need integration
- **Probability:** Low - Streaming architecture already exists
- **Mitigation:** Reuse existing handlers, incremental integration, thorough testing

---

## 📈 SUCCESS METRICS

### Technical Metrics

- **Code Duplication Reduction:** Target 70% reduction in provider-specific code duplication
- **Time to Add New Provider:** Target <4 hours for complete provider implementation
- **Test Coverage:** Maintain >90% coverage across all provider interface code
- **Performance:** <200ms API response times, <100ms streaming first token
- **Reliability:** >99.9% uptime for provider interface operations

### User Experience Metrics

- **Authentication Success Rate:** >95% for all provider/auth combinations
- **Session Management Satisfaction:** Support for 10+ named sessions per provider
- **Error Recovery:** <5 seconds automatic recovery from transient failures  
- **Feature Completeness:** 100% feature parity across all providers

### Development Productivity Metrics

- **Development Velocity:** 50% faster new provider addition
- **Bug Reduction:** 60% fewer authentication-related bugs  
- **Maintenance Overhead:** 40% reduction in provider-specific maintenance
- **Documentation Completeness:** 100% API coverage with examples

---

## 📋 CONCLUSION

This Emergency Course Correct PRD provides a comprehensive blueprint for transforming the fragmented Epic 1 implementation into a robust, modular, and extensible universal provider system. The proposed architecture addresses all critical fragmentation issues while implementing universal requirements for token refresh, named authentication, model listing, and comprehensive streaming support.

The phased implementation approach ensures minimal disruption to existing functionality while systematically building toward a clean, maintainable architecture that will support rapid addition of new providers and authentication methods.

**Critical Success Factors:**
1. **Complete E2E testing coverage** for all provider/auth combinations
2. **Seamless migration** of existing authentication data and sessions  
3. **Performance optimization** to ensure the abstraction layer adds minimal overhead
4. **Comprehensive documentation** to support developers using the new interface

**Expected Outcomes:**
- **Reduced Technical Debt:** 70% reduction in code duplication and maintenance overhead
- **Enhanced Scalability:** Drop-in provider support with <4 hour implementation time
- **Improved User Experience:** Complete feature parity and universal authentication support
- **Future-Proof Architecture:** Extensible design supporting unlimited provider addition

This transformation will establish `TheMaestro` as a truly universal LLM orchestration platform with clean, maintainable architecture supporting all current and future provider integration requirements.