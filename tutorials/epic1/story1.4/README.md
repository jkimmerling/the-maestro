# Story 1.4: LLMProvider Behaviour & Gemini Adapter with OAuth

This tutorial teaches an intermediate Elixir developer how to build a model-agnostic LLM provider system with comprehensive OAuth authentication, following the pattern implemented in Epic 1, Story 1.4 of The Maestro project.

## Overview

In this story, we implemented a flexible abstraction layer for Large Language Model providers that supports multiple authentication methods. This allows our agent system to work with different LLM providers (Gemini, OpenAI, Anthropic) through a standardized interface while providing robust authentication options including OAuth2 flows.

## Key Learning Objectives

- Understand the Behaviour pattern for creating extensible interfaces in Elixir
- Learn how to implement OAuth2 flows in Elixir applications
- Explore secure credential storage and management patterns
- See how to integrate external HTTP APIs with proper error handling
- Understand how to update GenServer state to work with external services

## Architecture Overview

Our implementation consists of three main components:

1. **LLMProvider Behaviour** - A contract defining the interface all providers must implement
2. **Gemini Provider Implementation** - A concrete implementation for Google's Gemini API
3. **Enhanced Agent GenServer** - Updated to work with the provider abstraction

## Step 1: Defining the LLMProvider Behaviour

Behaviours in Elixir are similar to interfaces in other languages. They define a contract that modules must implement, ensuring consistency across different implementations.

```elixir
defmodule TheMaestro.Providers.LLMProvider do
  @moduledoc """
  Behaviour for LLM (Large Language Model) providers.
  """

  @type auth_context :: %{
          type: :api_key | :oauth | :service_account,
          credentials: map(),
          config: map()
        }

  @callback initialize_auth(config :: map()) :: {:ok, auth_context()} | {:error, term()}
  @callback complete_text(auth_context(), [message()], completion_opts()) ::
              {:ok, completion_response()} | {:error, term()}
  # ... other callbacks
end
```

**Key Design Decisions:**

- **Tagged tuples**: We use `{:ok, result}` and `{:error, reason}` patterns for clear error handling
- **Flexible auth_context**: The authentication context can handle different auth types (API keys, OAuth, service accounts)
- **Structured options**: We define clear types for completion options and responses

## Step 2: OAuth2 Implementation Strategy

OAuth2 implementation requires careful handling of multiple flows and security considerations. Our Gemini provider supports three authentication methods:

### API Key Authentication (Simplest)
```elixir
defp get_api_key do
  System.get_env("GEMINI_API_KEY")
end
```

### OAuth2 Device Authorization Flow (CLI-friendly)
```elixir
def device_authorization_flow(config \\ %{}) do
  state = generate_state()
  code_verifier = generate_code_verifier()
  code_challenge = generate_code_challenge(code_verifier)

  auth_url = build_device_auth_url(state, code_challenge)
  
  {:ok, %{
    auth_url: auth_url,
    state: state,
    code_verifier: code_verifier,
    polling_fn: &prompt_for_authorization_code/0
  }}
end
```

### OAuth2 Web Flow (Browser-based)
```elixir
def web_authorization_flow(config \\ %{}) do
  port = get_available_port_number()
  redirect_uri = String.replace(@oauth_redirect_uri_pattern, "%d", Integer.to_string(port))
  state = generate_state()

  auth_url = build_web_auth_url(redirect_uri, state)
  server_pid = start_callback_server(port, state, redirect_uri)

  {:ok, %{
    auth_url: auth_url,
    server_pid: server_pid,
    port: port
  }}
end
```

**Security Considerations:**

- **PKCE (Proof Key for Code Exchange)**: We generate code verifiers and challenges to prevent code interception attacks
- **State parameter**: Random state prevents CSRF attacks
- **Secure token storage**: Credentials are stored with restricted file permissions (600)
- **Token validation**: We validate tokens before use and refresh when expired

## Step 3: Credential Caching and Refresh Logic

One of the most complex parts of OAuth implementation is handling credential persistence and refresh:

```elixir
defp load_cached_oauth_credentials do
  credential_path = get_credential_path()
  
  case File.read(credential_path) do
    {:ok, content} ->
      case Jason.decode(content) do
        {:ok, credentials} ->
          {:ok, atomize_keys(credentials)}
        {:error, reason} ->
          {:error, {:invalid_credential_format, reason}}
      end

    {:error, :enoent} ->
      {:error, :no_cached_credentials}

    {:error, reason} ->
      {:error, {:failed_to_read_credentials, reason}}
  end
end

defp cache_oauth_credentials(credentials) do
  credential_path = get_credential_path()
  credential_dir = Path.dirname(credential_path)
  
  case File.mkdir_p(credential_dir) do
    :ok ->
      content = Jason.encode!(credentials, pretty: true)
      case File.write(credential_path, content, [:write]) do
        :ok ->
          # Set restrictive permissions (equivalent to chmod 600)
          File.chmod(credential_path, 0o600)
          {:ok, credentials}
        {:error, reason} ->
          {:error, {:failed_to_cache_credentials, reason}}
      end
    {:error, reason} ->
      {:error, {:failed_to_create_credential_dir, reason}}
  end
end
```

**Important Pattern**: Notice how we handle each error case explicitly and provide meaningful error tuples. This makes debugging much easier.

## Step 4: HTTP Client Integration

We use HTTPoison for HTTP requests to the Gemini API. The key is handling different authentication methods in the request headers:

```elixir
defp make_gemini_request(token, model, request_body) do
  url = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent"
  
  headers = case String.starts_with?(token, "AIza") do
    true ->
      # API Key authentication
      [{"content-type", "application/json"}]
    
    false ->
      # OAuth or Service Account token
      [
        {"authorization", "Bearer #{token}"},
        {"content-type", "application/json"}
      ]
  end

  final_url = case String.starts_with?(token, "AIza") do
    true -> "#{url}?key=#{token}"
    false -> url
  end

  case HTTPoison.post(final_url, Jason.encode!(request_body), headers) do
    {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
      Jason.decode(response_body)

    {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
      {:error, {:gemini_request_failed, status, response_body}}

    {:error, reason} ->
      {:error, {:request_failed, reason}}
  end
end
```

## Step 5: Integrating with GenServer State

The Agent GenServer needed updates to work with the new provider system:

```elixir
defstruct [:agent_id, :message_history, :loop_state, :created_at, :llm_provider, :auth_context]

def init(%{agent_id: agent_id, llm_provider: llm_provider, auth_context: auth_context}) do
  # Initialize authentication if auth_context is nil
  final_auth_context = case auth_context do
    nil ->
      case llm_provider.initialize_auth() do
        {:ok, context} -> context
        {:error, reason} -> 
          Logger.warning("Failed to initialize LLM auth: #{inspect(reason)}")
          nil
      end
    context -> context
  end

  state = %__MODULE__{
    agent_id: agent_id,
    message_history: [],
    loop_state: :idle,
    created_at: DateTime.utc_now(),
    llm_provider: llm_provider,
    auth_context: final_auth_context
  }

  {:ok, state}
end
```

**Key Pattern**: We handle authentication initialization gracefully - if it fails, we don't crash the GenServer but instead log a warning and let the error surface during actual message processing.

## Step 6: Message Processing with LLM Integration

The message handling now integrates with the LLM provider:

```elixir
def handle_call({:send_message, message}, _from, state) do
  # Add user message to history
  user_message = %{
    type: :user,
    role: :user,
    content: message,
    timestamp: DateTime.utc_now()
  }

  # Update state to thinking mode
  thinking_state = %{state | 
    message_history: state.message_history ++ [user_message],
    loop_state: :thinking
  }

  # Attempt to get response from LLM provider
  case get_llm_response(thinking_state, message) do
    {:ok, llm_response} ->
      assistant_message = %{
        type: :assistant,
        role: :assistant,
        content: llm_response,
        timestamp: DateTime.utc_now()
      }

      final_state = %{thinking_state | 
        message_history: thinking_state.message_history ++ [assistant_message],
        loop_state: :idle
      }

      {:reply, {:ok, assistant_message}, final_state}

    {:error, reason} ->
      # Handle errors gracefully
      error_message = %{
        type: :assistant,
        role: :assistant,
        content: "I'm sorry, I encountered an error processing your request.",
        timestamp: DateTime.utc_now()
      }

      error_state = %{thinking_state | 
        message_history: thinking_state.message_history ++ [error_message],
        loop_state: :idle
      }

      {:reply, {:ok, error_message}, error_state}
  end
end
```

## Step 7: Dependencies and Mix Configuration

Don't forget to add the necessary dependencies to your `mix.exs`:

```elixir
defp deps do
  [
    # ... existing deps
    {:gemini_ex, "~> 0.2"},
    {:goth, "~> 1.3"},
    {:httpoison, "~> 2.0"}
  ]
end
```

## Testing Your Implementation

Here's a simple way to test your provider:

```elixir
# In IEx
{:ok, auth_context} = TheMaestro.Providers.Gemini.initialize_auth()

messages = [%{role: :user, content: "Hello, how are you?"}]
opts = %{model: "gemini-1.5-pro", temperature: 0.7}

{:ok, response} = TheMaestro.Providers.Gemini.complete_text(auth_context, messages, opts)
IO.puts(response.content)
```

## Security Best Practices Implemented

1. **Credential Storage**: OAuth tokens are stored in `~/.maestro/oauth_creds.json` with 600 permissions
2. **Token Validation**: We validate tokens before use and refresh when expired
3. **State Parameter**: CSRF protection in OAuth flows
4. **PKCE**: Code challenge/verifier for authorization code interception protection
5. **Error Handling**: No credential information is logged in error messages

## Comparison with Original gemini-cli

Our implementation maintains compatibility with the original gemini-cli by:
- Using the same OAuth client ID and secret
- Supporting the same OAuth scopes
- Implementing the same device authorization flow
- Using the same credential storage location pattern

## Next Steps

With this foundation, you can easily:
- Add other LLM providers (OpenAI, Anthropic) by implementing the same behaviour
- Extend the authentication methods (e.g., add Azure AD support)
- Add tool-calling capabilities to your agents
- Implement more sophisticated error recovery and retry logic

## Key Takeaways

1. **Behaviours** provide a clean way to create extensible systems in Elixir
2. **OAuth2 flows** require careful attention to security details like PKCE and state parameters
3. **Error handling** in Elixir should be explicit and informative using tagged tuples
4. **GenServer integration** with external services requires thoughtful state management
5. **Security** considerations must be built in from the start, not added as an afterthought

This implementation demonstrates how Elixir's strengths (pattern matching, behaviours, supervision trees) can be leveraged to build robust, secure, and extensible systems for AI agent applications.