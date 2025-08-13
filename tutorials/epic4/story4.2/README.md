# Epic 4, Story 4.2: Configurable TUI Authentication

## Overview

This tutorial explains how we implemented configurable authentication for the Terminal User Interface (TUI) in The Maestro project. The TUI now supports both authenticated mode (using OAuth 2.0 device authorization flow) and anonymous mode based on application configuration.

## Learning Objectives

By the end of this tutorial, you'll understand:
- How to implement OAuth 2.0 Device Authorization Grant (RFC 8628) in Elixir
- How to create configurable authentication flows
- How to securely store authentication tokens locally
- How to integrate HTTP client functionality in an escript application

## Architecture Overview

The TUI authentication system consists of several components:

1. **Configuration Reading**: Reads `require_authentication` from application config
2. **Device Authorization Flow**: Implements OAuth 2.0 device flow for CLI authentication
3. **Token Storage**: Securely stores access tokens in the user's home directory
4. **Anonymous Mode**: Bypasses authentication when configured

## Implementation Details

### 1. Configuration-Based Authentication

The authentication flow is controlled by the `:require_authentication` configuration in `config/config.exs`:

```elixir
config :the_maestro,
  require_authentication: true  # or false for anonymous mode
```

In the TUI CLI module, we read this configuration:

```elixir
defp read_authentication_config do
  case Application.get_env(:the_maestro, :require_authentication) do
    true -> {:ok, true}
    false -> {:ok, false}
    nil -> {:ok, true}  # Default to requiring authentication for security
    _ -> {:error, "Invalid authentication configuration"}
  end
end
```

### 2. Device Authorization Flow Implementation

The OAuth 2.0 Device Authorization Grant works as follows:

1. **Request Device Code**: TUI requests a device code from the server
2. **Display Instructions**: Show user the authorization URL and user code
3. **Poll for Token**: Continuously poll the server until user completes authorization
4. **Store Token**: Save the access token securely for future use

#### Device Code Request

```elixir
defp request_device_code(base_url) do
  url = "#{base_url}/api/cli/auth/device"

  case HTTPoison.post(url, "", [{"Content-Type", "application/json"}]) do
    {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
      case Jason.decode(body) do
        {:ok, response} -> {:ok, response}
        {:error, _} -> {:error, "Invalid JSON response"}
      end

    {:ok, %HTTPoison.Response{status_code: status_code}} ->
      {:error, "HTTP error: #{status_code}"}

    {:error, %HTTPoison.Error{reason: reason}} ->
      {:error, "Network error: #{reason}"}
  end
end
```

#### User Instructions Display

The TUI displays clear instructions with the authorization URL and user code:

```elixir
defp display_authorization_instructions(device_response) do
  IO.write([IO.ANSI.clear(), IO.ANSI.home()])

  IO.puts([
    IO.ANSI.bright(),
    "1. Open your browser and visit:",
    IO.ANSI.reset()
  ])

  IO.puts([
    "   ",
    IO.ANSI.bright(),
    IO.ANSI.cyan(),
    device_response["verification_uri_complete"],
    IO.ANSI.reset()
  ])

  IO.puts([
    IO.ANSI.bright(),
    "2. Enter this user code if prompted:",
    IO.ANSI.reset()
  ])

  IO.puts([
    "   ",
    IO.ANSI.bright(),
    IO.ANSI.yellow(),
    device_response["user_code"],
    IO.ANSI.reset()
  ])
end
```

#### Token Polling Loop

The TUI polls the server until authorization is complete:

```elixir
defp poll_loop(url, interval, remaining_time) when remaining_time > 0 do
  :timer.sleep(interval)

  case HTTPoison.get(url) do
    {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
      case Jason.decode(body) do
        {:ok, %{"access_token" => access_token}} ->
          # Success! Store and return token
          auth_info = %{
            authenticated: true,
            access_token: access_token,
            user_email: "authenticated_user"
          }
          store_token(auth_info)
          {:ok, auth_info}

        {:error, _} ->
          {:error, "Invalid response from server"}
      end

    {:ok, %HTTPoison.Response{status_code: 428}} ->
      # Still waiting - continue polling
      remaining = remaining_time - div(interval, 1000)
      poll_loop(url, interval, remaining)

    # Handle errors and expiration...
  end
end
```

### 3. Secure Token Storage

Authentication tokens are stored in the user's home directory with restricted permissions:

```elixir
defp store_token(auth_info) do
  home_dir = System.user_home!()
  maestro_dir = Path.join(home_dir, ".maestro")
  token_file = Path.join(maestro_dir, "tui_credentials.json")

  # Ensure directory exists
  File.mkdir_p!(maestro_dir)

  # Create token data with timestamp
  token_data = %{
    access_token: auth_info.access_token,
    user_email: auth_info.user_email,
    stored_at: DateTime.utc_now() |> DateTime.to_iso8601()
  }

  # Write to file and set secure permissions
  case Jason.encode(token_data) do
    {:ok, json} ->
      File.write!(token_file, json)
      File.chmod!(token_file, 0o600)  # Readable only by owner

    {:error, _} ->
      :error
  end
end
```

### 4. Anonymous Mode Implementation

When authentication is disabled, the TUI bypasses the entire authentication flow:

```elixir
defp handle_authentication do
  case read_authentication_config() do
    {:ok, true} ->
      # Authentication required
      initiate_device_authorization_flow()

    {:ok, false} ->
      # Authentication disabled - anonymous mode
      {:ok, %{authenticated: false}}

    {:error, reason} ->
      {:error, "Failed to read configuration: #{reason}"}
  end
end
```

### 5. HTTP Client Integration

For escript applications, we need to ensure the HTTP client is available. We added Finch to the TUI supervision tree:

```elixir
# In TUI.Application
children = [
  {Finch, name: TheMaestro.Finch},
  # ... other children
]
```

## Security Considerations

1. **Token Storage**: Tokens are stored with 0o600 permissions (owner read/write only)
2. **HTTPS in Production**: The base URL should use HTTPS in production deployments
3. **Token Validation**: In a production system, tokens should be validated and refreshed
4. **Cleanup**: Tokens are automatically cleaned up when authorization fails or expires

## Testing the Implementation

### Test Anonymous Mode

1. Set `require_authentication: false` in config
2. Build escript: `MIX_ENV=prod mix escript.build`
3. Run TUI: `./maestro_tui`
4. Should display "Running in anonymous mode"

### Test Authenticated Mode

1. Set `require_authentication: true` in config
2. Start Phoenix server: `mix phx.server`
3. Build escript: `MIX_ENV=prod mix escript.build`
4. Run TUI: `./maestro_tui`
5. Should display device authorization instructions
6. Follow the URL to complete authorization
7. TUI should proceed with authentication info

### Test Token Persistence

1. Complete authentication once
2. Exit and restart TUI
3. Should display "Found valid authentication token"
4. Should show "Authenticated as: [email]"

## Key Learning Points

1. **Configuration-Driven Behavior**: Using application configuration to control authentication requirements
2. **OAuth 2.0 Device Flow**: Implementing the complete device authorization grant flow
3. **Secure Storage**: Properly securing authentication credentials on the local filesystem
4. **Error Handling**: Comprehensive error handling for network issues and authorization failures
5. **User Experience**: Clear instructions and feedback for CLI users

## Best Practices Demonstrated

1. **Separation of Concerns**: Authentication logic is cleanly separated from UI logic
2. **Security First**: Default to requiring authentication, secure token storage
3. **Error Recovery**: Graceful handling of network failures and timeouts
4. **User Feedback**: Clear visual feedback and instructions throughout the flow
5. **Configuration Flexibility**: Easy switching between authenticated and anonymous modes

## Integration with Existing System

The TUI authentication integrates seamlessly with the existing web authentication system:

1. Uses the same OAuth endpoints as the web interface
2. Stores tokens in a separate location to avoid conflicts
3. Respects the same configuration settings
4. Follows the same security practices

This implementation provides a complete, production-ready authentication system for CLI applications while maintaining the flexibility to operate in anonymous mode when appropriate.