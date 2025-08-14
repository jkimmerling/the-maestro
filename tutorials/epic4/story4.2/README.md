# Epic 4, Story 4.2: Configurable TUI Authentication

## Overview

This tutorial explains how we implemented configurable authentication for the Terminal User Interface (TUI) in The Maestro project. The TUI now supports multiple authentication methods including API key authentication (via GEMINI_API_KEY environment variable), Google OAuth 2.0 device authorization flow, and anonymous mode based on application configuration.

## Learning Objectives

By the end of this tutorial, you'll understand:
- How to implement multiple authentication methods (API key and OAuth 2.0)
- How to integrate with Gemini provider authentication system
- How to create user-friendly authentication selection menus
- How to securely store authentication tokens and preferences locally
- How to implement Google OAuth 2.0 Device Authorization Grant flow

## Architecture Overview

The TUI authentication system consists of several components:

1. **Configuration Reading**: Reads `require_authentication` from application config
2. **Authentication Method Selection**: Interactive menu to choose between API key and OAuth
3. **API Key Authentication**: Uses GEMINI_API_KEY environment variable
4. **Google OAuth Device Flow**: Implements OAuth 2.0 device flow via Gemini provider
5. **Token Storage**: Securely stores access tokens and preferences in user's home directory
6. **Anonymous Mode**: Bypasses authentication when configured

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

### 2. Authentication Method Selection

The TUI provides an interactive menu for users to choose their preferred authentication method:

```elixir
defp show_authentication_menu do
  IO.write([IO.ANSI.clear(), IO.ANSI.home()])
  
  # Display menu with current environment status
  api_key_available = System.get_env("GEMINI_API_KEY") != nil
  
  if api_key_available do
    IO.puts([IO.ANSI.bright(), IO.ANSI.green(), "1. ", IO.ANSI.reset(),
            IO.ANSI.bright(), "API Key", IO.ANSI.reset(), 
            " (GEMINI_API_KEY detected)"])
  else
    IO.puts([IO.ANSI.faint(), "1. API Key (No GEMINI_API_KEY found)", IO.ANSI.reset()])
  end
  
  IO.puts([IO.ANSI.bright(), IO.ANSI.cyan(), "2. ", IO.ANSI.reset(),
          IO.ANSI.bright(), "OAuth (Google Account)", IO.ANSI.reset()])
end
```

### 3. API Key Authentication

For users with GEMINI_API_KEY environment variable set:

```elixir
defp handle_api_key_authentication do
  case System.get_env("GEMINI_API_KEY") do
    nil ->
      {:error, "GEMINI_API_KEY not found"}
    
    api_key ->
      auth_info = %{
        authenticated: true,
        method: :api_key,
        api_key: api_key
      }
      
      save_auth_preference("api_key")
      {:ok, auth_info}
  end
end
```

### 4. Google OAuth Device Authorization Flow

The OAuth 2.0 Device Authorization Grant integrates with the Gemini provider system:

#### OAuth Flow Implementation

The TUI delegates OAuth authentication to the Gemini provider:

```elixir
defp start_device_authorization do
  # Use the Gemini provider's device authorization flow
  case TheMaestro.Providers.Gemini.device_authorization_flow() do
    {:ok, %{auth_url: auth_url, state: state, code_verifier: code_verifier, polling_fn: polling_fn}} ->
      display_google_oauth_instructions(auth_url, state)
      poll_for_google_authorization(polling_fn, code_verifier)
      
    {:error, reason} ->
      {:error, "Failed to start Google OAuth: #{reason}"}
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

#### Authorization Completion

The TUI uses the Gemini provider's polling function and completion handler:

```elixir
defp poll_for_google_authorization(polling_fn, code_verifier) do
  # Get the authorization code from the user
  case polling_fn.() do
    "" ->
      {:error, "No authorization code provided"}
      
    auth_code ->
      # Complete the device authorization with the code
      case TheMaestro.Providers.Gemini.complete_device_authorization(auth_code, code_verifier) do
        {:ok, auth_info} ->
          handle_successful_google_authorization(auth_info)
          
        {:error, reason} ->
          {:error, "Failed to complete Google OAuth: #{inspect(reason)}"}
      end
  end
end

defp handle_successful_google_authorization(auth_info) do
  # Convert Gemini provider auth format to TUI format
  tui_auth_info = %{
    authenticated: true,
    method: :oauth,
    access_token: auth_info.access_token,
    user_email: auth_info[:user_email] || "google_user"
  }
  
  store_token(tui_auth_info)
  {:ok, tui_auth_info}
end
```

### 5. Secure Token Storage and Preference Management

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

The system also stores user authentication preferences:

```elixir
defp save_auth_preference(method) when method in ["api_key", "oauth"] do
  home_dir = System.user_home!()
  maestro_dir = Path.join(home_dir, ".maestro")
  pref_file = Path.join(maestro_dir, "auth_preference.txt")
  
  File.mkdir_p!(maestro_dir)
  File.write!(pref_file, method)
end

defp load_auth_preference do
  home_dir = System.user_home!()
  pref_file = Path.join([home_dir, ".maestro", "auth_preference.txt"])
  
  case File.read(pref_file) do
    {:ok, content} ->
      method = String.trim(content)
      if method in ["api_key", "oauth"], do: {:ok, method}, else: {:error, :invalid_preference}
    {:error, :enoent} ->
      {:error, :no_preference}
    {:error, reason} ->
      {:error, reason}
  end
end
```

### 6. Anonymous Mode Implementation

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

### 7. Integration with Existing Gemini Provider

The TUI leverages the existing Gemini provider authentication system:

```elixir
defp load_stored_token do
  # Try to load OAuth credentials from the Gemini provider's cache first
  case TheMaestro.Providers.Gemini.initialize_auth() do
    {:ok, %{type: :oauth, credentials: credentials}} ->
      # Convert to TUI format
      auth_info = %{
        authenticated: true,
        method: :oauth,
        access_token: credentials.access_token,
        user_email: credentials[:user_email] || "google_user"
      }
      {:ok, auth_info}
      
    {:error, _reason} ->
      # Fallback to TUI-specific token file
      load_tui_specific_token()
  end
end
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

### Test API Key Authentication

1. Set `GEMINI_API_KEY` environment variable
2. Set `require_authentication: true` in config
3. Build escript: `MIX_ENV=prod mix escript.build`
4. Run TUI: `./maestro_tui`
5. Should detect API key and offer it as option 1
6. Select option 1 to use API key authentication

### Test OAuth Authentication

1. Unset `GEMINI_API_KEY` or choose option 2 in menu
2. Set `require_authentication: true` in config
3. Build escript: `MIX_ENV=prod mix escript.build`
4. Run TUI: `./maestro_tui`
5. Select option 2 for OAuth
6. Follow the Google OAuth flow
7. Complete authorization in browser

### Test Authentication Preference

1. Complete authentication once with your preferred method
2. Exit and restart TUI
3. Should automatically use saved preference
4. Should display authentication status accordingly

## Key Learning Points

1. **Multi-Method Authentication**: Supporting both API key and OAuth authentication methods
2. **User Choice**: Providing interactive menus for authentication method selection
3. **Provider Integration**: Leveraging existing Gemini provider authentication system
4. **Preference Management**: Storing and reusing user authentication preferences
5. **Secure Storage**: Properly securing authentication credentials on the local filesystem
6. **User Experience**: Clear instructions and visual feedback for CLI authentication flows

## Best Practices Demonstrated

1. **Separation of Concerns**: Authentication logic is cleanly separated from UI logic
2. **Security First**: Default to requiring authentication, secure token storage
3. **Error Recovery**: Graceful handling of network failures and timeouts
4. **User Feedback**: Clear visual feedback and instructions throughout the flow
5. **Configuration Flexibility**: Easy switching between authenticated and anonymous modes

## Integration with Existing System

The TUI authentication integrates seamlessly with the existing Gemini provider system:

1. **Shared Provider Logic**: Uses the same Gemini provider authentication methods
2. **Consistent Token Management**: Leverages existing OAuth token caching where possible
3. **Fallback Strategy**: Falls back to TUI-specific storage when needed
4. **Configuration Compatibility**: Respects the same application configuration settings
5. **Security Consistency**: Follows the same security practices across all interfaces

This implementation provides a complete, production-ready authentication system for CLI applications that leverages existing infrastructure while maintaining the flexibility to operate in anonymous mode when appropriate. The multi-method approach ensures users can choose the authentication method that best fits their workflow and security requirements.