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
  @device_auth_redirect_uri "urn:ietf:wg:oauth:2.0:oob"

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
        with {:ok, client} <- create_anthropic_client(auth_context) do
          model = Map.get(opts, :model, "claude-3-sonnet-20240229")
          temperature = Map.get(opts, :temperature, 0.7)
          max_tokens = Map.get(opts, :max_tokens, 2048)

          anthropic_messages = convert_messages_to_anthropic(messages)

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
        with {:ok, client} <- create_anthropic_client(auth_context) do
          tools = Map.get(opts, :tools, [])
          model = Map.get(opts, :model, "claude-3-sonnet-20240229")
          temperature = Map.get(opts, :temperature, 0.0)
          max_tokens = Map.get(opts, :max_tokens, 2048)

          anthropic_messages = convert_messages_to_anthropic(messages)
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
  def validate_auth(%{type: :api_key, credentials: %{api_key: api_key}}) do
    if String.trim(api_key) != "", do: :ok, else: {:error, :invalid_api_key}
  end

  def validate_auth(%{type: :oauth} = auth_context) do
    case validate_and_refresh_oauth(auth_context) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Public API for OAuth flows

  @doc """
  Initiates device authorization flow for CLI environments.

  Returns a URL that the user should visit in their browser and a polling function
  to check for completion.
  """
  def device_authorization_flow(_config \\ %{}) do
    state = generate_state()
    code_verifier = generate_code_verifier()
    code_challenge = generate_code_challenge(code_verifier)

    auth_url = build_device_auth_url(state, code_challenge)

    polling_fn = fn ->
      prompt_for_authorization_code()
    end

    {:ok,
     %{
       auth_url: auth_url,
       state: state,
       code_verifier: code_verifier,
       polling_fn: polling_fn
     }}
  end

  @doc """
  Completes device authorization flow with the provided authorization code.
  """
  def complete_device_authorization(auth_code, code_verifier) do
    case exchange_code_for_tokens(auth_code, code_verifier, @device_auth_redirect_uri) do
      {:ok, tokens} ->
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

    case validate_token(credentials.access_token) do
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
    case credentials[:refresh_token] do
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

  defp build_device_auth_url(state, code_challenge) do
    params =
      URI.encode_query(%{
        client_id: @oauth_client_id,
        redirect_uri: @device_auth_redirect_uri,
        response_type: "code",
        scope: Enum.join(@oauth_scopes, " "),
        state: state,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      })

    "https://auth.anthropic.com/oauth/authorize?#{params}"
  end

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

  defp create_anthropic_client(%{type: :api_key, credentials: %{api_key: api_key}}) do
    # For API keys (sk-ant-api...), use the Anthropix library
    try do
      client = Anthropix.init(api_key: api_key)
      {:ok, {:anthropix_client, client}}
    rescue
      _ ->
        # Fallback to direct HTTP if library doesn't work
        {:ok, {:http_client, api_key}}
    end
  end

  defp create_anthropic_client(%{type: :oauth, credentials: %{access_token: access_token}}) do
    # For OAuth tokens (sk-ant-oat01-...), we need to use direct HTTP with special headers
    {:ok, {:oauth_client, access_token}}
  end

  defp validate_auth_context(%{type: _type, credentials: _credentials}), do: :ok
  defp validate_auth_context(_), do: {:error, :invalid_auth_context}

  # Request handling for different client types
  defp make_anthropic_request({:anthropix_client, client}, request_params) do
    # Use the Anthropix library for API key requests
    Anthropix.chat(client, request_params)
  end

  defp make_anthropic_request({:http_client, api_key}, request_params) do
    # Direct HTTP for API key requests when library fails
    make_direct_http_request(api_key, request_params, :api_key)
  end

  defp make_anthropic_request({:oauth_client, access_token}, request_params) do
    # Direct HTTP for OAuth requests with special headers
    make_direct_http_request(access_token, request_params, :oauth)
  end

  defp make_direct_http_request(token, request_params, auth_type) do
    url = "https://api.anthropic.com/v1/messages"

    headers = build_anthropic_headers(token, auth_type)
    body = Jason.encode!(request_params)

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
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
      {"authorization", "Bearer #{token}"},
      {"content-type", "application/json"},
      {"anthropic-version", "2023-06-01"},
      {"user-agent", "TheMaestro/v0.1.0 (elixir-httpoison)"}
    ]
  end

  defp build_anthropic_headers(token, :oauth) do
    # Based on the raw HTTP request, OAuth needs special beta headers
    [
      {"authorization", "Bearer #{token}"},
      {"content-type", "application/json"},
      {"anthropic-version", "2023-06-01"},
      {"anthropic-beta", "oauth-2025-04-20,fine-grained-tool-streaming-2025-05-14"},
      {"anthropic-dangerous-direct-browser-access", "true"},
      {"x-app", "cli"},
      {"user-agent", "TheMaestro/v0.1.0 (elixir-httpoison)"}
    ]
  end

  # Utility Functions

  defp generate_state do
    32 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
  end

  defp generate_code_verifier do
    43 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp generate_code_challenge(code_verifier) do
    :crypto.hash(:sha256, code_verifier) |> Base.url_encode64(padding: false)
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
end
