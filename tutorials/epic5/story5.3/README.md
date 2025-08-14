# Epic 5, Story 5.3: TUI Model Selection Flow Tutorial

This tutorial explains how we implemented a comprehensive Terminal User Interface (TUI) model selection flow that allows users to select LLM providers, authenticate securely, and choose models dynamically.

## Overview

The TUI Model Selection Flow provides a structured, numbered menu interface for:

1. **Provider Selection** - Choose between Claude (Anthropic), Gemini (Google), and ChatGPT (OpenAI)
2. **Authentication Method Selection** - Select between OAuth and API Key authentication
3. **Authentication Flow** - Complete secure authentication with chosen method  
4. **Model Selection** - Dynamically select from available models after authentication
5. **Chat Interface Activation** - Seamless transition to conversation interface

## Architecture

The implementation consists of 6 modular components:

```
lib/the_maestro/tui/
├── menu_helpers.ex        # Common TUI menu utilities
├── provider_selection.ex  # Provider selection interface
├── auth_flow.ex          # Authentication flow coordinator
├── api_key_handler.ex    # Secure API key input & validation
├── oauth_handler.ex      # OAuth flow for TUI environments
├── model_selection.ex    # Dynamic model selection
└── cli.ex               # Updated main CLI integration
```

## Implementation Details

### 1. MenuHelpers Module (`menu_helpers.ex`)

Provides reusable TUI components:

**Key Functions:**
- `display_menu/3` - Shows numbered menus with descriptions
- `get_menu_choice/2` - Validates numeric input with range checking
- `display_error/2` - Consistent error display with retry options
- `get_secure_input/2` - Masked input for sensitive data like API keys
- `display_loading/2` - Animated spinner for async operations

**Example Usage:**
```elixir
options = ["Claude (Anthropic)", "Gemini (Google)", "ChatGPT (OpenAI)"]
MenuHelpers.display_menu("SELECT PROVIDER", options)

case MenuHelpers.get_menu_choice("Enter choice (1-3): ", 1..3) do
  {:ok, choice} -> handle_choice(choice)
  {:error, :invalid_choice} -> show_error_and_retry()
end
```

### 2. ProviderSelection Module (`provider_selection.ex`)

Manages provider selection with detailed information display:

**Features:**
- Dynamic provider discovery via `ProviderRegistry`
- Provider capability and authentication method display
- Confirmation flow with detailed provider information
- Navigation support (back, cancel, quit)

**Key Function:**
```elixir
def select_provider do
  providers = get_available_providers()
  display_provider_menu(providers)
  handle_provider_selection(providers)
end
```

### 3. AuthFlow Module (`auth_flow.ex`) 

Coordinates authentication across different methods and providers:

**Responsibilities:**
- Method detection and presentation
- Authentication preference persistence
- Cross-method error handling and recovery
- Validation of authentication contexts

**Authentication Methods Supported:**
- **API Key**: Direct API key input with format validation
- **OAuth**: Browser-based authentication flow
- **Service Account**: Google Cloud service account authentication

**Example Flow:**
```elixir
case AuthFlow.authenticate_provider(:anthropic) do
  {:ok, auth_context} -> 
    # Authentication successful, proceed to model selection
  {:error, :back_to_provider} -> 
    # User wants to select different provider
  {:error, reason} -> 
    # Handle authentication failure
end
```

### 4. APIKeyHandler Module (`api_key_handler.ex`)

Provides secure API key input and validation:

**Security Features:**
- Input masking for security (shows asterisks while typing)
- Format validation for each provider's API key patterns
- Real-time API key testing via provider APIs
- Secure error handling without exposing keys in logs

**API Key Patterns:**
- **Anthropic**: `sk-ant-api03-[95 chars]`
- **Google**: `[39 alphanumeric chars]` 
- **OpenAI**: `sk-[48 chars]`

**Validation Flow:**
```elixir
case APIKeyHandler.handle_api_key_auth(provider) do
  {:ok, auth_context} -> proceed_to_model_selection()
  {:error, :try_oauth} -> switch_to_oauth()
  {:error, reason} -> handle_validation_error(reason)
end
```

### 5. OAuthHandler Module (`oauth_handler.ex`)

Manages OAuth authentication flows optimized for terminal environments:

**OAuth Strategies:**
- **Device Code Flow**: For Google/Gemini (user enters code in browser)
- **Browser Callback Flow**: For Anthropic/OpenAI (embedded server)
- **Polling Mechanism**: Automatic status checking

**Device Code Flow Example:**
```
OAuth Authentication for Gemini:

1. Open this URL in your browser:
   https://accounts.google.com/oauth/authorize?client_id=...

2. Enter this code when prompted: XYZW-ABCD

3. Waiting for authorization... (Press Ctrl+C to cancel)
   [●○○] Checking authorization status...
```

### 6. ModelSelection Module (`model_selection.ex`)

Handles dynamic model discovery and selection:

**Features:**
- Real-time model fetching from authenticated providers
- Fallback to known models if API calls fail
- Rich model information display (capabilities, context length, performance)
- Recommended model highlighting

**Model Information Display:**
```
Available Claude Models:
1. Claude 3.5 Sonnet (Recommended)
   Advanced reasoning and analysis capabilities

2. Claude 3 Opus (Most Capable)
   Highest intelligence and capability

3. Claude 3 Haiku (Fastest)
   Fastest and most efficient
```

### 7. CLI Integration (`cli.ex`)

Updated main CLI to integrate the new flow:

**Changes:**
- Replaced simple authentication with full provider/model selection
- Updated state management to store provider, model, and auth context
- Modified agent creation to use selected configuration
- Enhanced welcome messages with configuration display

**Welcome Message Example:**
```
Welcome to The Maestro TUI!
✓ Provider: Claude (Anthropic)  
✓ Model: Claude 3.5 Sonnet
✓ Authentication: OAuth

Type your message and press Enter to chat with the agent.
Press Ctrl-C or 'q' to exit.
```

## User Experience Flow

The complete user flow follows this sequence:

1. **Provider Selection**
   ```
   SELECT YOUR LLM PROVIDER
   
   1. Claude (Anthropic)
      Advanced reasoning and analysis capabilities
   2. Gemini (Google)  
      Multimodal AI with strong integration
   3. ChatGPT (OpenAI)
      Versatile conversational AI
   4. Back to main menu
   ```

2. **Authentication Method Selection**
   ```
   AUTHENTICATION FOR CLAUDE (ANTHROPIC)
   
   1. OAuth (Recommended) - Authenticate via web browser
   2. API Key - Enter your API key directly  
   3. Back to provider selection
   ```

3. **Authentication Process**
   - **OAuth**: Browser-based with device code or callback
   - **API Key**: Secure masked input with validation

4. **Model Selection**
   ```
   AVAILABLE CLAUDE MODELS
   
   1. Claude 3.5 Sonnet (Recommended)
      Enhanced reasoning and analysis
   2. Claude 3 Opus (Most Capable)
      Highest intelligence level
   3. Claude 3 Haiku (Fastest)
      Fastest and most efficient
   ```

5. **Configuration Confirmation**
   ```
   Configuration Complete:
   ✓ Provider: Claude (Anthropic)
   ✓ Authentication: OAuth
   ✓ Model: Claude 3.5 Sonnet
   
   Starting chat interface...
   ```

## Error Handling & Recovery

The implementation provides comprehensive error handling:

### Network Issues
```
⚠ Network Error: Unable to connect to Claude API

Options:
1. Retry connection
2. Try different authentication method  
3. Back to provider selection
4. Exit configuration
```

### Authentication Failures  
```
✗ Authentication Failed: Invalid API key

Options:
1. Re-enter API key
2. Try OAuth instead
3. Back to provider selection
```

### Model Loading Failures
```
⚠ Unable to load model list from provider

Options:
1. Retry loading models
2. Use default model (claude-3-5-sonnet)
3. Back to authentication
```

## Navigation Features

- **Back Navigation**: Every menu provides "Back" options
- **Cancel Support**: Ctrl+C cancellation at any point with graceful cleanup
- **Flow State**: Maintains selection state during navigation
- **Error Recovery**: Returns to appropriate menu level on errors

## Technical Implementation Notes

### State Machine Pattern
The flow implements a state machine:
```
:provider_selection → :auth_method_selection → :authenticating → :model_selection → :chat_ready
```

### Security Considerations
- API keys are masked during input
- Sensitive data is not logged in error messages
- OAuth tokens are securely stored
- Input validation prevents injection attacks

### Performance Optimizations
- Model lists are cached when possible
- Fallback to known models prevents API dependency
- Async operations with loading indicators
- Efficient state management in process dictionary

## Testing

The implementation includes comprehensive tests:
- Unit tests for each module
- Integration tests for complete flows
- Error handling scenario tests
- User input validation tests

Run tests with:
```bash
mix test test/the_maestro/tui/
```

## Future Enhancements

Potential improvements identified:
- Configuration persistence between sessions
- Multi-language support
- Enhanced accessibility features
- Offline mode with cached model lists
- Custom provider configuration

## Conclusion

The TUI Model Selection Flow successfully implements the story requirements:

✅ Provider selection menu with numbered choices  
✅ Authentication method selection for all providers  
✅ OAuth flow functional with browser-based authentication  
✅ API key input with secure masking and validation  
✅ Dynamic model selection with real-time fetching  
✅ Navigation flow with back/cancel operations  
✅ Comprehensive error handling and recovery  
✅ Integration with chat interface  
✅ Session and configuration persistence  
✅ Terminal compatibility across platforms

The modular architecture ensures maintainability while providing a smooth, professional user experience that guides users through complex provider and model selection with clear feedback and error recovery options.