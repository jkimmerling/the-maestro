# Story 5.2: UI Model Selection Interface

## User Story
**As a** Web User,  
**I want** to select my preferred LLM provider and model through an intuitive web interface with integrated authentication,  
**so that** I can seamlessly set up my agent with my chosen AI provider before starting conversations.

## Acceptance Criteria

### Provider Selection UI
1. **Provider Dropdown**: Implement provider selection dropdown with:
   - Claude (Anthropic)
   - Gemini (Google)  
   - ChatGPT (OpenAI)
   - Clear provider descriptions and capabilities
2. **Visual Provider Identity**: Each provider shows distinctive branding/icons
3. **Provider Status Indication**: Show availability/connection status for each provider

### Authentication Flow UI
4. **Authentication Method Selection**: For each provider, present authentication options:
   - OAuth button (primary)
   - API Key input field (alternative)
   - Clear explanation of each method
5. **OAuth Integration**: Seamless OAuth flow that:
   - Opens provider authorization in new tab/window
   - Handles callback gracefully
   - Shows authentication progress
   - Displays success/error states
6. **API Key Handling**: Secure API key input with:
   - Masked input field
   - Validation feedback
   - Test connection capability
   - Secure storage confirmation

### Model Selection UI  
7. **Dynamic Model Loading**: After authentication, fetch and display available models:
   - API call to provider to get model list
   - Loading state while fetching models
   - Error handling for model fetch failures
8. **Model Selection Interface**: Present models with:
   - Model names and descriptions
   - Capability indicators (context length, multimodal support)
   - Recommended models highlighted
   - Performance/cost indicators where available

### User Experience Flow
9. **Progressive Disclosure**: Step-by-step flow:
   ```
   Select Provider → Choose Auth Method → Authenticate → Select Model → Chat Ready
   ```
10. **State Persistence**: Maintain selection state across page refreshes
11. **Back Navigation**: Allow users to change selections without losing progress
12. **Skip Option**: For returning users, quick access to previous selections

### Chat Interface Integration
13. **Model Context Display**: Show selected provider and model in chat interface
14. **Switch Model Option**: Easy access to change model without full re-authentication
15. **Connection Status**: Real-time connection status to selected provider

### Error Handling & Recovery
16. **Authentication Failures**: Clear error messages and recovery options for:
    - Invalid API keys
    - OAuth failures
    - Network connectivity issues
    - Provider service outages
17. **Model Loading Failures**: Graceful handling when model list fails to load
18. **Session Recovery**: Restore previous selections when possible

## Technical Implementation

### LiveView Components
```elixir
# New LiveView components
lib/the_maestro_web/live/
├── provider_selection_live.ex    # Main provider/model selection flow
├── auth_flow_live.ex            # Authentication handling
└── components/
    ├── provider_selector.ex     # Provider dropdown component
    ├── auth_method_selector.ex  # OAuth/API key selection
    ├── model_selector.ex        # Dynamic model selection
    └── connection_status.ex     # Provider connection status
```

### Frontend JavaScript
```javascript
// assets/js/
├── provider_auth.js        # OAuth popup/callback handling
├── api_key_validator.js    # Real-time API key validation
└── model_fetcher.js        # Dynamic model loading
```

### API Endpoints
19. **Provider Endpoints**: New API routes for:
    - `GET /api/providers` - List available providers
    - `POST /api/providers/:provider/auth` - Initiate authentication
    - `GET /api/providers/:provider/models` - Get available models
    - `POST /api/providers/:provider/test` - Test connection

### Integration with Existing Auth
20. **Session Extension**: Extend existing session management to include:
    - Selected provider
    - Authentication method
    - Model selection
    - Provider-specific credentials
21. **User Preferences**: Store user provider/model preferences for future sessions

## UI/UX Design Requirements

### Visual Design
- Clean, modern interface following existing design system
- Responsive design for desktop and mobile
- Accessible components (WCAG AA compliance)
- Loading states and smooth transitions

### Provider Branding
- Appropriate use of provider colors/logos (respecting brand guidelines)
- Clear visual distinction between providers
- Professional, trustworthy appearance

### Progressive Enhancement
- Works without JavaScript (basic functionality)
- Enhanced experience with JavaScript enabled
- Mobile-optimized touch interactions

## Dependencies
- Story 5.1 (Multi-Provider Authentication Architecture)
- Existing Phoenix LiveView infrastructure from Epic 2
- Provider implementations from Epic 3

## Definition of Done
- [ ] Provider selection dropdown implemented and functional
- [ ] OAuth authentication flow working for all providers
- [ ] API key authentication option available and secure
- [ ] Dynamic model fetching and selection operational
- [ ] Progressive UI flow provides smooth user experience
- [ ] Integration with chat interface completed
- [ ] Error handling and recovery mechanisms implemented
- [ ] Mobile responsive design verified
- [ ] Accessibility standards met (WCAG AA)
- [ ] Session persistence working correctly
- [ ] Integration tests covering full flow
- [ ] Tutorial created in `tutorials/epic5/story5.2/`