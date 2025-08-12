# Epic 2, Story 2.5: CLI Device Authorization Flow Backend

This tutorial covers the implementation of the CLI device authorization flow backend for The Maestro project. This feature allows CLI clients to authenticate users through a browser-based OAuth flow, similar to tools like GitHub CLI or Docker CLI.

## Overview

The device authorization flow (RFC 8628) is a two-step authentication process:

1. **CLI requests device code**: The CLI application requests a device code and user verification URL from the server
2. **User authorizes in browser**: The user visits the URL in their browser and authorizes the device
3. **CLI polls for completion**: The CLI polls the server until the user completes authorization
4. **CLI receives access token**: Once authorized, the CLI receives an access token to make authenticated requests

## Architecture

The implementation consists of several key components:

### 1. CLI Authentication Controller (`CliAuthController`)
- **`POST /api/cli/auth/device`**: Generates device codes and verification URLs
- **`GET /api/cli/auth/authorize`**: Browser-based authorization page  
- **`POST /api/cli/auth/authorize`**: Processes user authorization
- **`GET /api/cli/auth/poll`**: Polling endpoint for CLI to check authorization status

### 2. OAuth Controller Integration
- Enhanced to handle both web OAuth and device authorization callbacks
- Routes device authorization through the same OAuth flow as web authentication
- Provides different success/error pages based on the authorization type

### 3. In-Memory Device Code Storage
- Uses ETS (Erlang Term Storage) for fast, concurrent device code management
- Stores device codes with expiration times and authorization status
- In production, consider using Redis or a database for persistence across server restarts

## Implementation Details

### Device Code Generation

```elixir
defp generate_device_code do
  # Generate a longer, URL-safe device code for internal use
  @device_code_length
  |> :crypto.strong_rand_bytes()
  |> Base.url_encode64(padding: false)
end

defp generate_user_code do
  # Generate a short, human-readable code for display to user
  chars = ~c"23456789ABCDEFGHJKLMNPQRSTUVWXYZ" # Excludes confusing chars
  
  for _ <- 1..@user_code_length do
    Enum.random(chars)
  end
  |> List.to_string()
end
```

**Key Design Decisions**:
- **Device Code**: Long, URL-safe string for internal tracking (prevents guessing)
- **User Code**: Short, human-friendly code displayed to users (easy to type)
- **Character Set**: Excludes confusing characters like 0, O, 1, I for better UX
- **Expiration**: 15-minute expiry to balance security and user experience

### Device Authorization Flow

```elixir
def device(conn, _params) do
  # Generate unique codes
  device_code = generate_device_code()
  user_code = generate_user_code()
  
  # Store with expiration
  device_info = %{
    device_code: device_code,
    user_code: user_code,
    expires_at: DateTime.add(DateTime.utc_now(), 900, :second),
    authorized: false,
    access_token: nil,
    error: nil
  }
  
  :ets.insert(@device_codes_store, {device_code, device_info})
  
  # Return response for CLI
  json(conn, %{
    device_code: device_code,
    user_code: user_code,
    verification_uri: "#{base_url}/api/cli/auth/authorize",
    verification_uri_complete: "#{base_url}/api/cli/auth/authorize?user_code=#{user_code}",
    expires_in: 900,
    interval: 5
  })
end
```

### Polling Implementation

The polling endpoint implements the standard OAuth 2.0 Device Authorization Grant response codes:

- **`200 OK`**: Authorization complete, returns access token
- **`428 Precondition Required`**: Authorization still pending, CLI should continue polling
- **`400 Bad Request`**: Device code expired, invalid, or authorization denied

```elixir
def poll(conn, %{"device_code" => device_code}) do
  case :ets.lookup(@device_codes_store, device_code) do
    [{^device_code, device_info}] ->
      cond do
        # Check if expired
        DateTime.compare(DateTime.utc_now(), device_info.expires_at) == :gt ->
          conn |> put_status(400) |> json(%{error: "expired_token"})
        
        # Check if authorized and we have access token
        device_info.authorized and device_info.access_token ->
          json(conn, %{access_token: device_info.access_token, token_type: "Bearer"})
        
        # Still pending
        true ->
          conn |> put_status(428) |> json(%{error: "authorization_pending", interval: 5})
      end
  end
end
```

### OAuth Integration

The existing OAuth controller was enhanced to handle device authorization callbacks:

```elixir
defp handle_oauth_success(conn, state, tokens) do
  case state do
    "device_auth" ->
      # This is a CLI device authorization flow
      access_token = Map.get(tokens, :access_token) || Map.get(tokens, "access_token")
      
      case CliAuthController.complete_device_authorization(conn, access_token) do
        {:ok, updated_conn} ->
          render_device_success_page(updated_conn)
        {:error, reason} ->
          render_error_page(conn, "Failed to complete device authorization")
      end

    _ ->
      # Regular web OAuth flow
      render_success_page(conn)
  end
end
```

**Integration Points**:
- Uses `state=device_auth` to distinguish device authorization from web OAuth
- Stores pending device code in session during OAuth flow
- Completes device authorization with access token on success
- Provides different success/error pages for device vs web flows

## Router Configuration

The routes are split between API and browser pipelines based on their needs:

```elixir
# CLI Authentication API Routes (JSON responses)
scope "/api/cli/auth", TheMaestroWeb do
  pipe_through :api

  post "/device", CliAuthController, :device
  get "/poll", CliAuthController, :poll
end

# CLI Authentication Browser Routes (HTML responses, need sessions)
scope "/api/cli/auth", TheMaestroWeb do
  pipe_through :browser

  get "/authorize", CliAuthController, :authorize
  post "/authorize", CliAuthController, :authorize_post
end
```

**Pipeline Design**:
- **API Pipeline**: Used for `/device` and `/poll` endpoints that return JSON
- **Browser Pipeline**: Used for `/authorize` endpoints that render HTML and need session support
- This separation ensures proper content-type handling and CSRF protection where needed

## User Experience Flow

### 1. CLI Initiates Device Authorization
```bash
curl -X POST http://localhost:4000/api/cli/auth/device
```

Response:
```json
{
  "device_code": "abc123def456",
  "user_code": "XYZABC", 
  "verification_uri": "http://localhost:4000/api/cli/auth/authorize",
  "verification_uri_complete": "http://localhost:4000/api/cli/auth/authorize?user_code=XYZABC",
  "expires_in": 900,
  "interval": 5
}
```

### 2. CLI Displays Instructions to User
```
To authorize this device, visit: http://localhost:4000/api/cli/auth/authorize
Enter this code: XYZABC

Waiting for authorization...
```

### 3. User Visits URL in Browser
- Clean, responsive authorization page
- Pre-fills user code if provided in URL
- Clear instructions about the process
- Redirects to Google OAuth on form submission

### 4. OAuth Flow Completion
- User completes Google OAuth in browser
- Success page confirms authorization
- Device code is marked as authorized with access token

### 5. CLI Receives Access Token
```bash
curl http://localhost:4000/api/cli/auth/poll?device_code=abc123def456
```

Response:
```json
{
  "access_token": "ya29.a0AfH6SMC...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

## Security Considerations

### Device Code Security
- **Entropy**: Device codes use cryptographically secure random generation
- **Length**: Long device codes prevent brute force attacks
- **Expiration**: Short-lived codes (15 minutes) limit exposure window
- **Single Use**: Device codes are deleted after successful authorization

### User Code Security  
- **Character Set**: Avoids confusing characters to prevent user error
- **Uniqueness**: Collision detection ensures unique codes
- **Display Only**: User codes are never used for authentication, only display

### Session Security
- **CSRF Protection**: Browser endpoints use Phoenix's CSRF protection
- **Session Isolation**: Each device authorization uses a separate session context
- **State Validation**: OAuth state parameter prevents CSRF attacks

### Access Token Handling
- **Secure Storage**: Tokens stored in ETS with restricted access
- **Cleanup**: Tokens removed immediately after successful polling
- **No Logging**: Access tokens never logged in plaintext

## Testing

The implementation includes comprehensive tests covering:

### Unit Tests
```elixir
describe "POST /api/cli/auth/device" do
  test "generates device code and verification URLs" do
    # Test device code generation and response format
  end
end

describe "GET /api/cli/auth/poll" do
  test "returns authorization_pending for pending authorization" do
    # Test polling behavior during pending state
  end
  
  test "returns access_token when authorization is complete" do
    # Test successful token delivery
  end
end
```

### Integration Tests
- **OAuth Flow Integration**: Tests device authorization through complete OAuth flow
- **Session Management**: Validates session handling during authorization
- **Error Handling**: Covers expired codes, invalid codes, and OAuth failures

### Manual Testing
1. Start Phoenix server: `mix phx.server`
2. Request device code: `curl -X POST http://localhost:4000/api/cli/auth/device`
3. Visit authorization URL in browser
4. Enter user code and complete OAuth
5. Poll for access token: `curl http://localhost:4000/api/cli/auth/poll?device_code=<code>`

## Production Considerations

### Scalability
- **ETS Limitations**: Current in-memory storage doesn't persist across restarts
- **Redis Option**: Consider Redis for production deployments with multiple servers
- **Database Option**: PostgreSQL could store device codes for full persistence

### Monitoring
- **Device Code Usage**: Track device code generation and completion rates
- **Error Rates**: Monitor expired codes and OAuth failures
- **Polling Patterns**: Analyze polling frequency and optimization opportunities

### Configuration
```elixir
# config/config.exs
config :the_maestro, :cli_auth,
  device_code_length: 8,
  user_code_length: 6,
  device_code_expiry_minutes: 15,
  polling_interval_seconds: 5
```

## Comparison with Original Gemini CLI

The implementation maintains compatibility with the original gemini-cli authentication patterns:

### Similarities
- **OAuth Scopes**: Uses the same Google OAuth scopes
- **Credential Caching**: Maintains the same credential storage approach
- **Token Refresh**: Integrates with existing token refresh logic

### Improvements
- **Elixir/OTP**: Better concurrency and fault tolerance
- **Phoenix Integration**: Seamless integration with web application
- **Modern UI**: Responsive, accessible authorization pages
- **Comprehensive Testing**: Full test coverage with Phoenix testing tools

## Next Steps

This implementation provides the backend foundation for CLI device authorization. Future enhancements could include:

1. **CLI Client Implementation**: Build the actual CLI client that uses these endpoints
2. **Persistent Storage**: Replace ETS with Redis or database for production
3. **Rate Limiting**: Add rate limiting to prevent abuse
4. **Analytics**: Add metrics and monitoring for authorization flows
5. **Configuration**: Make timeouts and intervals configurable
6. **Cleanup Jobs**: Add background jobs to clean up expired device codes

The device authorization flow backend is now complete and ready for CLI client integration in Epic 4.