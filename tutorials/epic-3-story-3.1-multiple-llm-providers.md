# Epic 3 Story 3.1: Multiple LLM Provider Support

## Overview

This tutorial demonstrates the implementation of multi-provider LLM support in TheMaestro, allowing users to choose between OpenAI, Anthropic (Claude), and Gemini providers with comprehensive OAuth authentication.

## Features Implemented

### 1. Multi-Provider Architecture

The system now supports three LLM providers:
- **Gemini** (Google) - Default provider
- **OpenAI** (GPT models)
- **Anthropic** (Claude models)

### 2. Dual Authentication Support

Each provider supports both authentication methods:
- **API Keys**: Direct API key authentication (e.g., `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`)
- **OAuth 2.0**: Web-based OAuth authentication with token caching and refresh

### 3. Configuration Management

Providers are configurable in `config/config.exs`:

```elixir
# Configure LLM Provider Selection
config :the_maestro, :llm_provider, default: :gemini

# Provider-specific configurations
config :the_maestro, :providers,
  gemini: %{
    module: TheMaestro.Providers.Gemini,
    models: ["gemini-2.5-pro", "gemini-1.5-pro", "gemini-1.5-flash"]
  },
  openai: %{
    module: TheMaestro.Providers.OpenAI,
    models: ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"]
  },
  anthropic: %{
    module: TheMaestro.Providers.Anthropic,
    models: ["claude-3-opus-20240229", "claude-3-sonnet-20240229", "claude-3-haiku-20240307"]
  }
```

## Implementation Details

### 1. LLM Provider Behaviour

All providers implement the `TheMaestro.Providers.LLMProvider` behaviour:

```elixir
@callback initialize_auth(config :: map()) :: {:ok, auth_context()} | {:error, term()}
@callback complete_text(auth_context(), [message()], opts :: map()) :: {:ok, response()} | {:error, term()}
@callback complete_with_tools(auth_context(), [message()], opts :: map()) :: {:ok, response()} | {:error, term()}
@callback refresh_auth(auth_context()) :: {:ok, auth_context()} | {:error, term()}
@callback validate_auth(auth_context()) :: :ok | {:error, term()}
```

### 2. OAuth Implementation

Each provider includes comprehensive OAuth 2.0 support:

#### Device Authorization Flow (CLI)
```elixir
# Start device authorization
{:ok, flow_data} = OpenAI.device_authorization_flow(%{})
# User visits flow_data.auth_url in browser
# App polls for completion
auth_code = flow_data.polling_fn.()
{:ok, credentials} = OpenAI.complete_device_authorization(auth_code, flow_data.code_verifier)
```

#### Web Authorization Flow (Phoenix)
```elixir
# Start web OAuth flow  
{:ok, flow_data} = OpenAI.web_authorization_flow(%{})
# Redirect user to flow_data.auth_url
# Handle callback in Phoenix controller
{:ok, tokens} = OpenAI.exchange_authorization_code(code, redirect_uri)
```

### 3. Provider Resolution

The Agent GenServer automatically resolves providers:

```elixir
# Start agent with specific provider
{:ok, pid} = Agents.start_agent("agent-1", provider_name: :openai)

# Or use default provider
{:ok, pid} = Agents.start_agent("agent-2")  # Uses :gemini by default
```

### 4. Anthropic OAuth Specifics

Based on real OAuth token examples, Anthropic requires special handling:

- OAuth tokens format: `sk-ant-oat01-...` (vs API keys: `sk-ant-api...`)
- Special beta headers: `anthropic-beta: oauth-2025-04-20,fine-grained-tool-streaming-2025-05-14`
- Direct HTTP requests for OAuth (library compatibility issues)

```elixir
defp build_anthropic_headers(token, :oauth) do
  [
    {"authorization", "Bearer #{token}"},
    {"content-type", "application/json"},
    {"anthropic-version", "2023-06-01"},
    {"anthropic-beta", "oauth-2025-04-20,fine-grained-tool-streaming-2025-05-14"},
    {"anthropic-dangerous-direct-browser-access", "true"},
    {"x-app", "cli"}
  ]
end
```

## Usage Examples

### 1. Environment Variable Setup

```bash
# For API key authentication
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-api..."
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"

# For OAuth authentication  
export OPENAI_OAUTH_CLIENT_ID="your-client-id"
export OPENAI_OAUTH_CLIENT_SECRET="your-client-secret"
export ANTHROPIC_OAUTH_CLIENT_ID="your-client-id" 
export ANTHROPIC_OAUTH_CLIENT_SECRET="your-client-secret"
```

### 2. Creating Agents with Different Providers

```elixir
# Start agents with different providers
{:ok, gemini_agent} = Agents.start_agent("gemini-1", provider_name: :gemini)
{:ok, openai_agent} = Agents.start_agent("openai-1", provider_name: :openai) 
{:ok, claude_agent} = Agents.start_agent("claude-1", provider_name: :anthropic)

# Send messages
{:ok, response} = Agent.send_message("openai-1", "Hello from GPT!")
{:ok, response} = Agent.send_message("claude-1", "Hello from Claude!")
```

### 3. Listing Available Providers

```elixir
# Get all configured providers
providers = Agent.list_providers()
# %{
#   gemini: %{module: TheMaestro.Providers.Gemini, models: [...]},
#   openai: %{module: TheMaestro.Providers.OpenAI, models: [...]},
#   anthropic: %{module: TheMaestro.Providers.Anthropic, models: [...]}
# }

# Get default provider
default = Agent.get_default_provider()  # :gemini
```

## Testing

The implementation includes comprehensive tests for all providers:

```bash
# Run all provider tests
mix test test/the_maestro/providers/

# Run specific provider tests
mix test test/the_maestro/providers/openai_test.exs
mix test test/the_maestro/providers/anthropic_test.exs
```

Test coverage includes:
- Authentication initialization (API key and OAuth)
- Text completion
- Tool-enabled completion  
- Token validation and refresh
- OAuth flow initiation
- Error handling

## Security Considerations

### 1. Credential Storage

- OAuth tokens are cached securely in `~/.maestro/` with 600 permissions
- Separate credential files per provider (`gemini_oauth_creds.json`, `openai_oauth_creds.json`, etc.)
- API keys read from environment variables only

### 2. Token Management

- Automatic token validation before requests
- Token refresh with proper error handling
- Secure credential caching and cleanup

### 3. OAuth Security

- PKCE (Proof Key for Code Exchange) for device flows
- State parameter validation for web flows
- Proper scope management per provider

## Architecture Benefits

1. **Provider Abstraction**: Common interface regardless of underlying provider
2. **Authentication Flexibility**: Supports both API keys and OAuth for all providers
3. **Configuration Driven**: Easy to add new providers or modify existing ones
4. **Error Handling**: Comprehensive error handling and fallback mechanisms
5. **Testing**: Full test coverage for all authentication and request scenarios

## Future Enhancements

- Add support for Azure OpenAI endpoints
- Implement provider-specific streaming optimizations  
- Add metrics and monitoring per provider
- Support for custom model fine-tuning
- Provider failover and load balancing

## Migration from Single Provider

Existing Gemini-only installations continue to work unchanged. The default provider remains `:gemini` ensuring backward compatibility. To enable multiple providers:

1. Add new dependencies to `mix.exs` (already done)
2. Configure additional providers in `config/config.exs`
3. Set up authentication (API keys or OAuth)
4. Create agents with specific providers as needed

The implementation maintains full backward compatibility while enabling the flexibility of multiple LLM providers.