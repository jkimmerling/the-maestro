# Epic 5, Story 5.1: Multi-Provider Authentication Architecture

## Overview

This tutorial explains the implementation of the multi-provider authentication system for The Maestro, which enables users to authenticate with multiple LLM providers (Claude, Gemini, ChatGPT) using both OAuth and API key authentication methods.

## Architecture Overview

The multi-provider authentication system consists of several key components:

### Core Components

1. **ProviderAuth Behaviour** - Defines the contract for authentication providers
2. **Auth Coordinator** - Main interface for authentication operations  
3. **Provider Registry** - Manages available authentication providers
4. **Credential Store** - Secure encrypted storage for credentials
5. **Session Manager** - Handles multi-provider sessions
6. **Provider Implementations** - Concrete implementations for each LLM provider

## Implementation Details

### 1. Provider Authentication Behaviour

The `ProviderAuth` behaviour defines a standard interface that all authentication providers must implement:

```elixir
defmodule TheMaestro.Providers.Auth.ProviderAuth do
  @callback get_available_methods(provider()) :: [auth_method()]
  @callback authenticate(provider(), auth_method(), auth_params()) :: 
              {:ok, credentials()} | {:error, term()}
  @callback validate_credentials(provider(), credentials()) :: 
              {:ok, credentials()} | {:error, term()}
  @callback refresh_credentials(provider(), credentials()) :: 
              {:ok, credentials()} | {:error, term()}
  @callback initiate_oauth_flow(provider(), map()) :: 
              {:ok, String.t()} | {:error, term()}
  @callback exchange_oauth_code(provider(), String.t(), map()) :: 
              {:ok, credentials()} | {:error, term()}
end
```

This behaviour ensures consistency across all provider implementations while allowing provider-specific logic.

### 2. Credential Storage with Encryption

The credential store provides secure, encrypted storage for authentication credentials:

```elixir
defmodule TheMaestro.Providers.Auth.CredentialStore do
  # Stores encrypted credentials
  def store_credentials(user_id, provider, method, credentials) do
    encrypted_creds = encrypt_credentials(credentials)
    # Store in database with unique constraints
  end
  
  # Retrieves and decrypts credentials
  def get_credentials(user_id, provider, method \\ nil) do
    # Fetch from database and decrypt
  end
  
  # Uses AES-256-CBC encryption
  defp encrypt_credentials(credentials) do
    key = get_encryption_key()
    plaintext = Jason.encode!(credentials)
    iv = :crypto.strong_rand_bytes(16)
    ciphertext = :crypto.crypto_one_time(:aes_256_cbc, key, iv, plaintext, true)
    Base.encode64(iv <> ciphertext)
  end
end
```

**Security Features:**
- AES-256-CBC encryption for credentials
- Unique database constraints prevent duplicates
- Environment-based encryption key configuration
- Automatic token refresh handling

### 3. Provider Implementations

#### Anthropic Provider
```elixir
defmodule TheMaestro.Providers.Auth.AnthropicAuth do
  @behaviour TheMaestro.Providers.Auth.ProviderAuth
  
  def get_available_methods(:anthropic) do
    methods = [:api_key]
    if @oauth_client_id && @oauth_client_secret do
      [:oauth | methods]
    else
      methods
    end
  end
  
  def authenticate(:anthropic, :api_key, %{api_key: api_key}) do
    case validate_api_key(api_key) do
      :ok -> {:ok, %{api_key: api_key, token_type: "api_key"}}
      error -> error
    end
  end
  
  def authenticate(:anthropic, :oauth, %{oauth_code: code, redirect_uri: uri}) do
    case exchange_code_for_tokens(code, uri) do
      {:ok, tokens} -> {:ok, format_oauth_credentials(tokens)}
      error -> error
    end
  end
end
```

#### OpenAI Provider
Similar structure with OpenAI-specific API endpoints and validation logic.

#### Google/Gemini Provider
Integrates with the existing Gemini authentication system while providing the new provider interface.

### 4. Session Management

The session manager handles multi-provider authentication contexts:

```elixir
defmodule TheMaestro.Providers.Auth.SessionManager do
  use GenServer
  
  defmodule SessionState do
    defstruct user_id: nil,
              active_provider: nil,
              provider_contexts: %{},
              last_activity: nil,
              created_at: nil
  end
  
  def set_active_provider(session, provider, method \\ nil) do
    GenServer.call(session, {:set_active_provider, provider, method})
  end
  
  def get_active_provider(session) do
    GenServer.call(session, :get_active_provider)
  end
end
```

## Database Schema

The system uses a new `provider_credentials` table:

```sql
CREATE TABLE provider_credentials (
  id UUID PRIMARY KEY,
  user_id VARCHAR NOT NULL,
  provider VARCHAR NOT NULL, -- 'anthropic', 'google', 'openai'
  auth_method VARCHAR NOT NULL, -- 'oauth', 'api_key'
  credentials TEXT NOT NULL, -- encrypted credentials
  expires_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

**Indexes:**
- `(user_id, provider, auth_method)` - Unique constraint
- `user_id`, `provider`, `auth_method`, `expires_at` - Performance indexes

## Configuration

The system is configured through application config:

```elixir
config :the_maestro, :providers,
  anthropic: %{
    oauth_client_id: {:system, "ANTHROPIC_OAUTH_CLIENT_ID"},
    oauth_client_secret: {:system, "ANTHROPIC_OAUTH_CLIENT_SECRET"},
    api_key: {:system, "ANTHROPIC_API_KEY"}
  },
  openai: %{
    oauth_client_id: {:system, "OPENAI_OAUTH_CLIENT_ID"}, 
    oauth_client_secret: {:system, "OPENAI_OAUTH_CLIENT_SECRET"},
    api_key: {:system, "OPENAI_API_KEY"}
  },
  google: %{
    # Reuse existing Gemini configuration
    oauth_client_id: "...",
    oauth_client_secret: "...",
    api_key: {:system, "GEMINI_API_KEY"}
  }

config :the_maestro, :multi_provider_auth,
  credential_encryption_key: {:system, "CREDENTIAL_ENCRYPTION_KEY"},
  default_redirect_uris: %{
    anthropic: "http://localhost:4000/auth/anthropic/callback",
    openai: "http://localhost:4000/auth/openai/callback",
    google: "http://localhost:4000/auth/google/callback"
  },
  session_timeout: 3600 * 24,  # 24 hours
  refresh_threshold: 300  # 5 minutes
```

## Usage Examples

### Basic Authentication
```elixir
# Authenticate with API key
{:ok, auth_result} = Auth.authenticate(:anthropic, :api_key, %{
  api_key: "sk-ant-api123456"
}, "user123")

# Initiate OAuth flow
{:ok, auth_url} = Auth.initiate_oauth_flow(:openai, %{
  redirect_uri: "http://localhost:4000/auth/openai/callback"
})

# Complete OAuth flow
{:ok, auth_result} = Auth.complete_oauth_flow(:openai, "auth_code", "user123", %{
  redirect_uri: "http://localhost:4000/auth/openai/callback"
})
```

### Session Management
```elixir
# Start a session manager
{:ok, session} = SessionManager.start_link("user123")

# Set active provider
{:ok, auth_context} = SessionManager.set_active_provider(session, :anthropic)

# Get current active provider
{:ok, {provider, context}} = SessionManager.get_active_provider(session)

# List all providers for user
provider_status = SessionManager.list_session_providers(session)
```

### Credential Management
```elixir
# Store credentials
:ok = Auth.store_credentials("user123", :anthropic, :oauth, %{
  access_token: "access_token",
  refresh_token: "refresh_token",
  expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
})

# Retrieve credentials
{:ok, credentials} = Auth.get_credentials("user123", :anthropic)

# Refresh tokens
{:ok, new_credentials} = provider_module.refresh_credentials(:anthropic, credentials)
```

## Testing

The implementation includes comprehensive test coverage:

### Unit Tests
- Provider authentication methods
- Credential encryption/decryption
- Session management operations
- Error handling scenarios

### Integration Tests
- End-to-end authentication flows
- Provider switching
- Token refresh workflows
- Database operations

### Security Tests
- Credential protection
- Session isolation
- Input validation
- Error message sanitization

## Security Considerations

### Implemented Security Measures
1. **Encryption at Rest** - All credentials encrypted using AES-256-CBC
2. **Environment-based Secrets** - No hardcoded credentials
3. **Input Validation** - API keys and tokens validated before use
4. **Session Isolation** - Each user has isolated session state
5. **Secure Token Storage** - Encrypted database storage with expiry

### Security Best Practices
1. Use environment variables for all sensitive configuration
2. Implement proper CSRF protection for OAuth flows
3. Validate all redirect URIs against allowlists
4. Implement rate limiting for authentication attempts
5. Use secure, random encryption keys in production
6. Regularly rotate encryption keys
7. Implement audit logging for authentication events

## Performance Considerations

### Optimizations Implemented
1. **Connection Reuse** - HTTP clients reuse connections
2. **Database Indexes** - Optimized queries with proper indexing
3. **Session Caching** - In-memory session state management
4. **Lazy Loading** - Credentials loaded only when needed

### Monitoring Points
1. Authentication success/failure rates
2. Token refresh frequency
3. Session duration and cleanup
4. Database query performance
5. External API response times

## Troubleshooting

### Common Issues

**Authentication Failures:**
- Check API key format and validity
- Verify OAuth client credentials
- Ensure proper redirect URI configuration

**Token Refresh Errors:**
- Verify refresh token hasn't expired
- Check provider-specific refresh endpoints
- Validate client credentials for refresh

**Session Issues:**
- Check session timeout configuration
- Verify GenServer process health
- Monitor memory usage for large session counts

**Database Errors:**
- Check database connectivity
- Verify migration status
- Monitor encryption key availability

## Future Enhancements

1. **Additional Providers** - Support for more LLM providers
2. **MFA Support** - Multi-factor authentication integration
3. **SSO Integration** - Enterprise SSO provider support
4. **Advanced Session Management** - Cross-device session sharing
5. **Audit Trail** - Comprehensive authentication logging
6. **Key Rotation** - Automated encryption key rotation
7. **Provider Health Checks** - Automated provider availability monitoring

## Conclusion

The multi-provider authentication system provides a secure, scalable foundation for authenticating with multiple LLM providers. The modular architecture allows for easy extension to support additional providers while maintaining security and performance standards.

The system successfully abstracts provider-specific authentication details while providing a consistent interface for the application to use, enabling seamless switching between different LLM providers based on user preferences and availability.