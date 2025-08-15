defmodule TheMaestroWeb.ProviderSelectionLive do
  @moduledoc """
  LiveView for provider and model selection with integrated authentication.

  This LiveView implements the multi-step flow for users to:
  1. Select their preferred LLM provider (Claude, Gemini, ChatGPT)
  2. Choose authentication method (OAuth or API Key)
  3. Complete authentication
  4. Select from available models
  5. Proceed to chat interface
  """
  use TheMaestroWeb, :live_view

  alias TheMaestro.Providers.Auth
  alias TheMaestro.Providers.Auth.{AnthropicAuth, GoogleAuth, OpenAIAuth, ProviderRegistry}
  alias TheMaestro.Providers.{Anthropic, Gemini, OpenAI}

  require Logger

  # Define the steps in our progressive flow
  @steps [:provider, :auth_method, :authenticate, :model, :ready]

  def mount(_params, session, socket) do
    current_user = Map.get(session, "current_user")
    authentication_enabled = authentication_enabled?()
    previous_selection = Map.get(session, "provider_selection")

    # Initialize the UI state
    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:authentication_enabled, authentication_enabled)
      |> assign(:current_step, :provider)
      |> assign(:steps, @steps)
      |> assign(:selected_provider, nil)
      |> assign(:available_providers, get_available_providers())
      |> assign(:selected_auth_method, nil)
      |> assign(:available_auth_methods, [])
      |> assign(:provider_status, %{})
      |> assign(:auth_credentials, nil)
      |> assign(:available_models, [])
      |> assign(:selected_model, nil)
      |> assign(:loading_models, false)
      |> assign(:error_message, nil)
      |> assign(:success_message, nil)
      |> assign(:oauth_url, nil)
      |> assign(:api_key_input, "")
      |> assign(:validating_api_key, false)
      |> assign(:previous_selection, previous_selection)

    # Check provider status
    socket = check_provider_status(socket)

    # Show previous selection if available
    socket =
      if previous_selection do
        assign(
          socket,
          :success_message,
          "Previous configuration: #{provider_display_name(previous_selection.provider)} with #{previous_selection.model}"
        )
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("select_provider", %{"provider" => provider_string}, socket) do
    provider = String.to_existing_atom(provider_string)

    # Get available auth methods for this provider
    auth_methods = ProviderRegistry.get_provider_methods(provider)

    socket =
      socket
      |> assign(:selected_provider, provider)
      |> assign(:available_auth_methods, auth_methods)
      |> assign(:current_step, :auth_method)
      |> assign(:error_message, nil)
      |> assign(:selected_auth_method, nil)
      |> assign(:auth_credentials, nil)

    {:noreply, socket}
  end

  def handle_event("select_auth_method", %{"method" => method_string}, socket) do
    method = String.to_existing_atom(method_string)

    socket =
      socket
      |> assign(:selected_auth_method, method)
      |> assign(:current_step, :authenticate)
      |> assign(:error_message, nil)

    {:noreply, socket}
  end

  def handle_event("initiate_oauth", _params, socket) do
    provider = socket.assigns.selected_provider

    case Auth.initiate_oauth_flow(provider, %{redirect_uri: get_oauth_redirect_uri()}) do
      {:ok, auth_url} ->
        socket =
          socket
          |> assign(:oauth_url, auth_url)
          |> assign(:error_message, nil)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:error_message, "Failed to initiate OAuth: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  def handle_event("validate_api_key", %{"api_key" => api_key}, socket) do
    if String.trim(api_key) == "" do
      {:noreply, assign(socket, :api_key_input, api_key)}
    else
      socket =
        socket
        |> assign(:api_key_input, api_key)
        |> assign(:validating_api_key, true)
        |> assign(:error_message, nil)

      # Validate the API key asynchronously
      send(self(), {:validate_api_key, api_key})

      {:noreply, socket}
    end
  end

  def handle_event("submit_api_key", %{"api_key" => api_key}, socket) do
    provider = socket.assigns.selected_provider

    socket =
      socket
      |> assign(:validating_api_key, true)
      |> assign(:error_message, nil)

    case Auth.authenticate(provider, :api_key, %{api_key: api_key}, "anonymous_user") do
      {:ok, credentials} ->
        socket =
          socket
          |> assign(:auth_credentials, credentials)
          |> assign(:validating_api_key, false)
          |> assign(:current_step, :model)
          |> assign(:loading_models, true)

        # Load models for this provider
        send(self(), {:load_models, provider, credentials})

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:validating_api_key, false)
          |> assign(:error_message, "Invalid API key: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  def handle_event("select_model", %{"model" => model}, socket) do
    socket =
      socket
      |> assign(:selected_model, model)
      |> assign(:current_step, :ready)
      |> assign(:success_message, "Setup complete! You can now start chatting.")

    {:noreply, socket}
  end

  def handle_event("start_chat", _params, socket) do
    # Store the selection in the session and redirect to chat
    provider = socket.assigns.selected_provider
    model = socket.assigns.selected_model
    credentials = socket.assigns.auth_credentials
    auth_method = socket.assigns.selected_auth_method

    # Store provider/model selection in session
    session_data = %{
      provider: provider,
      model: model,
      auth_method: auth_method,
      credentials: credentials,
      selected_at: DateTime.utc_now()
    }

    Logger.info("Starting chat with provider: #{provider}, model: #{model}")

    socket =
      socket
      |> assign(:session_data, session_data)
      |> put_flash(
        :info,
        "Successfully configured #{provider_display_name(provider)} with #{model}"
      )

    {:noreply, redirect(socket, to: ~p"/agent")}
  end

  def handle_event("go_back", _params, socket) do
    current_step = socket.assigns.current_step

    previous_step =
      case current_step do
        :auth_method -> :provider
        :authenticate -> :auth_method
        :model -> :authenticate
        :ready -> :model
        _ -> :provider
      end

    socket =
      socket
      |> assign(:current_step, previous_step)
      |> assign(:error_message, nil)
      |> assign(:success_message, nil)

    {:noreply, socket}
  end

  def handle_event("use_previous_selection", _params, socket) do
    case socket.assigns.previous_selection do
      nil ->
        socket = assign(socket, :error_message, "No previous selection found")
        {:noreply, socket}

      previous ->
        socket =
          socket
          |> assign(:selected_provider, previous.provider)
          |> assign(:selected_auth_method, previous.auth_method)
          |> assign(:auth_credentials, previous.credentials)
          |> assign(:selected_model, previous.model)
          |> assign(:current_step, :ready)
          |> assign(:error_message, nil)
          |> assign(:success_message, "Restored previous configuration")

        {:noreply, socket}
    end
  end

  def handle_event("reset_flow", _params, socket) do
    socket =
      socket
      |> assign(:current_step, :provider)
      |> assign(:selected_provider, nil)
      |> assign(:selected_auth_method, nil)
      |> assign(:auth_credentials, nil)
      |> assign(:available_models, [])
      |> assign(:selected_model, nil)
      |> assign(:error_message, nil)
      |> assign(:success_message, nil)
      |> assign(:oauth_url, nil)
      |> assign(:api_key_input, "")

    {:noreply, socket}
  end

  def handle_info({:validate_api_key, api_key}, socket) do
    # Basic API key validation - just check if it's not empty
    # More sophisticated validation would happen in the Auth module
    socket =
      if String.trim(api_key) != "" and String.length(api_key) > 10 do
        assign(socket, :validating_api_key, false)
      else
        socket
        |> assign(:validating_api_key, false)
        |> assign(:error_message, "Invalid API key format")
      end

    {:noreply, socket}
  end

  def handle_info({:load_models, provider, credentials}, socket) do
    case load_provider_models(provider, credentials) do
      {:ok, models} ->
        socket =
          socket
          |> assign(:available_models, models)
          |> assign(:loading_models, false)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:loading_models, false)
          |> assign(:error_message, "Failed to load models: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  # OAuth callback handling (from external window)
  def handle_info({:oauth_callback, code}, socket) do
    provider = socket.assigns.selected_provider

    # Use provider-specific auth exchange function
    result =
      case provider do
        :anthropic ->
          AnthropicAuth.exchange_oauth_code(:anthropic, code, %{
            redirect_uri: get_oauth_redirect_uri()
          })

        :google ->
          GoogleAuth.exchange_oauth_code(:google, code, %{redirect_uri: get_oauth_redirect_uri()})

        :openai ->
          OpenAIAuth.exchange_oauth_code(:openai, code, %{redirect_uri: get_oauth_redirect_uri()})

        _ ->
          {:error, :unsupported_provider}
      end

    case result do
      {:ok, credentials} ->
        socket =
          socket
          |> assign(:auth_credentials, credentials)
          |> assign(:current_step, :model)
          |> assign(:loading_models, true)
          |> assign(:oauth_url, nil)

        # Load models for this provider
        send(self(), {:load_models, provider, credentials})

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:error_message, "OAuth authentication failed: #{inspect(reason)}")
          |> assign(:oauth_url, nil)

        {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="mx-auto max-w-2xl px-4">
        <!-- Header -->
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Setup Your AI Assistant</h1>
          <p class="mt-2 text-gray-600">
            Choose your preferred LLM provider and authenticate to get started
          </p>
        </div>
        
    <!-- Progress indicator -->
        <div class="mb-8">
          <.progress_indicator current_step={@current_step} />
        </div>
        
    <!-- Flash messages -->
        <%= if @error_message do %>
          <div class="mb-4 rounded-md bg-red-50 p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <.icon name="hero-x-circle" class="h-5 w-5 text-red-400" />
              </div>
              <div class="ml-3">
                <p class="text-sm font-medium text-red-800">{@error_message}</p>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @success_message do %>
          <div class="mb-4 rounded-md bg-green-50 p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <.icon name="hero-check-circle" class="h-5 w-5 text-green-400" />
              </div>
              <div class="ml-3">
                <p class="text-sm font-medium text-green-800">{@success_message}</p>
              </div>
            </div>
          </div>
        <% end %>
        
    <!-- Main content card -->
        <div class="bg-white rounded-lg shadow-sm border p-6">
          <%= case @current_step do %>
            <% :provider -> %>
              <.provider_selection_step
                available_providers={@available_providers}
                provider_status={@provider_status}
              />
            <% :auth_method -> %>
              <.auth_method_selection_step
                selected_provider={@selected_provider}
                available_auth_methods={@available_auth_methods}
              />
            <% :authenticate -> %>
              <.authentication_step
                selected_provider={@selected_provider}
                selected_auth_method={@selected_auth_method}
                oauth_url={@oauth_url}
                api_key_input={@api_key_input}
                validating_api_key={@validating_api_key}
              />
            <% :model -> %>
              <.model_selection_step
                selected_provider={@selected_provider}
                available_models={@available_models}
                loading_models={@loading_models}
              />
            <% :ready -> %>
              <.ready_step selected_provider={@selected_provider} selected_model={@selected_model} />
          <% end %>
          
    <!-- Navigation buttons -->
          <div class="mt-6 flex justify-between">
            <%= if @current_step != :provider do %>
              <button
                phx-click="go_back"
                class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                <.icon name="hero-arrow-left" class="h-4 w-4 mr-2" /> Back
              </button>
            <% else %>
              <div></div>
            <% end %>

            <button
              phx-click="reset_flow"
              class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500"
            >
              <.icon name="hero-arrow-path" class="h-4 w-4 mr-2" /> Start Over
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Step component functions

  def progress_indicator(assigns) do
    ~H"""
    <nav aria-label="Progress">
      <ol class="flex items-center justify-center space-x-2">
        <%= for {step, index} <- Enum.with_index(@steps) do %>
          <li class={[
            "flex items-center",
            index < length(@steps) - 1 && "w-full"
          ]}>
            <div class={[
              "flex items-center justify-center w-8 h-8 rounded-full text-sm font-medium",
              case step_status(step, @current_step) do
                :completed -> "bg-blue-600 text-white"
                :current -> "bg-blue-100 text-blue-600 border-2 border-blue-600"
                :pending -> "bg-gray-100 text-gray-400"
              end
            ]}>
              {index + 1}
            </div>

            <%= if index < length(@steps) - 1 do %>
              <div class={[
                "flex-1 h-0.5 mx-2",
                case step_status(step, @current_step) do
                  :completed -> "bg-blue-600"
                  _ -> "bg-gray-200"
                end
              ]}>
              </div>
            <% end %>
          </li>
        <% end %>
      </ol>

      <div class="text-center mt-2">
        <span class="text-sm text-gray-600">{step_name(@current_step)}</span>
      </div>
    </nav>
    """
  end

  def provider_selection_step(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Choose Your AI Provider</h2>
      <p class="text-gray-600 mb-6">
        Select the AI provider you'd like to use for your conversations.
      </p>
      
    <!-- Previous Configuration Option -->
      <%= if @previous_selection do %>
        <div class="mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="text-sm font-medium text-blue-900">Previous Configuration</h3>
              <p class="text-sm text-blue-700">
                {provider_display_name(@previous_selection.provider)} • {String.slice(
                  @previous_selection.model,
                  0,
                  30
                )}
                <%= if String.length(@previous_selection.model) > 30 do %>
                  ...
                <% end %>
              </p>
            </div>
            <button
              phx-click="use_previous_selection"
              class="px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              Use Previous
            </button>
          </div>
        </div>
      <% end %>

      <div class="space-y-4">
        <%= for provider <- @available_providers do %>
          <div
            class={[
              "relative rounded-lg border-2 p-4 cursor-pointer transition-all duration-200",
              "hover:border-#{provider.color}-300 hover:bg-#{provider.color}-50",
              "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-#{provider.color}-500"
            ]}
            phx-click="select_provider"
            phx-value-provider={provider.id}
            tabindex="0"
            role="button"
            aria-label={"Select #{provider.name}"}
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-4">
                <!-- Provider Icon -->
                <div class={[
                  "flex-shrink-0 w-12 h-12 rounded-lg flex items-center justify-center text-2xl",
                  "bg-#{provider.color}-100"
                ]}>
                  {provider.icon}
                </div>
                
    <!-- Provider Info -->
                <div class="flex-1">
                  <div class="flex items-center space-x-2">
                    <h3 class="text-lg font-medium text-gray-900">{provider.name}</h3>
                    <.provider_status_badge status={Map.get(@provider_status, provider.id, :unknown)} />
                  </div>
                  <p class="text-sm text-gray-600 mt-1">{provider.description}</p>
                </div>
              </div>
              
    <!-- Selection Indicator -->
              <div class="flex-shrink-0">
                <.icon name="hero-chevron-right" class="h-5 w-5 text-gray-400" />
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def auth_method_selection_step(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Choose Authentication Method</h2>
      <p class="text-gray-600 mb-6">
        How would you like to authenticate with {@selected_provider |> provider_display_name()}?
      </p>

      <div class="space-y-4">
        <%= if :oauth in @available_auth_methods do %>
          <div
            class="relative rounded-lg border-2 border-gray-200 p-4 cursor-pointer hover:border-blue-300 hover:bg-blue-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-all duration-200"
            phx-click="select_auth_method"
            phx-value-method="oauth"
            tabindex="0"
            role="button"
            aria-label="Use OAuth authentication"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-4">
                <!-- OAuth Icon -->
                <div class="flex-shrink-0 w-12 h-12 rounded-lg bg-blue-100 flex items-center justify-center">
                  <.icon name="hero-shield-check" class="h-6 w-6 text-blue-600" />
                </div>
                
    <!-- OAuth Info -->
                <div class="flex-1">
                  <div class="flex items-center space-x-2">
                    <h3 class="text-lg font-medium text-gray-900">OAuth Authentication</h3>
                    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
                      Recommended
                    </span>
                  </div>
                  <p class="text-sm text-gray-600 mt-1">
                    Secure authentication through {@selected_provider |> provider_display_name()}'s official login flow.
                    No need to manage API keys.
                  </p>
                </div>
              </div>
              <div class="flex-shrink-0">
                <.icon name="hero-chevron-right" class="h-5 w-5 text-gray-400" />
              </div>
            </div>
          </div>
        <% end %>

        <%= if :api_key in @available_auth_methods do %>
          <div
            class="relative rounded-lg border-2 border-gray-200 p-4 cursor-pointer hover:border-orange-300 hover:bg-orange-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500 transition-all duration-200"
            phx-click="select_auth_method"
            phx-value-method="api_key"
            tabindex="0"
            role="button"
            aria-label="Use API key authentication"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-4">
                <div class="flex-shrink-0 w-12 h-12 rounded-lg bg-orange-100 flex items-center justify-center">
                  <.icon name="hero-key" class="h-6 w-6 text-orange-600" />
                </div>
                <div class="flex-1">
                  <div class="flex items-center space-x-2">
                    <h3 class="text-lg font-medium text-gray-900">API Key Authentication</h3>
                    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-orange-100 text-orange-800">
                      Alternative
                    </span>
                  </div>
                  <p class="text-sm text-gray-600 mt-1">
                    Use your {@selected_provider |> provider_display_name()} API key.
                  </p>
                </div>
              </div>
              <div class="flex-shrink-0">
                <.icon name="hero-chevron-right" class="h-5 w-5 text-gray-400" />
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def authentication_step(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Authenticate</h2>

      <%= case @selected_auth_method do %>
        <% :oauth -> %>
          <div class="text-center">
            <p class="text-gray-600 mb-6">
              Click the button below to authenticate with {@selected_provider
              |> provider_display_name()}.
              This will open a new window for secure authentication.
            </p>

            <%= if @oauth_url do %>
              <div class="space-y-4">
                <a
                  href={@oauth_url}
                  target="_blank"
                  class="inline-flex items-center px-6 py-3 border border-transparent text-base font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="h-5 w-5 mr-2" />
                  Authenticate with {@selected_provider |> provider_display_name()}
                </a>
                <p class="text-sm text-gray-500">
                  After completing authentication, this page will automatically update.
                </p>
              </div>
            <% else %>
              <button
                phx-click="initiate_oauth"
                class="inline-flex items-center px-6 py-3 border border-transparent text-base font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                <.icon name="hero-shield-check" class="h-5 w-5 mr-2" /> Start OAuth Authentication
              </button>
            <% end %>
          </div>
        <% :api_key -> %>
          <form phx-submit="submit_api_key" class="space-y-4">
            <div>
              <label for="api_key" class="block text-sm font-medium text-gray-700 mb-2">
                {@selected_provider |> provider_display_name()} API Key
              </label>
              <div class="relative">
                <input
                  type="password"
                  name="api_key"
                  id="api_key"
                  value={@api_key_input}
                  phx-change="validate_api_key"
                  placeholder="Enter your API key..."
                  class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                  required
                />
                <%= if @validating_api_key do %>
                  <div class="absolute inset-y-0 right-0 flex items-center pr-3">
                    <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600"></div>
                  </div>
                <% end %>
              </div>
              <p class="mt-2 text-sm text-gray-500">
                Get your API key from {@selected_provider |> provider_display_name()}'s dashboard.
                It will be stored securely in your session.
              </p>
            </div>

            <button
              type="submit"
              disabled={@validating_api_key || String.trim(@api_key_input) == ""}
              class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <%= if @validating_api_key do %>
                <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2"></div>
                Validating...
              <% else %>
                Authenticate with API Key
              <% end %>
            </button>
          </form>
      <% end %>
    </div>
    """
  end

  def model_selection_step(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Choose Your Model</h2>
      <p class="text-gray-600 mb-6">
        Select the specific AI model you'd like to use with {@selected_provider
        |> provider_display_name()}.
      </p>

      <%= if @loading_models do %>
        <div class="text-center py-8">
          <div class="inline-flex items-center space-x-2">
            <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600"></div>
            <span class="text-gray-600">Loading available models...</span>
          </div>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for model <- @available_models do %>
            <div
              class="relative rounded-lg border-2 border-gray-200 p-4 cursor-pointer hover:border-blue-300 hover:bg-blue-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-all duration-200"
              phx-click="select_model"
              phx-value-model={model.id}
              tabindex="0"
              role="button"
              aria-label={"Select #{model.name}"}
            >
              <div class="flex items-center justify-between">
                <div class="flex items-center space-x-4">
                  <div class="flex-shrink-0 w-12 h-12 rounded-lg bg-blue-100 flex items-center justify-center">
                    <.icon name="hero-cpu-chip" class="h-6 w-6 text-blue-600" />
                  </div>
                  <div class="flex-1">
                    <h3 class="text-lg font-medium text-gray-900">{model.name}</h3>
                    <p class="text-sm text-gray-600 mt-1">{model.description}</p>
                  </div>
                </div>
                <div class="flex-shrink-0">
                  <.icon name="hero-chevron-right" class="h-5 w-5 text-gray-400" />
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  def ready_step(assigns) do
    ~H"""
    <div class="text-center">
      <div class="mx-auto flex items-center justify-center h-16 w-16 rounded-full bg-green-100 mb-4">
        <.icon name="hero-check" class="h-8 w-8 text-green-600" />
      </div>

      <h2 class="text-xl font-semibold text-gray-900 mb-4">Setup Complete!</h2>
      <p class="text-gray-600 mb-6">
        You're all set to start chatting with {@selected_model} from {@selected_provider
        |> provider_display_name()}.
      </p>

      <button
        phx-click="start_chat"
        class="inline-flex items-center px-6 py-3 border border-transparent text-base font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
      >
        <.icon name="hero-chat-bubble-left-ellipsis" class="h-5 w-5 mr-2" /> Start Chatting
      </button>
    </div>
    """
  end

  def provider_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-1 rounded-full text-xs font-medium",
      case @status do
        :available -> "bg-green-100 text-green-800"
        :unavailable -> "bg-red-100 text-red-800"
        :degraded -> "bg-yellow-100 text-yellow-800"
        _ -> "bg-gray-100 text-gray-800"
      end
    ]}>
      <span class={[
        "w-1.5 h-1.5 rounded-full mr-1",
        case @status do
          :available -> "bg-green-400"
          :unavailable -> "bg-red-400"
          :degraded -> "bg-yellow-400"
          _ -> "bg-gray-400"
        end
      ]}>
      </span>
      {status_text(@status)}
    </span>
    """
  end

  # Private functions

  @steps [:provider, :auth_method, :authenticate, :model, :ready]

  defp step_status(step, current_step) do
    current_index = Enum.find_index(@steps, &(&1 == current_step))
    step_index = Enum.find_index(@steps, &(&1 == step))

    cond do
      step_index < current_index -> :completed
      step_index == current_index -> :current
      true -> :pending
    end
  end

  defp step_name(:provider), do: "Choose Provider"
  defp step_name(:auth_method), do: "Select Authentication"
  defp step_name(:authenticate), do: "Authenticate"
  defp step_name(:model), do: "Choose Model"
  defp step_name(:ready), do: "Ready to Chat"

  defp status_text(:available), do: "Available"
  defp status_text(:unavailable), do: "Unavailable"
  defp status_text(:degraded), do: "Issues"
  defp status_text(_), do: "Unknown"

  defp authentication_enabled? do
    Application.get_env(:the_maestro, :require_authentication, true)
  end

  defp get_available_providers do
    ProviderRegistry.list_providers()
    |> Enum.map(fn provider ->
      %{
        id: provider,
        name: provider_display_name(provider),
        description: provider_description(provider),
        icon: provider_icon(provider),
        color: provider_color(provider)
      }
    end)
  end

  defp provider_display_name(:anthropic), do: "Claude (Anthropic)"
  defp provider_display_name(:google), do: "Gemini (Google)"
  defp provider_display_name(:openai), do: "ChatGPT (OpenAI)"
  defp provider_display_name(provider), do: to_string(provider)

  defp provider_description(:anthropic), do: "Advanced reasoning and analysis with Claude AI"
  defp provider_description(:google), do: "Google's multimodal AI with Gemini models"
  defp provider_description(:openai), do: "Conversational AI with GPT models"
  defp provider_description(_), do: "AI Language Model"

  defp provider_icon(:anthropic), do: "🤖"
  defp provider_icon(:google), do: "🔍"
  defp provider_icon(:openai), do: "💬"
  defp provider_icon(_), do: "🤖"

  defp provider_color(:anthropic), do: "orange"
  defp provider_color(:google), do: "blue"
  defp provider_color(:openai), do: "green"
  defp provider_color(_), do: "gray"

  defp check_provider_status(socket) do
    status =
      socket.assigns.available_providers
      |> Enum.reduce(%{}, fn provider_info, acc ->
        status = get_provider_connection_status(provider_info.id)
        Map.put(acc, provider_info.id, status)
      end)

    assign(socket, :provider_status, status)
  end

  defp get_provider_connection_status(_provider) do
    # This would typically ping the provider's API to check availability
    # For now, we'll assume all providers are available
    :available
  end

  defp get_oauth_redirect_uri do
    "http://localhost:4000/oauth2callback"
  end

  defp load_provider_models(provider, credentials) do
    # Create auth context from credentials
    auth_context = %{
      type: credentials.auth_method,
      credentials: credentials.credentials,
      config: %{provider: provider}
    }

    # Call the provider's list_models function
    case provider do
      :anthropic ->
        Anthropic.list_models(auth_context)

      :google ->
        Gemini.list_models(auth_context)

      :openai ->
        OpenAI.list_models(auth_context)

      _ ->
        {:error, :unsupported_provider}
    end
  end
end
