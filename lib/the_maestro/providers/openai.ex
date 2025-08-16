defmodule TheMaestro.Providers.OpenAI do
  @moduledoc """
  OpenAI LLM Provider implementation with comprehensive OAuth authentication support.

  This module implements the LLMProvider behaviour for OpenAI's API,
  supporting multiple authentication methods:
  - API Key authentication via OPENAI_API_KEY environment variable
  - OAuth2 authentication with device authorization flow and web-based flow
  - User-delegated OAuth tokens for enterprise use cases

  The OAuth implementation follows similar patterns to the Gemini provider,
  including credential caching, token refresh, and proper security practices.
  """

  @behaviour TheMaestro.Providers.LLMProvider

  alias OpenaiEx.Chat.Completions
  alias TheMaestro.Models.Model
  alias TheMaestro.Providers.LLMProvider

  require Logger

  # OAuth Configuration for OpenAI
  @oauth_client_id System.get_env("OPENAI_OAUTH_CLIENT_ID") || "openai-client-id"
  @oauth_client_secret System.get_env("OPENAI_OAUTH_CLIENT_SECRET") || "openai-client-secret"
  @oauth_scopes ["openai"]
  @phoenix_redirect_uri "http://localhost:4000/oauth2callback/openai"
  @device_auth_redirect_uri "urn:ietf:wg:oauth:2.0:oob"

  # File paths for credential storage
  @maestro_dir ".maestro"
  @oauth_creds_file "openai_oauth_creds.json"

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
        with {:ok, client} <- create_openai_client(auth_context) do
          model = Map.get(opts, :model, "gpt-4")
          temperature = Map.get(opts, :temperature, 0.7)
          max_tokens = Map.get(opts, :max_tokens, 2048)

          openai_messages = convert_messages_to_openai(messages)

          request_params = %{
            model: model,
            messages: openai_messages,
            temperature: temperature,
            max_tokens: max_tokens
          }

          case Completions.create(client, request_params) do
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
        with {:ok, client} <- create_openai_client(auth_context) do
          tools = Map.get(opts, :tools, [])
          model = Map.get(opts, :model, "gpt-4")
          temperature = Map.get(opts, :temperature, 0.0)
          max_tokens = Map.get(opts, :max_tokens, 2048)

          openai_messages = convert_messages_to_openai(messages)
          openai_tools = convert_tools_to_openai(tools)

          request_params = %{
            model: model,
            messages: openai_messages,
            temperature: temperature,
            max_tokens: max_tokens,
            tools: openai_tools,
            tool_choice: "auto"
          }

          case Completions.create(client, request_params) do
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

  @impl LLMProvider
  def list_models(auth_context) do
    case validate_auth_context(auth_context) do
      :ok ->
        fetch_openai_models(auth_context)

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
        Logger.info("OpenAI cached credentials cleared")
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
    System.get_env("OPENAI_API_KEY")
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
            Logger.info("OpenAI OAuth credentials cached successfully")
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
    # OpenAI doesn't have a token validation endpoint like Google
    # We'll validate by making a simple API call
    client = OpenaiEx.new(access_token)

    case OpenaiEx.Models.list(client) do
      {:ok, _models} ->
        :ok

      {:error, %{status: 401}} ->
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

    "https://auth.openai.com/oauth/authorize?#{params}"
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

    "https://auth.openai.com/oauth/authorize?#{params}"
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
    url = "https://auth.openai.com/oauth/token"

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
    url = "https://auth.openai.com/oauth/token"

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

  defp create_openai_client(%{type: :api_key, credentials: %{api_key: api_key}}) do
    {:ok, OpenaiEx.new(api_key)}
  end

  defp create_openai_client(%{type: :oauth, credentials: %{access_token: access_token}}) do
    {:ok, OpenaiEx.new(access_token)}
  end

  defp create_openai_client(_auth_context) do
    {:error, :unsupported_auth_type}
  end

  defp validate_auth_context(%{type: _type, credentials: _credentials}), do: :ok
  defp validate_auth_context(_), do: {:error, :invalid_auth_context}

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

  defp convert_messages_to_openai(messages) do
    Enum.map(messages, fn message ->
      role =
        case message.role do
          :user -> "user"
          :assistant -> "assistant"
          :system -> "system"
          :tool -> "tool"
        end

      %{
        role: role,
        content: message.content
      }
    end)
  end

  defp convert_tools_to_openai(tools) do
    Enum.map(tools, fn tool ->
      %{
        type: "function",
        function: %{
          name: tool["name"],
          description: tool["description"],
          parameters: tool["parameters"]
        }
      }
    end)
  end

  defp build_text_response(response, model) do
    content = get_in(response, ["choices", Access.at(0), "message", "content"]) || ""

    %{
      content: content,
      model: model,
      usage: Map.get(response, "usage", %{})
    }
  end

  defp build_tools_response(response, model) do
    choice = get_in(response, ["choices", Access.at(0)]) || %{}
    message = Map.get(choice, "message", %{})

    content = Map.get(message, "content")
    tool_calls = extract_tool_calls(message)

    %{
      content: content,
      tool_calls: tool_calls,
      model: model,
      usage: Map.get(response, "usage", %{})
    }
  end

  defp extract_tool_calls(%{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    Enum.map(tool_calls, fn tool_call ->
      function = Map.get(tool_call, "function", %{})

      %{
        "name" => Map.get(function, "name"),
        "arguments" =>
          case Map.get(function, "arguments") do
            args when is_binary(args) ->
              case Jason.decode(args) do
                {:ok, parsed} -> parsed
                {:error, _} -> %{}
              end

            args when is_map(args) ->
              args

            _ ->
              %{}
          end
      }
    end)
  end

  defp extract_tool_calls(_), do: []

  # Helper function to fetch OpenAI models from API
  defp fetch_openai_models(auth_context) do
    case create_openai_client(auth_context) do
      {:ok, client} ->
        case OpenaiEx.Models.list(client) do
          {:ok, %{"data" => models}} ->
            formatted_models =
              models
              |> Enum.filter(&chat_model?/1)
              |> Enum.map(&format_openai_model/1)
              |> Enum.sort_by(& &1.name)

            {:ok, formatted_models}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp chat_model?(%{"id" => id}) do
    String.contains?(id, ["gpt-3.5", "gpt-4", "gpt-4o"]) and
      not String.contains?(id, ["instruct", "edit", "search", "similarity"])
  end

  defp format_openai_model(%{"id" => id} = _model) do
    Model.new(%{
      id: id,
      name: format_model_name(id),
      description: get_model_description(id),
      provider: :openai,
      context_length: get_model_context_length(id),
      multimodal: multimodal_model?(id),
      function_calling: supports_function_calling?(id),
      cost_tier: get_cost_tier(id),
      capabilities: get_openai_capabilities(id)
    })
  end

  defp format_model_name("gpt-3.5-turbo"), do: "GPT-3.5 Turbo"
  defp format_model_name("gpt-3.5-turbo-16k"), do: "GPT-3.5 Turbo 16K"
  defp format_model_name("gpt-4"), do: "GPT-4"
  defp format_model_name("gpt-4-32k"), do: "GPT-4 32K"
  defp format_model_name("gpt-4-turbo"), do: "GPT-4 Turbo"
  defp format_model_name("gpt-4o"), do: "GPT-4o"
  defp format_model_name("gpt-4o-mini"), do: "GPT-4o mini"
  defp format_model_name(id), do: String.replace(id, "-", " ") |> String.upcase()

  defp get_model_description("gpt-3.5-turbo"),
    do: "Most capable GPT-3.5 model, optimized for chat"

  defp get_model_description("gpt-4"),
    do: "More capable than any GPT-3.5 model, able to do more complex tasks"

  defp get_model_description("gpt-4-turbo"),
    do: "Latest GPT-4 model with improved instruction following"

  defp get_model_description("gpt-4o"),
    do: "Most advanced multimodal model, faster and cheaper than GPT-4"

  defp get_model_description("gpt-4o-mini"), do: "Fast and affordable model for simple tasks"
  defp get_model_description(_), do: "OpenAI language model"

  defp get_model_context_length("gpt-3.5-turbo"), do: 16_384
  defp get_model_context_length("gpt-3.5-turbo-16k"), do: 16_384
  defp get_model_context_length("gpt-4"), do: 8_192
  defp get_model_context_length("gpt-4-32k"), do: 32_768
  defp get_model_context_length("gpt-4-turbo"), do: 128_000
  defp get_model_context_length("gpt-4o"), do: 128_000
  defp get_model_context_length("gpt-4o-mini"), do: 128_000
  defp get_model_context_length(_), do: nil

  defp multimodal_model?(id) do
    String.contains?(id, ["gpt-4", "gpt-4o"]) and not String.contains?(id, ["gpt-4-32k"])
  end

  defp supports_function_calling?(id) do
    String.contains?(id, ["gpt-3.5-turbo", "gpt-4"])
  end

  defp get_cost_tier("gpt-3.5-turbo"), do: :economy
  defp get_cost_tier("gpt-4o-mini"), do: :economy
  defp get_cost_tier("gpt-4-turbo"), do: :balanced
  defp get_cost_tier("gpt-4o"), do: :balanced
  defp get_cost_tier(id) when id in ["gpt-4", "gpt-4-32k"], do: :premium
  defp get_cost_tier(_), do: :balanced

  defp get_openai_capabilities(model_id) do
    base_capabilities = ["text", "code"]

    capabilities =
      if multimodal_model?(model_id) do
        base_capabilities ++ ["multimodal", "vision", "image_analysis"]
      else
        base_capabilities
      end

    capabilities =
      if supports_function_calling?(model_id) do
        capabilities ++ ["function_calling", "tools"]
      else
        capabilities
      end

    if String.contains?(model_id, ["gpt-4"]) do
      capabilities ++ ["analysis", "reasoning", "complex_tasks"]
    else
      capabilities
    end
  end
end
