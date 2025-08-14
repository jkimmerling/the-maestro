# Story 5.1: Multi-Provider Authentication Architecture

## User Story
**As a** Developer,  
**I want** to extend the existing authentication system to support multiple LLM providers with flexible authentication methods,  
**so that** users can authenticate with Claude, Gemini, and ChatGPT using either OAuth or API keys.

## Acceptance Criteria

### Core Architecture
1. **Multi-Provider Auth Module**: Create `TheMaestro.Providers.Auth` module that manages authentication across different providers
2. **Provider Registration System**: Implement a registry pattern for authentication providers with support for:
   - Claude (Anthropic) - OAuth and API Key
   - Gemini (Google) - OAuth and API Key  
   - ChatGPT (OpenAI) - OAuth and API Key
3. **Authentication Method Detection**: Auto-detect available authentication methods for each provider
4. **Unified Auth Interface**: Create consistent authentication interface regardless of provider

### Authentication Flows
5. **OAuth Integration**: Extend existing OAuth system to support:
   - Anthropic OAuth (Claude)
   - Google OAuth (Gemini) - reuse existing implementation
   - OpenAI OAuth (ChatGPT)
6. **API Key Management**: Secure storage and validation of API keys for each provider
7. **Fallback Strategies**: Implement authentication fallback chains (OAuth → API Key → Environment Variables)

### Session Management
8. **Multi-Provider Sessions**: Extend session management to track:
   - Active provider
   - Authentication method used
   - Token/credential state
   - Model selection context
9. **Credential Refresh**: Automatic token refresh for OAuth providers
10. **Secure Storage**: Encrypted credential storage following existing patterns

### Configuration
11. **Provider Configuration**: Extend application configuration to support:
   ```elixir
   config :the_maestro, :providers,
     anthropic: [
       oauth_client_id: {:system, "ANTHROPIC_OAUTH_CLIENT_ID"},
       api_key: {:system, "ANTHROPIC_API_KEY"}
     ],
     google: [
       # Reuse existing Gemini config
     ],
     openai: [
       oauth_client_id: {:system, "OPENAI_OAUTH_CLIENT_ID"}, 
       api_key: {:system, "OPENAI_API_KEY"}
     ]
   ```

### Database Schema
12. **Provider Credentials Table**: Create migration for multi-provider credential storage:
   ```sql
   CREATE TABLE provider_credentials (
     id UUID PRIMARY KEY,
     user_id UUID REFERENCES users(id),
     provider VARCHAR NOT NULL, -- 'anthropic', 'google', 'openai'
     auth_method VARCHAR NOT NULL, -- 'oauth', 'api_key'
     credentials JSONB NOT NULL, -- encrypted credentials
     expires_at TIMESTAMP,
     created_at TIMESTAMP DEFAULT NOW(),
     updated_at TIMESTAMP DEFAULT NOW()
   );
   ```

### Error Handling
13. **Authentication Errors**: Comprehensive error handling for:
    - Invalid credentials
    - Expired tokens
    - Provider-specific errors
    - Network connectivity issues
14. **Graceful Degradation**: System continues to function when some providers are unavailable

### Testing
15. **Authentication Tests**: Comprehensive test coverage for all providers and methods
16. **Mock Provider Support**: Test doubles for external provider services
17. **Integration Tests**: End-to-end authentication flows

## Technical Implementation

### Module Structure
```
lib/the_maestro/providers/auth/
├── auth.ex                 # Main authentication coordinator
├── provider_registry.ex    # Provider registration and discovery
├── anthropic_auth.ex      # Claude/Anthropic authentication
├── google_auth.ex         # Gemini/Google authentication (extend existing)
├── openai_auth.ex         # ChatGPT/OpenAI authentication
├── credential_store.ex    # Secure credential management
└── session_manager.ex     # Multi-provider session handling
```

### Key Behaviours
```elixir
defmodule TheMaestro.Providers.Auth.ProviderAuth do
  @callback get_available_methods(provider :: atom()) :: [:oauth | :api_key]
  @callback authenticate(provider :: atom(), method :: atom(), params :: map()) :: {:ok, credentials} | {:error, reason}
  @callback validate_credentials(provider :: atom(), credentials :: map()) :: {:ok, valid_credentials} | {:error, reason}
  @callback refresh_credentials(provider :: atom(), credentials :: map()) :: {:ok, new_credentials} | {:error, reason}
end
```

## Dependencies
- Existing authentication system from Epic 2 (Story 2.2)
- OAuth infrastructure from Epic 1 (Story 1.4)  
- Provider abstractions from Epic 3 (Story 3.1)
- Database and session management from Epic 3 (Story 3.5)

## Definition of Done
- [ ] Multi-provider authentication architecture implemented
- [ ] All three providers (Claude, Gemini, ChatGPT) support OAuth and API key authentication
- [ ] Credential storage and management system operational
- [ ] Authentication flows tested for all providers and methods
- [ ] Database migration and schema updates completed
- [ ] Integration tests passing
- [ ] Documentation updated with new authentication patterns
- [ ] Tutorial created in `tutorials/epic5/story5.1/`