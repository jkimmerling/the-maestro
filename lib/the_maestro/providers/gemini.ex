defmodule TheMaestro.Providers.Gemini do
  @moduledoc """
  Gemini LLM Provider implementation with comprehensive OAuth authentication support.

  This module implements the LLMProvider behaviour for Google's Gemini API,
  supporting multiple authentication methods:
  - API Key authentication via GEMINI_API_KEY environment variable
  - OAuth2 authentication with device authorization flow and web-based flow
  - Service Account authentication via GOOGLE_APPLICATION_CREDENTIALS

  Authentication follows the same patterns as the original gemini-cli, including
  credential caching, token refresh, and proper security practices.
  """

  @behaviour TheMaestro.Providers.LLMProvider

  alias TheMaestro.Providers.LLMProvider

  require Logger

  # OAuth Configuration - matches gemini-cli settings
  @oauth_client_id "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
  @oauth_client_secret "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"
  @oauth_scopes [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile"
  ]
  @oauth_redirect_uri_pattern "http://localhost:%d/oauth2callback"
  @device_auth_redirect_uri "https://codeassist.google.com/authcode"

  # File paths for credential storage
  @maestro_dir ".maestro"
  @oauth_creds_file "oauth_creds.json"

  @impl LLMProvider
  def initialize_auth(config \\ %{}) do
    case detect_auth_method(config) do
      {:api_key, api_key} ->
        {:ok, %{
          type: :api_key,
          credentials: %{api_key: api_key},
          config: config
        }}

      {:oauth, :cached} ->
        case load_cached_oauth_credentials() do
          {:ok, credentials} ->
            auth_context = %{
              type: :oauth,
              credentials: credentials,
              config: config
            }
            # Validate and refresh if needed
            case validate_and_refresh_oauth(auth_context) do
              {:ok, refreshed_context} -> {:ok, refreshed_context}
              {:error, _} -> initialize_oauth_flow(config)
            end

          {:error, _} ->
            initialize_oauth_flow(config)
        end

      {:oauth, :new} ->
        initialize_oauth_flow(config)

      {:service_account, creds_path} ->
        case Goth.Token.for_scope(@oauth_scopes, source: creds_path) do
          {:ok, %Goth.Token{token: token}} ->
            {:ok, %{
              type: :service_account,
              credentials: %{access_token: token, source: creds_path},
              config: config
            }}

          {:error, reason} ->
            {:error, {:service_account_auth_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl LLMProvider
  def complete_text(auth_context, messages, opts \\ %{}) do
    case get_access_token(auth_context) do
      {:ok, token} ->
        gemini_messages = convert_messages_to_gemini(messages)
        model = Map.get(opts, :model, "gemini-1.5-pro")
        
        request_body = %{
          contents: gemini_messages,
          generationConfig: %{
            temperature: Map.get(opts, :temperature, 0.7),
            maxOutputTokens: Map.get(opts, :max_tokens, 8192)
          }
        }

        case make_gemini_request(token, model, request_body) do
          {:ok, response} ->
            {:ok, %{
              content: extract_text_content(response),
              model: model,
              usage: extract_usage_info(response)
            }}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl LLMProvider
  def complete_with_tools(auth_context, messages, opts \\ %{}) do
    case get_access_token(auth_context) do
      {:ok, token} ->
        gemini_messages = convert_messages_to_gemini(messages)
        gemini_tools = convert_tools_to_gemini(Map.get(opts, :tools, []))
        model = Map.get(opts, :model, "gemini-1.5-pro")
        
        request_body = %{
          contents: gemini_messages,
          tools: gemini_tools,
          generationConfig: %{
            temperature: Map.get(opts, :temperature, 0.7),
            maxOutputTokens: Map.get(opts, :max_tokens, 8192)
          }
        }

        case make_gemini_request(token, model, request_body) do
          {:ok, response} ->
            {:ok, %{
              content: extract_text_content(response),
              tool_calls: extract_tool_calls(response),
              model: model,
              usage: extract_usage_info(response)
            }}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl LLMProvider
  def refresh_auth(%{type: :oauth} = auth_context) do
    validate_and_refresh_oauth(auth_context)
  end

  def refresh_auth(%{type: :service_account, credentials: %{source: source}} = auth_context) do
    case Goth.Token.for_scope(@oauth_scopes, source: source) do
      {:ok, %Goth.Token{token: token}} ->
        {:ok, %{auth_context | credentials: %{access_token: token, source: source}}}

      {:error, reason} ->
        {:error, {:refresh_failed, reason}}
    end
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

  def validate_auth(%{type: :service_account} = auth_context) do
    case refresh_auth(auth_context) do
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
  def device_authorization_flow(config \\ %{}) do
    state = generate_state()
    code_verifier = generate_code_verifier()
    code_challenge = generate_code_challenge(code_verifier)

    auth_url = build_device_auth_url(state, code_challenge)
    
    polling_fn = fn ->
      prompt_for_authorization_code()
    end

    {:ok, %{
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
        cache_oauth_credentials(tokens)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Initiates web-based OAuth flow.
  
  Returns a URL for browser-based authentication and starts a local server
  to handle the callback.
  """
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

  @doc """
  Clears cached OAuth credentials.
  """
  def logout do
    credential_path = get_credential_path()
    case File.rm(credential_path) do
      :ok -> 
        Logger.info("Cached credentials cleared")
        :ok
      {:error, :enoent} -> 
        :ok  # Already deleted
      {:error, reason} -> 
        {:error, {:failed_to_clear_credentials, reason}}
    end
  end

  # Private Authentication Detection and Flow Management

  defp detect_auth_method(config) do
    cond do
      # Check for API key first
      api_key = get_api_key() ->
        {:api_key, api_key}

      # Check for service account credentials
      service_account_path = get_service_account_path() ->
        {:service_account, service_account_path}

      # Check for cached OAuth credentials
      File.exists?(get_credential_path()) ->
        {:oauth, :cached}

      # Default to OAuth flow for interactive environments
      !is_non_interactive() ->
        {:oauth, :new}

      true ->
        {:error, :no_auth_method_available}
    end
  end

  defp get_api_key do
    System.get_env("GEMINI_API_KEY")
  end

  defp get_service_account_path do
    System.get_env("GOOGLE_APPLICATION_CREDENTIALS")
  end

  defp is_non_interactive do
    # Check if running in CI or non-interactive environment
    System.get_env("CI") == "true" or 
    System.get_env("NON_INTERACTIVE") == "true" or
    !System.get_env("TERM")
  end

  defp initialize_oauth_flow(config) do
    if is_non_interactive() do
      {:error, :oauth_not_available_in_non_interactive}
    else
      case config[:auth_flow] do
        :device -> device_authorization_flow(config)
        :web -> web_authorization_flow(config)
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
            Logger.info("OAuth credentials cached successfully")
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
    url = "https://www.googleapis.com/oauth2/v2/tokeninfo?access_token=#{access_token}"
    
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: 400, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"error" => "invalid_token"}} -> {:error, :expired}
          _ -> {:error, :invalid_token}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, {:validation_request_failed, reason}}
    end
  end

  defp refresh_oauth_token(%{credentials: credentials} = auth_context) do
    case credentials[:refresh_token] do
      nil ->
        {:error, :no_refresh_token}

      refresh_token ->
        case exchange_refresh_token(refresh_token) do
          {:ok, new_tokens} ->
            # Preserve refresh token if not provided in response
            final_tokens = if new_tokens[:refresh_token] do
              new_tokens
            else
              Map.put(new_tokens, :refresh_token, refresh_token)
            end

            updated_context = %{auth_context | credentials: final_tokens}
            
            # Cache the updated credentials
            cache_oauth_credentials(final_tokens)
            
            {:ok, updated_context}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # OAuth Flow Implementation

  defp build_device_auth_url(state, code_challenge) do
    params = URI.encode_query(%{
      client_id: @oauth_client_id,
      redirect_uri: @device_auth_redirect_uri,
      response_type: "code",
      scope: Enum.join(@oauth_scopes, " "),
      state: state,
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      access_type: "offline",
      prompt: "consent"
    })

    "https://accounts.google.com/o/oauth2/v2/auth?#{params}"
  end

  defp build_web_auth_url(redirect_uri, state) do
    params = URI.encode_query(%{
      client_id: @oauth_client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: Enum.join(@oauth_scopes, " "),
      state: state,
      access_type: "offline",
      prompt: "consent"
    })

    "https://accounts.google.com/o/oauth2/v2/auth?#{params}"
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
    body = URI.encode_query(%{
      client_id: @oauth_client_id,
      client_secret: @oauth_client_secret,
      code: code,
      code_verifier: code_verifier,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri
    })

    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    url = "https://oauth2.googleapis.com/token"

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
    body = URI.encode_query(%{
      client_id: @oauth_client_id,
      client_secret: @oauth_client_secret,
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    })

    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    url = "https://oauth2.googleapis.com/token"

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

  # OAuth Server for Web Flow

  defp start_callback_server(port, state, redirect_uri) do
    spawn(fn -> 
      callback_server_loop(port, state, redirect_uri)
    end)
  end

  defp callback_server_loop(port, expected_state, redirect_uri) do
    # This would need a proper HTTP server implementation
    # For now, this is a placeholder that would integrate with Bandit or similar
    Logger.info("OAuth callback server would start on port #{port}")
    
    receive do
      {:authorization_code, code, state} when state == expected_state ->
        code_verifier = generate_code_verifier()
        case exchange_code_for_tokens(code, code_verifier, redirect_uri) do
          {:ok, tokens} ->
            cache_oauth_credentials(tokens)
            Logger.info("OAuth flow completed successfully")

          {:error, reason} ->
            Logger.error("Failed to exchange authorization code: #{inspect(reason)}")
        end

      _ ->
        Logger.error("Invalid authorization callback")
    end
  end

  defp get_available_port_number do
    # Find available port for OAuth callback
    case :gen_tcp.listen(0, []) do
      {:ok, socket} ->
        {:ok, port} = :inet.port(socket)
        :gen_tcp.close(socket)
        port

      _ ->
        # Fallback to a high port number
        8080 + :rand.uniform(1000)
    end
  end

  # Token and Request Management

  defp get_access_token(%{type: :api_key, credentials: %{api_key: api_key}}) do
    {:ok, api_key}
  end

  defp get_access_token(%{type: :oauth, credentials: credentials}) do
    case credentials[:access_token] do
      nil -> {:error, :no_access_token}
      token -> {:ok, token}
    end
  end

  defp get_access_token(%{type: :service_account, credentials: %{access_token: token}}) do
    {:ok, token}
  end

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

  defp convert_messages_to_gemini(messages) do
    Enum.map(messages, fn message ->
      role = case message.role do
        :user -> "user"
        :assistant -> "model"
        :system -> "user"  # Gemini doesn't have system role, treat as user
      end

      %{
        role: role,
        parts: [%{text: message.content}]
      }
    end)
  end

  defp convert_tools_to_gemini(tools) do
    function_declarations = Enum.map(tools, fn tool ->
      %{
        name: tool.name,
        description: tool.description,
        parameters: tool.parameters
      }
    end)

    [%{function_declarations: function_declarations}]
  end

  defp extract_text_content(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    parts
    |> Enum.find(&Map.has_key?(&1, "text"))
    |> case do
      %{"text" => text} -> text
      _ -> ""
    end
  end

  defp extract_text_content(_), do: ""

  defp extract_tool_calls(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    parts
    |> Enum.filter(&Map.has_key?(&1, "functionCall"))
    |> Enum.map(fn %{"functionCall" => call} ->
      %{
        name: call["name"],
        arguments: call["args"] || %{}
      }
    end)
  end

  defp extract_tool_calls(_), do: []

  defp extract_usage_info(%{"usageMetadata" => usage}), do: usage
  defp extract_usage_info(_), do: %{}
end