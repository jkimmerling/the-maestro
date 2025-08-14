/**
 * Provider Authentication JavaScript Module
 * 
 * Handles OAuth popup windows and real-time API key validation
 * for the provider selection interface.
 */

class ProviderAuth {
  constructor() {
    this.oauthWindow = null;
    this.oauthCheckInterval = null;
    this.apiKeyValidationTimeout = null;
    this.liveSocket = window.liveSocket;
    
    this.setupEventListeners();
  }

  setupEventListeners() {
    // Listen for OAuth initiation events from LiveView
    document.addEventListener('phx:oauth-popup', (event) => {
      this.openOAuthPopup(event.detail);
    });

    // Listen for API key validation events
    document.addEventListener('phx:validate-api-key', (event) => {
      this.validateApiKey(event.detail);
    });

    // Listen for cleanup events
    document.addEventListener('phx:cleanup-oauth', () => {
      this.cleanupOAuth();
    });
  }

  /**
   * Opens OAuth popup window and monitors for completion
   */
  openOAuthPopup({ url, provider }) {
    if (this.oauthWindow && !this.oauthWindow.closed) {
      this.oauthWindow.close();
    }

    // Calculate centered popup position
    const width = 600;
    const height = 700;
    const left = (screen.width / 2) - (width / 2);
    const top = (screen.height / 2) - (height / 2);

    // Open popup window
    this.oauthWindow = window.open(
      url,
      `oauth_${provider}`,
      `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes`
    );

    if (!this.oauthWindow) {
      this.liveSocket.pushEvent('oauth-error', {
        error: 'popup_blocked',
        message: 'Popup window was blocked by browser'
      });
      return;
    }

    // Monitor popup for completion
    this.monitorOAuthPopup(provider);
  }

  /**
   * Monitors OAuth popup window for completion or closure
   */
  monitorOAuthPopup(provider) {
    this.oauthCheckInterval = setInterval(() => {
      if (this.oauthWindow.closed) {
        clearInterval(this.oauthCheckInterval);
        this.liveSocket.pushEvent('oauth-cancelled', { provider });
        return;
      }

      try {
        // Check if popup has navigated to callback URL
        const popupUrl = this.oauthWindow.location.href;
        if (popupUrl.includes('/oauth2callback')) {
          const urlParams = new URLSearchParams(this.oauthWindow.location.search);
          const code = urlParams.get('code');
          const error = urlParams.get('error');

          if (code) {
            this.liveSocket.pushEvent('oauth-success', { 
              provider, 
              code,
              state: urlParams.get('state')
            });
          } else if (error) {
            this.liveSocket.pushEvent('oauth-error', {
              provider,
              error,
              error_description: urlParams.get('error_description')
            });
          }

          this.cleanupOAuth();
        }
      } catch (e) {
        // Cross-origin error is expected while on provider's domain
        // We'll continue monitoring until popup closes or returns to our domain
      }
    }, 1000);
  }

  /**
   * Validates API key in real-time using provider API
   */
  validateApiKey({ provider, apiKey, immediate = false }) {
    // Clear any existing validation timeout
    if (this.apiKeyValidationTimeout) {
      clearTimeout(this.apiKeyValidationTimeout);
    }

    // For immediate validation (on submit), validate right away
    if (immediate) {
      this.performApiKeyValidation(provider, apiKey);
      return;
    }

    // For real-time validation, debounce the requests
    this.apiKeyValidationTimeout = setTimeout(() => {
      this.performApiKeyValidation(provider, apiKey);
    }, 1000); // 1 second debounce
  }

  /**
   * Performs the actual API key validation request
   */
  async performApiKeyValidation(provider, apiKey) {
    if (!apiKey || apiKey.trim().length === 0) {
      return;
    }

    try {
      const response = await fetch(`/api/providers/${provider}/test`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({
          credentials: { api_key: apiKey }
        })
      });

      const result = await response.json();

      if (response.ok && result.status === 'success') {
        this.liveSocket.pushEvent('api-key-valid', {
          provider,
          result: result.result
        });
      } else {
        this.liveSocket.pushEvent('api-key-invalid', {
          provider,
          error: result.error || 'Invalid API key'
        });
      }
    } catch (error) {
      this.liveSocket.pushEvent('api-key-error', {
        provider,
        error: 'Network error during validation'
      });
    }
  }

  /**
   * Tests provider connection with current credentials
   */
  async testConnection(provider) {
    try {
      const response = await fetch(`/api/providers/${provider}/test`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        }
      });

      const result = await response.json();
      
      this.liveSocket.pushEvent('connection-test-result', {
        provider,
        status: result.status,
        result: result.result || result.error
      });
    } catch (error) {
      this.liveSocket.pushEvent('connection-test-result', {
        provider,
        status: 'error',
        result: 'Network error'
      });
    }
  }

  /**
   * Fetches available models for a provider
   */
  async fetchModels(provider) {
    try {
      const response = await fetch(`/api/providers/${provider}/models`, {
        method: 'GET',
        headers: {
          'X-CSRF-Token': this.getCSRFToken()
        }
      });

      const result = await response.json();

      if (response.ok && result.models) {
        this.liveSocket.pushEvent('models-loaded', {
          provider,
          models: result.models
        });
      } else {
        this.liveSocket.pushEvent('models-error', {
          provider,
          error: result.error || 'Failed to load models'
        });
      }
    } catch (error) {
      this.liveSocket.pushEvent('models-error', {
        provider,
        error: 'Network error while loading models'
      });
    }
  }

  /**
   * Cleans up OAuth-related resources
   */
  cleanupOAuth() {
    if (this.oauthWindow && !this.oauthWindow.closed) {
      this.oauthWindow.close();
    }
    this.oauthWindow = null;

    if (this.oauthCheckInterval) {
      clearInterval(this.oauthCheckInterval);
      this.oauthCheckInterval = null;
    }
  }

  /**
   * Gets CSRF token for API requests
   */
  getCSRFToken() {
    return document.querySelector("meta[name='csrf-token']").getAttribute("content");
  }

  /**
   * Cleanup when page unloads
   */
  destroy() {
    this.cleanupOAuth();
    
    if (this.apiKeyValidationTimeout) {
      clearTimeout(this.apiKeyValidationTimeout);
    }
  }
}

// Initialize provider auth when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  window.providerAuth = new ProviderAuth();
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
  if (window.providerAuth) {
    window.providerAuth.destroy();
  }
});

// Expose for manual usage if needed
export default ProviderAuth;