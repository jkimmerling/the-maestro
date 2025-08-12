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
  @phoenix_redirect_uri "http://localhost:4000/oauth2callback"
  @device_auth_redirect_uri "https://codeassist.google.com/authcode"

  # File paths for credential storage
  @maestro_dir ".maestro"
  @oauth_creds_file "oauth_creds.json"

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

      {:service_account, creds_path} ->
        initialize_service_account_auth(creds_path, config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl LLMProvider
  def complete_text(auth_context, messages, opts \\ %{}) do
    case get_access_token(auth_context) do
      {:ok, token} ->
        gemini_messages = convert_messages_to_gemini(messages)
        model = Map.get(opts, :model, "gemini-2.5-pro")

        # Choose request format based on auth type (like original gemini-cli)
        request_body = case auth_context.type do
          :api_key ->
            # Direct Generative Language API format for API keys
            %{
              contents: gemini_messages,
              generationConfig: %{
                temperature: Map.get(opts, :temperature, 0.7),
                maxOutputTokens: Map.get(opts, :max_tokens, 8192)
              }
            }
          _ ->
            # Code Assist API format - NO tools field, model generates function calls directly
            %{
              model: model,
              project: get_project_id_from_context(auth_context),  
              user_prompt_id: generate_user_prompt_id(),
              request: %{
                contents: gemini_messages,
                generationConfig: %{
                  temperature: Map.get(opts, :temperature, 0.0),
                  topP: 1
                }
              }
            }
        end

        case make_gemini_request(token, model, request_body, auth_context.type) do
          {:ok, response} ->
            {:ok,
             %{
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
        tools = Map.get(opts, :tools, [])
        model = Map.get(opts, :model, "gemini-2.5-pro")

        # Choose request format based on auth type (like original gemini-cli)
        request_body = case auth_context.type do
          :api_key ->
            # Direct Generative Language API format for API keys
            gemini_messages = convert_messages_to_gemini(messages)
            gemini_tools = convert_tools_to_gemini(tools)
            %{
              contents: gemini_messages,
              tools: gemini_tools,
              generationConfig: %{
                temperature: Map.get(opts, :temperature, 0.7),
                maxOutputTokens: Map.get(opts, :max_tokens, 8192)
              }
            }
          _ ->
            # Code Assist API format - use systemInstruction and tools fields like original gemini-cli
            gemini_messages = convert_messages_to_gemini(messages)
            gemini_tools = convert_tools_to_gemini(tools)
            system_instruction = build_system_instruction_with_tools(tools)
            
            request_content = %{
              contents: gemini_messages,
              generationConfig: %{
                temperature: Map.get(opts, :temperature, 0.0),
                topP: 1
              }
            }
            
            # Add systemInstruction if tools are available
            request_content = if Enum.empty?(tools) do
              request_content
            else
              Map.put(request_content, :systemInstruction, %{
                role: "user",
                parts: [%{text: system_instruction}]
              })
            end
            
            # Add tools if available
            request_content = if Enum.empty?(gemini_tools) do
              request_content
            else
              Map.put(request_content, :tools, gemini_tools)
            end
            
            %{
              model: model,
              project: get_project_id_from_context(auth_context),
              user_prompt_id: generate_user_prompt_id(),
              request: request_content
            }
        end

        case make_gemini_request(token, model, request_body, auth_context.type) do
          {:ok, response} ->
            {:ok,
             %{
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
    opts = [source: source, scopes: @oauth_scopes]

    case Goth.fetch(opts) do
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
        Logger.info("Cached credentials cleared")
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
    case load_cached_oauth_credentials() do
      {:ok, credentials} ->
        auth_context = %{
          type: :oauth,
          credentials: credentials,
          config: config
        }

        # Validate and refresh if needed
        case validate_and_refresh_oauth(auth_context) do
          {:ok, refreshed_context} ->
            # Set up Code Assist user (like original gemini-cli)
            case setup_code_assist_user(refreshed_context) do
              {:ok, user_data} ->
                updated_context = Map.put(refreshed_context, :user_data, user_data)
                {:ok, updated_context}
              {:error, reason} ->
                Logger.error("Failed to set up Code Assist user: #{inspect(reason)}")
                {:error, reason}
            end
          {:error, _} -> 
            initialize_oauth_flow(config)
        end

      {:error, _} ->
        initialize_oauth_flow(config)
    end
  end

  defp initialize_service_account_auth(creds_path, config) do
    opts = [source: creds_path, scopes: @oauth_scopes]

    case Goth.fetch(opts) do
      {:ok, %Goth.Token{token: token}} ->
        {:ok,
         %{
           type: :service_account,
           credentials: %{access_token: token, source: creds_path},
           config: config
         }}

      {:error, reason} ->
        {:error, {:service_account_auth_failed, reason}}
    end
  end

  defp detect_auth_method(_config) do
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
      !non_interactive?() ->
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
        code_challenge_method: "S256",
        access_type: "offline",
        prompt: "consent"
      })

    "https://accounts.google.com/o/oauth2/v2/auth?#{params}"
  end

  defp build_web_auth_url(redirect_uri, state) do
    params =
      URI.encode_query(%{
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
    body =
      URI.encode_query(%{
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
    body =
      URI.encode_query(%{
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

  # OAuth Server functions removed - now using Phoenix endpoint

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

  defp make_gemini_request(token, model, request_body, auth_type) do
    # Choose endpoint based on auth type (like original gemini-cli)
    url = case auth_type do
      :api_key ->
        # Direct Generative Language API for API keys
        "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent"
      _ ->
        # Code Assist API for OAuth and service accounts
        "https://cloudcode-pa.googleapis.com/v1internal:generateContent"
    end

    headers =
      case String.starts_with?(token, "AIza") do
        true ->
          # API Key authentication
          [{"content-type", "application/json"}]

        false ->
          # OAuth or Service Account token - match original gemini-cli headers
          [
            {"authorization", "Bearer #{token}"},
            {"content-type", "application/json"},
            {"user-agent", "TheMaestro/v0.1.0 (darwin; arm64) elixir-httpoison"},
            {"x-goog-api-client", "gl-elixir/1.0.0"},
            {"accept", "application/json"}
          ]
      end

    final_url =
      case String.starts_with?(token, "AIza") do
        true -> "#{url}?key=#{token}"
        false -> url
      end

    # Debug logging to compare with original gemini-cli
    Logger.debug("Making request to: #{final_url}")
    Logger.debug("Request body: #{Jason.encode!(request_body, pretty: true)}")
    Logger.debug("Headers: #{inspect(headers)}")

    case HTTPoison.post(final_url, Jason.encode!(request_body), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, decoded} = result ->
            Logger.debug("Raw API response: #{Jason.encode!(decoded, pretty: true)}")
            result
          error -> error
        end

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        Logger.error("Request failed with status #{status}: #{response_body}")
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

  defp generate_user_prompt_id do
    # Generate a unique user prompt ID (like gemini-cli)
    32 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
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
      role =
        case message.role do
          :user -> "user"
          :assistant -> "model"
          # Gemini doesn't have system role, treat as user
          :system -> "user"
          # Tool results should be treated as model responses in Gemini
          :tool -> "model"
        end

      %{
        role: role,
        parts: [%{text: message.content}]
      }
    end)
  end


  defp build_system_instruction_with_tools(tools) do
    tool_descriptions = build_tool_descriptions(tools)
    
    """
    You are an interactive CLI agent specializing in software engineering tasks. Your primary goal is to help users safely and efficiently, adhering strictly to the following instructions and utilizing your available tools.

    # Core Mandates

    - **Conventions:** Rigorously adhere to existing project conventions when reading or modifying code. Analyze surrounding code, tests, and configuration first.
    - **Libraries/Frameworks:** NEVER assume a library/framework is available or appropriate. Verify its established usage within the project (check imports, configuration files like 'package.json', 'Cargo.toml', 'requirements.txt', 'build.gradle', etc., or observe neighboring files) before employing it.
    - **Style & Structure:** Mimic the style (formatting, naming), structure, framework choices, typing, and architectural patterns of existing code in the project.
    - **Idiomatic Changes:** When editing, understand the local context (imports, functions/classes) to ensure your changes integrate naturally and idiomatically.
    - **Comments:** Add code comments sparingly. Focus on *why* something is done, especially for complex logic, rather than *what* is done. Only add high-value comments if necessary for clarity or if requested by the user.
    - **Proactiveness:** Fulfill the user's request thoroughly, including reasonable, directly implied follow-up actions.
    - **Path Construction:** Before using any file system tool, you must construct the full absolute path for the file_path argument. Always combine the absolute path of the project's root directory with the file's path relative to the root.

    # Available Tools

    You have access to the following tools. When you need to use a tool, generate a functionCall with the exact tool name and required arguments:

    #{tool_descriptions}

    # Tool Usage

    To use a tool, you must generate a functionCall part in your response. The functionCall format is:
    
    {
      "functionCall": {
        "name": "tool_name",
        "args": {
          "parameter_name": "parameter_value"
        }
      }
    }

    For example, to read a file:
    {
      "functionCall": {
        "name": "read_file", 
        "args": {
          "path": "/path/to/file.txt"
        }
      }
    }

    Always use tools when appropriate to fulfill user requests that require file system access, code analysis, or other operations beyond text generation. The system will execute the tool and provide results back to you in a functionResponse.
    """
  end

  defp build_tool_descriptions(tools) do
    tools
    |> Enum.map(&format_tool_description/1)
    |> Enum.join("\n\n")
  end

  defp format_tool_description(%{"name" => name, "description" => description, "parameters" => parameters}) do
    # Format parameters for display
    params_desc = format_parameters(parameters)
    
    """
    ## #{name}
    #{description}
    
    Parameters:
    #{params_desc}
    """
  end

  defp format_parameters(%{"type" => "object", "properties" => properties, "required" => required}) do
    properties
    |> Enum.map(fn {param_name, param_info} ->
      required_marker = if param_name in required, do: " (required)", else: ""
      param_type = Map.get(param_info, "type", "string")
      param_desc = Map.get(param_info, "description", "")
      
      "- **#{param_name}** (#{param_type})#{required_marker}: #{param_desc}"
    end)
    |> Enum.join("\n")
  end

  defp format_parameters(parameters) do
    inspect(parameters)
  end

  defp convert_tools_to_gemini(tools) do
    # Code Assist API and Generative Language API use the same function_declarations format
    # The original gemini-cli uses function_declarations for custom tools
    function_declarations =
      Enum.map(tools, fn tool ->
        %{
          name: tool["name"],
          description: tool["description"], 
          parameters: tool["parameters"]
        }
      end)

    [%{function_declarations: function_declarations}]
  end

  defp extract_text_content(%{"response" => response}), do: extract_text_content(response)
  defp extract_text_content(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    parts
    |> Enum.find(&Map.has_key?(&1, "text"))
    |> case do
      %{"text" => text} -> text
      _ -> ""
    end
  end

  defp extract_text_content(_), do: ""

  defp extract_tool_calls(%{"response" => response}), do: extract_tool_calls(response)
  defp extract_tool_calls(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    parts
    |> Enum.filter(&Map.has_key?(&1, "functionCall"))
    |> Enum.map(fn %{"functionCall" => call} ->
      %{
        "name" => call["name"],
        "arguments" => call["args"] || %{}
      }
    end)
  end

  defp extract_tool_calls(_), do: []

  defp extract_usage_info(%{"response" => response}), do: extract_usage_info(response)
  defp extract_usage_info(%{"usageMetadata" => usage}), do: usage
  defp extract_usage_info(_), do: %{}

  # Code Assist Setup Functions (mimicking original gemini-cli setup.ts)

  defp setup_code_assist_user(auth_context) do
    Logger.info("Setting up Code Assist user...")
    
    # Get project ID from environment (like original gemini-cli)
    project_id = System.get_env("GOOGLE_CLOUD_PROJECT")
    
    case get_access_token(auth_context) do
      {:ok, token} ->
        # Step 1: Load Code Assist (like loadCodeAssist in original)
        case load_code_assist(token, project_id) do
          {:ok, load_response} ->
            # Extract project ID from response if not set
            final_project_id = project_id || Map.get(load_response, "cloudaicompanionProject")
            
            # Step 2: Get tier information
            tier = get_onboard_tier(load_response)
            
            # Step 3: Onboard user with polling (like original)
            case onboard_user(token, final_project_id, tier) do
              {:ok, onboard_response} ->
                # Extract final project ID from onboard response
                result_project_id = get_in(onboard_response, ["response", "cloudaicompanionProject", "id"]) || final_project_id
                
                if result_project_id do
                  {:ok, %{project_id: result_project_id, user_tier: tier["id"]}}
                else
                  {:error, :project_id_required}
                end
              {:error, reason} ->
                {:error, reason}
            end
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_code_assist(token, project_id) do
    url = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
    
    headers = [
      {"authorization", "Bearer #{token}"},
      {"content-type", "application/json"}
    ]
    
    # Client metadata (like original gemini-cli)
    client_metadata = %{
      "ideType" => "IDE_UNSPECIFIED",
      "platform" => "PLATFORM_UNSPECIFIED",
      "pluginType" => "GEMINI",
      "duetProject" => project_id
    }
    
    request_body = %{
      "cloudaicompanionProject" => project_id,
      "metadata" => client_metadata
    }
    
    case HTTPoison.post(url, Jason.encode!(request_body), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        Jason.decode(response_body)
      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        {:error, {:load_code_assist_failed, status, response_body}}
      {:error, reason} ->
        {:error, {:load_code_assist_request_failed, reason}}
    end
  end

  defp onboard_user(token, project_id, tier) do
    url = "https://cloudcode-pa.googleapis.com/v1internal:onboardUser"
    
    headers = [
      {"authorization", "Bearer #{token}"},
      {"content-type", "application/json"}
    ]
    
    # Client metadata (like original gemini-cli)
    client_metadata = %{
      "ideType" => "IDE_UNSPECIFIED",
      "platform" => "PLATFORM_UNSPECIFIED", 
      "pluginType" => "GEMINI",
      "duetProject" => project_id
    }
    
    request_body = %{
      "tierId" => tier["id"],
      "cloudaicompanionProject" => project_id,
      "metadata" => client_metadata
    }
    
    # Poll until operation is complete (like original gemini-cli)
    poll_onboard_user(url, request_body, headers, 0)
  end

  defp poll_onboard_user(url, request_body, headers, attempt) do
    case HTTPoison.post(url, Jason.encode!(request_body), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"done" => true} = response} ->
            {:ok, response}
          {:ok, %{"done" => false}} when attempt < 10 ->
            # Wait 5 seconds and retry (like original gemini-cli)
            Logger.info("Waiting for onboard operation to complete... (attempt #{attempt + 1})")
            Process.sleep(5000)
            poll_onboard_user(url, request_body, headers, attempt + 1)
          {:ok, %{"done" => false}} ->
            {:error, :onboard_timeout}
          {:error, reason} ->
            {:error, {:onboard_decode_failed, reason}}
        end
      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        {:error, {:onboard_failed, status, response_body}}
      {:error, reason} ->
        {:error, {:onboard_request_failed, reason}}
    end
  end

  defp get_onboard_tier(load_response) do
    cond do
      # If current tier exists, use it
      current_tier = Map.get(load_response, "currentTier") ->
        current_tier
      
      # Otherwise find default tier from allowed tiers
      allowed_tiers = Map.get(load_response, "allowedTiers", []) ->
        Enum.find(allowed_tiers, fn tier -> Map.get(tier, "isDefault") end) ||
        %{
          "name" => "",
          "description" => "",
          "id" => "LEGACY",
          "userDefinedCloudaicompanionProject" => true
        }
      
      # Fallback
      true ->
        %{
          "name" => "",
          "description" => "",
          "id" => "LEGACY", 
          "userDefinedCloudaicompanionProject" => true
        }
    end
  end

  # Update request to use project ID from user_data
  defp get_project_id_from_context(auth_context) do
    project_id = case auth_context do
      %{user_data: %{project_id: project_id}} when not is_nil(project_id) ->
        project_id
      _ ->
        System.get_env("GOOGLE_CLOUD_PROJECT")
    end
    
    Logger.debug("Using project ID: #{inspect(project_id)}")
    project_id
  end
end
