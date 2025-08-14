/**
 * API Key Validator JavaScript Module
 * 
 * Provides real-time validation for API keys with visual feedback
 * and format checking for different providers.
 */

class ApiKeyValidator {
  constructor() {
    this.validationTimeout = null;
    this.validationCache = new Map();
    this.setupEventListeners();
  }

  setupEventListeners() {
    // Listen for API key input events
    document.addEventListener('input', (event) => {
      if (event.target.matches('[data-api-key-input]')) {
        this.handleApiKeyInput(event);
      }
    });

    // Listen for form submissions
    document.addEventListener('submit', (event) => {
      if (event.target.matches('[data-api-key-form]')) {
        this.handleFormSubmit(event);
      }
    });
  }

  handleApiKeyInput(event) {
    const input = event.target;
    const provider = input.dataset.provider;
    const apiKey = input.value.trim();

    // Clear previous validation timeout
    if (this.validationTimeout) {
      clearTimeout(this.validationTimeout);
    }

    // Immediate format validation
    this.validateFormat(input, provider, apiKey);

    // Debounced remote validation
    if (apiKey.length > 0) {
      this.validationTimeout = setTimeout(() => {
        this.validateRemote(input, provider, apiKey);
      }, 1500); // 1.5 second debounce
    } else {
      this.clearValidationState(input);
    }
  }

  handleFormSubmit(event) {
    const form = event.target;
    const apiKeyInput = form.querySelector('[data-api-key-input]');
    
    if (apiKeyInput) {
      const provider = apiKeyInput.dataset.provider;
      const apiKey = apiKeyInput.value.trim();
      
      // Validate before submission
      if (!this.isValidFormat(provider, apiKey)) {
        event.preventDefault();
        this.showValidationError(apiKeyInput, 'Invalid API key format');
        return false;
      }
    }
  }

  validateFormat(input, provider, apiKey) {
    if (!apiKey) {
      this.clearValidationState(input);
      return;
    }

    if (this.isValidFormat(provider, apiKey)) {
      this.showValidationState(input, 'format-valid', 'Format looks correct');
    } else {
      this.showValidationState(input, 'format-invalid', this.getFormatHint(provider));
    }
  }

  async validateRemote(input, provider, apiKey) {
    // Check cache first
    const cacheKey = `${provider}:${apiKey}`;
    if (this.validationCache.has(cacheKey)) {
      const cached = this.validationCache.get(cacheKey);
      this.showValidationState(input, cached.state, cached.message);
      return;
    }

    this.showValidationState(input, 'validating', 'Validating API key...');

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
        const state = 'valid';
        const message = 'API key is valid';
        this.validationCache.set(cacheKey, { state, message });
        this.showValidationState(input, state, message);
      } else {
        const state = 'invalid';
        const message = result.error || 'API key is invalid';
        this.validationCache.set(cacheKey, { state, message });
        this.showValidationState(input, state, message);
      }
    } catch (error) {
      this.showValidationState(input, 'error', 'Unable to validate API key');
    }
  }

  isValidFormat(provider, apiKey) {
    switch (provider) {
      case 'anthropic':
        // Anthropic API keys start with "sk-ant-"
        return /^sk-ant-[a-zA-Z0-9_-]{95,}$/.test(apiKey);
      
      case 'openai':
        // OpenAI API keys start with "sk-"
        return /^sk-[a-zA-Z0-9]{48,}$/.test(apiKey);
      
      case 'google':
        // Google API keys are typically 39 characters
        return /^[a-zA-Z0-9_-]{39}$/.test(apiKey);
      
      default:
        // Generic validation - at least 20 characters
        return apiKey.length >= 20;
    }
  }

  getFormatHint(provider) {
    switch (provider) {
      case 'anthropic':
        return 'Claude API keys start with "sk-ant-" and are ~99 characters long';
      
      case 'openai':
        return 'OpenAI API keys start with "sk-" and are ~51 characters long';
      
      case 'google':
        return 'Google API keys are typically 39 characters long';
      
      default:
        return 'Please enter a valid API key';
    }
  }

  showValidationState(input, state, message) {
    const container = input.closest('[data-api-key-container]') || input.parentElement;
    
    // Remove existing validation classes
    input.classList.remove(
      'border-gray-300', 'border-green-300', 'border-red-300', 
      'border-yellow-300', 'border-blue-300'
    );
    
    // Add appropriate class based on state
    switch (state) {
      case 'format-valid':
        input.classList.add('border-blue-300');
        break;
      case 'valid':
        input.classList.add('border-green-300');
        break;
      case 'format-invalid':
      case 'invalid':
        input.classList.add('border-red-300');
        break;
      case 'validating':
        input.classList.add('border-yellow-300');
        break;
      case 'error':
        input.classList.add('border-red-300');
        break;
      default:
        input.classList.add('border-gray-300');
    }

    // Update or create validation message
    this.updateValidationMessage(container, state, message);
    
    // Update loading indicator
    this.updateLoadingIndicator(container, state === 'validating');
  }

  showValidationError(input, message) {
    this.showValidationState(input, 'invalid', message);
  }

  clearValidationState(input) {
    const container = input.closest('[data-api-key-container]') || input.parentElement;
    
    input.classList.remove(
      'border-green-300', 'border-red-300', 'border-yellow-300', 'border-blue-300'
    );
    input.classList.add('border-gray-300');
    
    this.updateValidationMessage(container, '', '');
    this.updateLoadingIndicator(container, false);
  }

  updateValidationMessage(container, state, message) {
    let messageEl = container.querySelector('[data-validation-message]');
    
    if (!messageEl && message) {
      messageEl = document.createElement('p');
      messageEl.setAttribute('data-validation-message', '');
      messageEl.className = 'mt-1 text-sm';
      container.appendChild(messageEl);
    }
    
    if (messageEl) {
      messageEl.textContent = message;
      
      // Update classes based on state
      messageEl.classList.remove(
        'text-gray-500', 'text-green-600', 'text-red-600', 
        'text-yellow-600', 'text-blue-600'
      );
      
      switch (state) {
        case 'format-valid':
          messageEl.classList.add('text-blue-600');
          break;
        case 'valid':
          messageEl.classList.add('text-green-600');
          break;
        case 'format-invalid':
        case 'invalid':
        case 'error':
          messageEl.classList.add('text-red-600');
          break;
        case 'validating':
          messageEl.classList.add('text-yellow-600');
          break;
        default:
          messageEl.classList.add('text-gray-500');
      }
      
      // Remove message if empty
      if (!message) {
        messageEl.remove();
      }
    }
  }

  updateLoadingIndicator(container, show) {
    let indicator = container.querySelector('[data-validation-loading]');
    
    if (show && !indicator) {
      indicator = document.createElement('div');
      indicator.setAttribute('data-validation-loading', '');
      indicator.className = 'absolute inset-y-0 right-0 flex items-center pr-3';
      indicator.innerHTML = '<div class="animate-spin rounded-full h-4 w-4 border-b-2 border-yellow-600"></div>';
      
      const inputWrapper = container.querySelector('.relative') || container;
      inputWrapper.appendChild(indicator);
    } else if (!show && indicator) {
      indicator.remove();
    }
  }

  getCSRFToken() {
    return document.querySelector("meta[name='csrf-token']").getAttribute("content");
  }

  // Clear cache periodically to prevent memory issues
  clearCache() {
    this.validationCache.clear();
  }
}

// Initialize API key validator when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  window.apiKeyValidator = new ApiKeyValidator();
  
  // Clear cache every 10 minutes
  setInterval(() => {
    if (window.apiKeyValidator) {
      window.apiKeyValidator.clearCache();
    }
  }, 10 * 60 * 1000);
});

export default ApiKeyValidator;