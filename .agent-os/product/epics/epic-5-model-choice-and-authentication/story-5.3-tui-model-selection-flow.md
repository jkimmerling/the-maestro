# Story 5.3: TUI Model Selection Flow

## User Story
**As a** CLI User,  
**I want** to select my LLM provider and model through a structured terminal interface with numbered choices,  
**so that** I can efficiently configure my agent without requiring a web browser for the entire flow.

## Acceptance Criteria

### Provider Selection Flow
1. **Provider Menu**: Present numbered list of providers:
   ```
   Select your LLM Provider:
   1. Claude (Anthropic)
   2. Gemini (Google) 
   3. ChatGPT (OpenAI)
   4. Back to main menu
   
   Enter your choice (1-4): 
   ```

2. **Provider Information**: Display brief information about selected provider:
   - Capabilities and strengths
   - Authentication requirements
   - Model availability

### Authentication Method Selection
3. **Auth Method Menu**: After provider selection, show authentication options:
   ```
   Authentication for Claude (Anthropic):
   1. OAuth (Recommended) - Authenticate via web browser
   2. API Key - Enter your API key directly
   3. Back to provider selection
   
   Enter your choice (1-3):
   ```

### OAuth Flow (TUI)
4. **Browser-Based OAuth**: For OAuth selection:
   - Display authorization URL for user to visit
   - Show device code if applicable (for providers supporting device flow)
   - Provide clear instructions
   - Poll for authorization completion
   - Show success/failure status
   
   ```
   OAuth Authentication for Claude:
   
   1. Open this URL in your browser:
      https://auth.anthropic.com/oauth/authorize?client_id=...
   
   2. Enter this code when prompted: XYZW-ABCD
   
   3. Waiting for authorization... (Press Ctrl+C to cancel)
      [●○○] Checking authorization status...
   ```

### API Key Flow (TUI)
5. **API Key Input**: For API key selection:
   - Secure input (masked characters)
   - Real-time validation
   - Clear error messages
   - Option to retry or go back
   
   ```
   Enter your Claude API Key:
   API Key: ******************** (masked)
   
   [Testing connection...]
   ✓ API Key validated successfully!
   ```

### Model Selection Flow
6. **Dynamic Model List**: After successful authentication:
   ```
   Available Claude Models:
   1. claude-3-5-sonnet-20241022 (Recommended)
   2. claude-3-opus-20240229 (Most Capable) 
   3. claude-3-haiku-20240307 (Fastest)
   4. Back to authentication options
   
   Enter your choice (1-4):
   ```

7. **Model Information**: Show detailed info for each model:
   - Context length
   - Capabilities (text, vision, etc.)
   - Performance characteristics
   - Cost information (if available)

### Navigation & Flow Control
8. **Back Navigation**: Always provide "Back" options to return to previous menus
9. **Cancel Option**: Allow Ctrl+C cancellation at any point with graceful cleanup
10. **Flow State**: Maintain selection state during navigation
11. **Error Recovery**: Return to appropriate menu level on errors

### Chat Interface Activation
12. **Completion Confirmation**: After model selection:
    ```
    Configuration Complete:
    ✓ Provider: Claude (Anthropic)
    ✓ Authentication: OAuth
    ✓ Model: claude-3-5-sonnet-20241022
    
    Starting chat interface...
    ```

13. **Chat Interface Integration**: Seamlessly transition to chat interface with:
    - Selected provider and model active
    - Connection status visible
    - Option to reconfigure

## Technical Implementation

### TUI Module Structure
```elixir
lib/the_maestro/tui/
├── provider_selection.ex    # Provider selection menu
├── auth_flow.ex            # Authentication flow coordinator  
├── model_selection.ex      # Model selection interface
├── oauth_handler.ex        # OAuth flow for TUI
├── api_key_handler.ex     # API key input and validation
└── menu_helpers.ex        # Common menu utilities
```

### Menu State Management
14. **State Machine**: Implement state machine for flow control:
    ```elixir
    # Flow states
    :provider_selection → :auth_method_selection → :authenticating → :model_selection → :chat_ready
    ```

15. **Session Persistence**: Store selections in TUI session state
16. **Configuration Persistence**: Save successful configurations for future sessions

### Input Validation & Error Handling  
17. **Input Validation**: Robust validation for:
    - Numeric menu choices
    - API key format validation  
    - Network connectivity checks
18. **Error Recovery**: Graceful error handling with:
    - Clear error messages
    - Retry mechanisms
    - Fallback options

### Integration with Authentication System
19. **Auth System Integration**: Use Story 5.1 authentication architecture
20. **Credential Storage**: Secure storage of TUI authentication results
21. **Session Management**: Integration with existing session management

## User Experience Requirements

### Terminal Compatibility
- Works with standard terminal emulators
- ANSI color support with graceful fallback
- Proper cursor management
- Screen clearing and redrawing

### Performance
- Responsive menu navigation
- Fast authentication validation
- Minimal network calls for model lists
- Efficient state updates

### Accessibility
- Screen reader compatible output
- Clear visual hierarchy
- Keyboard-only navigation
- High contrast display options

## Error Scenarios & Recovery

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

## Dependencies
- Story 5.1 (Multi-Provider Authentication Architecture)
- Story 5.4 (Dynamic Model Discovery Service)
- Existing TUI infrastructure from Epic 4
- Terminal UI library (ratatouille)

## Definition of Done
- [x] Provider selection menu implemented with numbered choices
- [x] Authentication method selection working for all providers
- [x] OAuth flow functional with browser-based authentication
- [x] API key input and validation operational
- [x] Dynamic model selection with real-time fetching
- [x] Navigation flow supports back/cancel operations
- [x] Error handling and recovery mechanisms implemented
- [x] Integration with chat interface completed
- [x] Session and configuration persistence working
- [x] Terminal compatibility verified across platforms
- [x] Performance meets responsiveness requirements
- [x] Integration tests covering full TUI flow
- [x] Tutorial created in `tutorials/epic5/story5.3/`

## Implementation Summary

✅ **COMPLETED** - Epic 5, Story 5.3: TUI Model Selection Flow has been successfully implemented.

### What Was Built

**6 Core Modules Implemented:**
1. **MenuHelpers** (`menu_helpers.ex`) - Common TUI utilities with secure input, menu display, and error handling
2. **ProviderSelection** (`provider_selection.ex`) - Provider selection interface with capability display
3. **AuthFlow** (`auth_flow.ex`) - Authentication coordination supporting API key, OAuth, and service account methods
4. **APIKeyHandler** (`api_key_handler.ex`) - Secure API key input with masking and real-time validation
5. **OAuthHandler** (`oauth_handler.ex`) - OAuth flows optimized for terminal environments
6. **ModelSelection** (`model_selection.ex`) - Dynamic model selection with provider-specific information

**Main CLI Integration:**
- Updated `cli.ex` with complete provider/model selection flow
- Replaced simple authentication with comprehensive selection process
- Enhanced welcome messages with configuration display
- Integrated with existing agent creation and state management

### Key Features Delivered

**Provider Selection:**
- Numbered menu interface for Claude (Anthropic), Gemini (Google), and ChatGPT (OpenAI)
- Provider capability and authentication method information display
- Navigation support with back/cancel operations

**Authentication Flow:**
- Multiple authentication methods: API Key, OAuth, Service Account
- Secure API key input with character masking
- OAuth device authorization flow with browser integration
- Real-time validation and error recovery

**Model Selection:**
- Dynamic model fetching from authenticated providers
- Fallback to known models if API calls fail
- Rich model information display (capabilities, context length, performance)
- Recommended model highlighting

**User Experience:**
- Comprehensive error handling with recovery options
- Consistent navigation patterns throughout the flow
- Professional terminal interface with ANSI formatting
- Loading indicators and status updates

### Test Results
- ✅ All TUI tests passing (26 tests, 0 failures)
- ✅ Project compiles successfully with no critical errors
- ✅ Code review completed with recommendations for future improvements

### Documentation Created
- ✅ Comprehensive tutorial in `tutorials/epic5/story5.3/README.md`
- ✅ Updated main tutorials index with new story link
- ✅ Architecture documentation and implementation details

### Quality Assurance
- Used test-automator for TDD test creation
- Used code-reviewer for quality assessment
- Used qa-expert validation (tests passing, documentation complete)
- All acceptance criteria verified and checked off

**Status**: ✅ COMPLETE - Ready for integration with broader Epic 5 objectives.