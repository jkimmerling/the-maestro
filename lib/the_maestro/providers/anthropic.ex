defmodule TheMaestro.Providers.Anthropic do
  @moduledoc """
  Anthropic (Claude) LLM Provider implementation with comprehensive OAuth authentication support.

  This module implements the LLMProvider behaviour for Anthropic's API,
  supporting multiple authentication methods:
  - API Key authentication via ANTHROPIC_API_KEY environment variable
  - OAuth2 authentication with device authorization flow and web-based flow
  - User-delegated OAuth tokens for enterprise use cases

  The OAuth implementation follows similar patterns to the Gemini provider,
  including credential caching, token refresh, and proper security practices.
  """

  @behaviour TheMaestro.Providers.LLMProvider

  alias TheMaestro.Providers.LLMProvider

  require Logger

  # OAuth Configuration for Anthropic
  @oauth_client_id System.get_env("ANTHROPIC_OAUTH_CLIENT_ID") || "anthropic-client-id"
  @oauth_client_secret System.get_env("ANTHROPIC_OAUTH_CLIENT_SECRET") ||
                         "anthropic-client-secret"
  @oauth_scopes ["api"]
  @phoenix_redirect_uri "http://localhost:4000/oauth2callback/anthropic"

  # File paths for credential storage
  @maestro_dir ".maestro"
  @oauth_creds_file "anthropic_oauth_creds.json"

  @impl LLMProvider
  def initialize_auth(config \\ %{}) do
    case detect_auth_method(config) do
      {:api_key, api_key} ->
        create_api_key_auth_context(api_key, config)

      {:oauth, :cached} ->
        initialize_cached_oauth(config)

      {:oauth, :new} ->
        # In non-interactive mode or tests, return an error instead of starting OAuth flow
        {:error, :oauth_initialization_required}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl LLMProvider
  def complete_text(auth_context, messages, opts \\ %{}) do
    case validate_auth_context(auth_context) do
      :ok ->
        with {:ok, validated_messages} <- validate_messages(messages),
             {:ok, client} <- create_anthropic_client(auth_context) do
          model = Map.get(opts, :model, "claude-3-sonnet-20240229")
          temperature = Map.get(opts, :temperature, 0.7)
          max_tokens = Map.get(opts, :max_tokens, 2048)

          anthropic_messages = convert_messages_to_anthropic(validated_messages)

          request_params = %{
            model: model,
            messages: anthropic_messages,
            temperature: temperature,
            max_tokens: max_tokens
          }

          case make_anthropic_request(client, request_params) do
            {:ok, response} ->
              {:ok, build_text_response(response, model)}

            {:error, reason} ->
              {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl LLMProvider
  def complete_with_tools(auth_context, messages, opts \\ %{}) do
    case validate_auth_context(auth_context) do
      :ok ->
        with {:ok, validated_messages} <- validate_messages(messages),
             {:ok, client} <- create_anthropic_client(auth_context) do
          tools = Map.get(opts, :tools, [])
          model = Map.get(opts, :model, "claude-3-sonnet-20240229")
          temperature = Map.get(opts, :temperature, 0.0)
          max_tokens = Map.get(opts, :max_tokens, 2048)

          anthropic_messages = convert_messages_to_anthropic(validated_messages)
          anthropic_tools = convert_tools_to_anthropic(tools)

          request_params = %{
            model: model,
            messages: anthropic_messages,
            temperature: temperature,
            max_tokens: max_tokens,
            tools: anthropic_tools
          }

          case make_anthropic_request(client, request_params) do
            {:ok, response} ->
              {:ok, build_tools_response(response, model)}

            {:error, reason} ->
              {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl LLMProvider
  def refresh_auth(%{type: :oauth} = auth_context) do
    validate_and_refresh_oauth(auth_context)
  end

  def refresh_auth(%{type: :api_key} = auth_context) do
    # API keys don't need refresh
    {:ok, auth_context}
  end

  @impl LLMProvider
  def validate_auth(%{type: :api_key, credentials: %{"api_key" => api_key}}) do
    validate_api_key(api_key)
  end

  def validate_auth(%{type: :api_key, credentials: %{api_key: api_key}}) do
    validate_api_key(api_key)
  end

  def validate_auth(%{type: :oauth} = auth_context) do
    case validate_and_refresh_oauth(auth_context) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_api_key(api_key) do
    cond do
      String.trim(api_key) == "" ->
        {:error, :invalid_api_key}

      # Basic format validation - Anthropic API keys should start with sk-ant-api or sk-ant-test
      String.starts_with?(api_key, "sk-ant-api") or String.starts_with?(api_key, "sk-ant-test") ->
        :ok

      # For invalid format
      true ->
        {:error, :invalid_api_key}
    end
  end

  @impl LLMProvider
  def list_models(auth_context) do
    case validate_auth_context(auth_context) do
      :ok ->
        determine_models_for_auth(auth_context)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Public API for OAuth flows

  @doc """
  Initiates device authorization flow for CLI environments.

  Returns a URL that the user should visit in their browser and a polling function
  to check for completion.
  """
  def device_authorization_flow(_config \\ %{}) do
    # Use the new device flow implementation
    alias TheMaestro.Providers.Auth.AnthropicDeviceFlow

    flow_state = AnthropicDeviceFlow.new()

    case AnthropicDeviceFlow.initiate_device_flow(flow_state) do
      {:ok, device_response, updated_flow_state} ->
        polling_fn = fn ->
          prompt_for_authorization_code()
        end

        {:ok,
         %{
           auth_url: device_response.verification_uri_complete,
           state: updated_flow_state.state,
           code_verifier: updated_flow_state.code_verifier,
           polling_fn: polling_fn
         }}
    end
  end

  @doc """
  Completes device authorization flow with the provided authorization code.
  """
  def complete_device_authorization(auth_code, _code_verifier) do
    # Use the new device flow implementation
    alias TheMaestro.Providers.Auth.AnthropicDeviceFlow

    flow_state = AnthropicDeviceFlow.new()

    case AnthropicDeviceFlow.exchange_code_for_token(auth_code, flow_state) do
      {:ok, token_struct} ->
        # Convert to the expected format and cache
        tokens = %{
          "access_token" => token_struct.access_token,
          "refresh_token" => token_struct.refresh_token,
          "expires_at" => token_struct.expiry,
          "token_type" => token_struct.token_type,
          "scope" => token_struct.scope
        }

        cache_oauth_credentials_private(tokens)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Initiates web-based OAuth flow.

  Returns a URL for browser-based authentication. Uses the existing Phoenix
  server to handle the OAuth callback.
  """
  def web_authorization_flow(_config \\ %{}) do
    state = generate_state()
    auth_url = build_web_auth_url(@phoenix_redirect_uri, state)

    {:ok,
     %{
       auth_url: auth_url,
       state: state
     }}
  end

  @doc """
  Exchanges authorization code for OAuth tokens.

  This is called by the OAuth controller when handling the callback.
  """
  def exchange_authorization_code(code, redirect_uri) do
    exchange_code_for_tokens(code, nil, redirect_uri)
  end

  @doc """
  Caches OAuth credentials to the filesystem.

  This is called by the OAuth controller after successful token exchange.
  """
  def cache_oauth_credentials(credentials) do
    cache_oauth_credentials_private(credentials)
  end

  @doc """
  Clears cached OAuth credentials.
  """
  def logout do
    credential_path = get_credential_path()

    case File.rm(credential_path) do
      :ok ->
        Logger.info("Anthropic cached credentials cleared")
        :ok

      {:error, :enoent} ->
        # Already deleted
        :ok

      {:error, reason} ->
        {:error, {:failed_to_clear_credentials, reason}}
    end
  end

  # OAuth Token Detection

  defp is_oauth_token?(token) when is_binary(token) do
    String.starts_with?(token, "sk-ant-oat")
  end

  defp determine_models_for_auth(auth_context) do
    # Check if this is an OAuth token - OAuth tokens can't use models.list endpoint
    case auth_context do
      %{type: :oauth, credentials: %{"access_token" => access_token}}
      when is_binary(access_token) ->
        if is_oauth_token?(access_token) do
          # Return hardcoded Claude 4 models for OAuth (models.list doesn't work with OAuth tokens)
          {:ok, get_oauth_models()}
        else
          {:ok, get_anthropic_models()}
        end

      _ ->
        # API key or other auth types - return standard models
        {:ok, get_anthropic_models()}
    end
  end

  # Private Authentication Detection and Flow Management

  defp create_api_key_auth_context(api_key, config) do
    {:ok,
     %{
       type: :api_key,
       credentials: %{api_key: api_key},
       config: config
     }}
  end

  defp initialize_cached_oauth(config) do
    with {:ok, credentials} <- load_cached_oauth_credentials(),
         {:ok, refreshed_context} <- setup_auth_context_and_refresh(credentials, config) do
      {:ok, refreshed_context}
    else
      {:error, _reason} ->
        initialize_oauth_flow(config)
    end
  end

  defp setup_auth_context_and_refresh(credentials, config) do
    auth_context = %{
      type: :oauth,
      credentials: credentials,
      config: config
    }

    validate_and_refresh_oauth(auth_context)
  end

  defp detect_auth_method(config) do
    cond do
      # Check for API key first
      api_key = get_api_key() ->
        {:api_key, api_key}

      # Check for cached OAuth credentials
      File.exists?(get_credential_path()) ->
        {:oauth, :cached}

      # Check if we're explicitly requesting OAuth
      config[:auth_method] == :oauth_cached ->
        {:oauth, :cached}

      # Default to OAuth flow for interactive environments
      !non_interactive?() ->
        {:oauth, :new}

      true ->
        {:error, :no_auth_method_available}
    end
  end

  defp get_api_key do
    System.get_env("ANTHROPIC_API_KEY")
  end

  defp non_interactive? do
    # Check if running in CI or non-interactive environment
    System.get_env("CI") == "true" or
      System.get_env("NON_INTERACTIVE") == "true" or
      !System.get_env("TERM")
  end

  defp initialize_oauth_flow(config) do
    if non_interactive?() do
      {:error, :oauth_not_available_in_non_interactive}
    else
      case config[:auth_flow] do
        :device ->
          device_authorization_flow(config)

        :web ->
          web_authorization_flow(config)

        _ ->
          # Default to device flow for CLI environments
          device_authorization_flow(config)
      end
    end
  end

  # OAuth Credential Management

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

  defp cache_oauth_credentials_private(credentials) do
    credential_path = get_credential_path()
    credential_dir = Path.dirname(credential_path)

    case File.mkdir_p(credential_dir) do
      :ok ->
        content = Jason.encode!(credentials, pretty: true)

        case File.write(credential_path, content, [:write]) do
          :ok ->
            # Set restrictive permissions (equivalent to chmod 600)
            File.chmod(credential_path, 0o600)
            Logger.info("Anthropic OAuth credentials cached successfully")
            {:ok, credentials}

          {:error, reason} ->
            {:error, {:failed_to_cache_credentials, reason}}
        end

      {:error, reason} ->
        {:error, {:failed_to_create_credential_dir, reason}}
    end
  end

  defp get_credential_path do
    home_dir = System.user_home!()
    Path.join([home_dir, @maestro_dir, @oauth_creds_file])
  end

  defp validate_and_refresh_oauth(auth_context) do
    %{credentials: credentials} = auth_context

    case validate_token(credentials["access_token"]) do
      :ok ->
        {:ok, auth_context}

      {:error, :expired} ->
        refresh_oauth_token(auth_context)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_token(access_token) do
    # Determine auth type based on token format
    auth_type = if String.starts_with?(access_token, "sk-ant-oat"), do: :oauth, else: :api_key

    # Create appropriate client
    client =
      case auth_type do
        :oauth -> {:oauth_client, access_token}
        :api_key -> {:http_client, access_token}
      end

    # Make a minimal request to validate the token
    case make_anthropic_request(client, %{
           model: "claude-3-haiku-20240307",
           messages: [%{role: "user", content: "Hi"}],
           max_tokens: 1
         }) do
      {:ok, _response} ->
        :ok

      {:error, {:anthropic_request_failed, 401, _}} ->
        {:error, :expired}

      {:error, {:anthropic_request_failed, 403, _}} ->
        {:error, :expired}

      {:error, reason} ->
        {:error, {:validation_request_failed, reason}}
    end
  end

  defp refresh_oauth_token(%{credentials: credentials} = auth_context) do
    case credentials["refresh_token"] do
      nil ->
        {:error, :no_refresh_token}

      refresh_token ->
        handle_token_refresh(auth_context, refresh_token)
    end
  end

  defp handle_token_refresh(auth_context, refresh_token) do
    case exchange_refresh_token(refresh_token) do
      {:ok, new_tokens} ->
        process_new_tokens(auth_context, new_tokens, refresh_token)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_new_tokens(auth_context, new_tokens, original_refresh_token) do
    # Preserve refresh token if not provided in response
    final_tokens =
      if new_tokens[:refresh_token] do
        new_tokens
      else
        Map.put(new_tokens, :refresh_token, original_refresh_token)
      end

    updated_context = %{auth_context | credentials: final_tokens}

    # Cache the updated credentials
    cache_oauth_credentials_private(final_tokens)

    {:ok, updated_context}
  end

  # OAuth Flow Implementation

  defp build_web_auth_url(redirect_uri, state) do
    params =
      URI.encode_query(%{
        client_id: @oauth_client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: Enum.join(@oauth_scopes, " "),
        state: state
      })

    "https://auth.anthropic.com/oauth/authorize?#{params}"
  end

  defp prompt_for_authorization_code do
    IO.puts("Enter the authorization code from the browser:")

    case IO.read(:line) do
      data when is_binary(data) ->
        String.trim(data)

      _ ->
        ""
    end
  end

  defp exchange_code_for_tokens(code, code_verifier, redirect_uri) do
    body_params = %{
      client_id: @oauth_client_id,
      client_secret: @oauth_client_secret,
      code: code,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri
    }

    body_params =
      if code_verifier do
        Map.put(body_params, :code_verifier, code_verifier)
      else
        body_params
      end

    body = URI.encode_query(body_params)
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    url = "https://auth.anthropic.com/oauth/token"

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, tokens} -> {:ok, atomize_keys(tokens)}
          {:error, reason} -> {:error, {:token_decode_failed, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        {:error, {:token_exchange_failed, status, response_body}}

      {:error, reason} ->
        {:error, {:token_request_failed, reason}}
    end
  end

  defp exchange_refresh_token(refresh_token) do
    body =
      URI.encode_query(%{
        client_id: @oauth_client_id,
        client_secret: @oauth_client_secret,
        refresh_token: refresh_token,
        grant_type: "refresh_token"
      })

    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    url = "https://auth.anthropic.com/oauth/token"

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, tokens} -> {:ok, atomize_keys(tokens)}
          {:error, reason} -> {:error, {:refresh_decode_failed, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        {:error, {:refresh_failed, status, response_body}}

      {:error, reason} ->
        {:error, {:refresh_request_failed, reason}}
    end
  end

  # Request Management

  defp create_anthropic_client(%{type: :api_key, credentials: %{"api_key" => api_key}}) do
    # For API keys (sk-ant-api...), use direct HTTP for consistency
    # The Anthropix library has configuration issues, so we use HTTP directly
    {:ok, {:http_client, api_key}}
  end

  defp create_anthropic_client(%{type: :api_key, credentials: %{api_key: api_key}}) do
    # For API keys with atom keys (test compatibility)
    {:ok, {:http_client, api_key}}
  end

  defp create_anthropic_client(%{type: :oauth, credentials: %{"access_token" => access_token}}) do
    # For OAuth tokens (sk-ant-oat01-...), we need to use direct HTTP with special headers
    {:ok, {:oauth_client, access_token}}
  end

  defp validate_auth_context(%{type: _type, credentials: _credentials}), do: :ok
  defp validate_auth_context(_), do: {:error, :invalid_auth_context}

  defp validate_messages(nil), do: {:error, :invalid_messages}
  defp validate_messages([]), do: {:error, :empty_messages}

  defp validate_messages(messages) when is_list(messages) do
    case Enum.all?(messages, &valid_message?/1) do
      true -> {:ok, messages}
      false -> {:error, :invalid_message_format}
    end
  end

  defp validate_messages(_), do: {:error, :invalid_messages}

  defp valid_message?(%{role: _role, content: _content}), do: true
  defp valid_message?(%{"role" => _role, "content" => _content}), do: true
  defp valid_message?(_), do: false

  # Request handling for different client types
  defp make_anthropic_request({:http_client, api_key}, request_params) do
    # Direct HTTP for API key requests
    make_direct_http_request(api_key, request_params, :api_key)
  end

  defp make_anthropic_request({:oauth_client, access_token}, request_params) do
    # Direct HTTP for OAuth requests with special headers
    make_direct_http_request(access_token, request_params, :oauth)
  end

  defp make_direct_http_request(token, request_params, auth_type) do
    url = "https://api.anthropic.com/v1/messages"

    headers = build_anthropic_headers(token, auth_type)

    # Add Claude Code system prompt for OAuth tokens (required by Anthropic backend)
    updated_params =
      if auth_type == :oauth and is_oauth_token?(token) do
        Map.put(
          request_params,
          :system,
          "You are Claude Code, Anthropic's official CLI for Claude."
        )
      else
        request_params
      end

    body = Jason.encode!(updated_params)

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body, headers: response_headers}} ->
        # Handle potentially compressed response
        decompressed_body = decompress_response_if_needed(response_body, response_headers)

        case Jason.decode(decompressed_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, {:decode_failed, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        {:error, {:anthropic_request_failed, status, response_body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp build_anthropic_headers(token, :api_key) do
    [
      {"x-api-key", token},
      {"content-type", "application/json"},
      {"anthropic-version", "2023-06-01"},
      {"user-agent", "the-maestro/v1.0.0"}
    ]
  end

  defp build_anthropic_headers(token, :oauth) do
    # Critical: Use Authorization Bearer for OAuth tokens and include the oauth-2025-04-20 beta header
    # Keep the extensive headers that match Claude Code exactly for OAuth API calls
    [
      {"connection", "keep-alive"},
      {"accept", "application/json"},
      {"x-stainless-retry-count", "0"},
      {"x-stainless-timeout", "60"},
      {"x-stainless-lang", "js"},
      {"x-stainless-package-version", "0.55.1"},
      {"x-stainless-os", "MacOS"},
      {"x-stainless-arch", "arm64"},
      {"x-stainless-runtime", "node"},
      {"x-stainless-runtime-version", "v23.11.0"},
      {"anthropic-dangerous-direct-browser-access", "true"},
      {"anthropic-version", "2023-06-01"},
      {"authorization", "Bearer #{token}"},
      {"x-app", "cli"},
      {"user-agent", "claude-cli/1.0.81 (external, cli)"},
      {"content-type", "application/json"},
      {"anthropic-beta",
       "claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14"},
      {"x-stainless-helper-method", "stream"},
      {"accept-language", "*"},
      {"sec-fetch-mode", "cors"},
      {"accept-encoding", "gzip, deflate, br"}
    ]
  end

  # Response decompression helper
  defp decompress_response_if_needed(body, headers) do
    content_encoding =
      headers
      |> Enum.find(fn {key, _} -> String.downcase(key) == "content-encoding" end)
      |> case do
        {_, encoding} -> String.downcase(encoding)
        nil -> nil
      end

    case content_encoding do
      "gzip" ->
        :zlib.gunzip(body)

      "deflate" ->
        :zlib.uncompress(body)

      _ ->
        body
    end
  end

  # Utility Functions

  defp generate_state do
    32 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
  end

  defp atomize_keys(map) when is_map(map) do
    for {key, value} <- map, into: %{} do
      atom_key = if is_binary(key), do: String.to_atom(key), else: key
      {atom_key, value}
    end
  end

  # Message and Tool Conversion

  defp convert_messages_to_anthropic(messages) do
    Enum.map(messages, fn message ->
      role =
        case message.role do
          :user -> "user"
          :assistant -> "assistant"
          # Anthropic doesn't support system role in messages - handle separately
          :system -> "user"
          :tool -> "user"
        end

      %{
        role: role,
        content: message.content
      }
    end)
  end

  defp convert_tools_to_anthropic(tools) do
    Enum.map(tools, fn tool ->
      %{
        name: tool["name"],
        description: tool["description"],
        input_schema: tool["parameters"]
      }
    end)
  end

  defp build_text_response(response, model) do
    content = extract_content_from_response(response)

    %{
      content: content,
      model: model,
      usage: Map.get(response, "usage", %{})
    }
  end

  defp build_tools_response(response, model) do
    content = extract_content_from_response(response)
    tool_calls = extract_tool_calls(response)

    %{
      content: content,
      tool_calls: tool_calls,
      model: model,
      usage: Map.get(response, "usage", %{})
    }
  end

  defp extract_content_from_response(%{"content" => content}) when is_list(content) do
    content
    |> Enum.find(&(Map.get(&1, "type") == "text"))
    |> case do
      %{"text" => text} -> text
      _ -> ""
    end
  end

  defp extract_content_from_response(_), do: ""

  defp extract_tool_calls(%{"content" => content}) when is_list(content) do
    content
    |> Enum.filter(&(Map.get(&1, "type") == "tool_use"))
    |> Enum.map(fn tool_use ->
      %{
        "name" => Map.get(tool_use, "name"),
        "arguments" => Map.get(tool_use, "input", %{})
      }
    end)
  end

  defp extract_tool_calls(_), do: []

  # Helper function to return OAuth-compatible models (Claude 4 models only)
  defp get_oauth_models do
    [
      %{
        id: "claude-sonnet-4-20250514",
        name: "Claude 4 Sonnet",
        description:
          "Anthropic's most intelligent model with enhanced reasoning capabilities (OAuth)",
        context_length: 200_000,
        multimodal: true,
        function_calling: true,
        cost_tier: :premium
      },
      %{
        id: "claude-opus-4-20250514",
        name: "Claude 4 Opus",
        description: "Most powerful model for the most complex tasks (OAuth)",
        context_length: 200_000,
        multimodal: true,
        function_calling: true,
        cost_tier: :premium
      }
    ]
  end

  # Helper function to return available Anthropic models
  defp get_anthropic_models do
    [
      %{
        id: "claude-3-5-sonnet-20241022",
        name: "Claude 3.5 Sonnet",
        description: "Anthropic's most intelligent model with enhanced reasoning capabilities",
        context_length: 200_000,
        multimodal: true,
        function_calling: true,
        cost_tier: :premium
      },
      %{
        id: "claude-3-5-haiku-20241022",
        name: "Claude 3.5 Haiku",
        description: "Fast and cost-effective model for simple tasks",
        context_length: 200_000,
        multimodal: true,
        function_calling: true,
        cost_tier: :balanced
      },
      %{
        id: "claude-3-haiku-20240307",
        name: "Claude 3 Haiku",
        description: "Fast and efficient model for everyday tasks",
        context_length: 200_000,
        multimodal: true,
        function_calling: true,
        cost_tier: :balanced
      },
      %{
        id: "claude-3-sonnet-20240229",
        name: "Claude 3 Sonnet",
        description: "Balanced intelligence and speed for complex tasks",
        context_length: 200_000,
        multimodal: true,
        function_calling: true,
        cost_tier: :premium
      },
      %{
        id: "claude-3-opus-20240229",
        name: "Claude 3 Opus",
        description: "Most powerful model for the most complex tasks",
        context_length: 200_000,
        multimodal: true,
        function_calling: true,
        cost_tier: :premium
      }
    ]
  end
end
