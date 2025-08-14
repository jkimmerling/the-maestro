defmodule TheMaestroWeb.ProvidersController do
  @moduledoc """
  API controller for provider management operations.

  Provides REST endpoints for:
  - Listing available providers
  - Initiating authentication flows
  - Fetching provider models
  - Testing provider connections
  """
  use TheMaestroWeb, :controller

  alias TheMaestro.Providers.Auth
  alias TheMaestro.Providers.{Anthropic, Gemini, OpenAI}

  require Logger

  @doc """
  GET /api/providers

  Lists all available providers with their supported authentication methods
  and current status.
  """
  def index(conn, _params) do
    providers = Auth.get_available_providers()

    provider_list =
      Enum.map(providers, fn {provider, methods} ->
        %{
          id: provider,
          name: provider_display_name(provider),
          description: provider_description(provider),
          icon: provider_icon(provider),
          color: provider_color(provider),
          auth_methods: methods,
          status: get_provider_status(provider)
        }
      end)

    json(conn, %{providers: provider_list})
  end

  @doc """
  POST /api/providers/:provider/auth

  Initiates authentication flow for the specified provider.
  Expects JSON body with:
  - method: "oauth" or "api_key"
  - params: method-specific parameters
  """
  def auth(conn, %{"provider" => provider_string} = _params) do
    provider = String.to_existing_atom(provider_string)

    case get_request_body(conn) do
      {:ok, %{"method" => "oauth"} = auth_params} ->
        initiate_oauth_auth(conn, provider, auth_params)

      {:ok, %{"method" => "api_key"} = auth_params} ->
        initiate_api_key_auth(conn, provider, auth_params)

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid request body", reason: reason})
    end
  rescue
    ArgumentError ->
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid provider: #{provider_string}"})
  end

  @doc """
  GET /api/providers/:provider/models

  Fetches available models for the specified provider.
  Requires valid authentication credentials in session or headers.
  """
  def models(conn, %{"provider" => provider_string}) do
    provider = String.to_existing_atom(provider_string)
    user_id = get_user_id(conn)

    case get_provider_models(provider, user_id) do
      {:ok, models} ->
        json(conn, %{models: models})

      {:error, :not_authenticated} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required to fetch models"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to fetch models", reason: inspect(reason)})
    end
  rescue
    ArgumentError ->
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid provider: #{provider_string}"})
  end

  @doc """
  POST /api/providers/:provider/test

  Tests connection to the specified provider.
  Expects JSON body with credentials or uses stored credentials.
  """
  def test(conn, %{"provider" => provider_string}) do
    provider = String.to_existing_atom(provider_string)
    user_id = get_user_id(conn)

    case test_provider_connection(provider, user_id, conn) do
      {:ok, test_result} ->
        json(conn, %{status: "success", result: test_result})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", error: inspect(reason)})
    end
  rescue
    ArgumentError ->
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid provider: #{provider_string}"})
  end

  # Private functions

  defp get_request_body(conn) do
    case Jason.decode(conn.assigns[:raw_body] || "") do
      {:ok, body} ->
        {:ok, body}

      {:error, _} ->
        # Try to read from params if not in assigns
        case conn.body_params do
          %{} = params when map_size(params) > 0 -> {:ok, params}
          _ -> {:error, "Invalid JSON body"}
        end
    end
  end

  defp initiate_oauth_auth(conn, provider, auth_params) do
    redirect_uri = Map.get(auth_params, "redirect_uri", get_default_oauth_redirect())
    options = %{redirect_uri: redirect_uri}

    case Auth.initiate_oauth_flow(provider, options) do
      {:ok, auth_url} ->
        json(conn, %{
          status: "success",
          auth_url: auth_url,
          method: "oauth"
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          status: "error",
          error: "Failed to initiate OAuth flow",
          reason: inspect(reason)
        })
    end
  end

  defp initiate_api_key_auth(conn, provider, auth_params) do
    api_key = Map.get(auth_params, "api_key")
    user_id = get_user_id(conn)

    if api_key && user_id do
      case Auth.authenticate(provider, :api_key, %{api_key: api_key}, user_id) do
        {:ok, result} ->
          json(conn, %{
            status: "success",
            method: "api_key",
            provider: result.provider
          })

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{
            status: "error",
            error: "API key authentication failed",
            reason: inspect(reason)
          })
      end
    else
      conn
      |> put_status(:bad_request)
      |> json(%{
        status: "error",
        error: "API key and user authentication required"
      })
    end
  end

  defp get_provider_models(provider, user_id) do
    case Auth.get_credentials(user_id, provider) do
      {:ok, auth_result} ->
        fetch_models_from_provider(provider, auth_result.credentials)

      {:error, _} ->
        {:error, :not_authenticated}
    end
  end

  defp fetch_models_from_provider(provider, credentials) do
    # Determine auth type from credentials structure
    auth_type =
      case credentials do
        %{auth_method: method} -> method
        %{api_key: _} -> :api_key
        %{access_token: _} -> :oauth
        _ -> :api_key
      end

    # Create proper auth context
    auth_context = %{
      type: auth_type,
      credentials: credentials,
      config: %{provider: provider}
    }

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

  defp test_provider_connection(provider, user_id, conn) do
    case get_request_body(conn) do
      {:ok, %{"credentials" => test_credentials}} ->
        # Test with provided credentials
        test_with_credentials(provider, test_credentials)

      _ ->
        # Test with stored credentials
        case Auth.get_credentials(user_id, provider) do
          {:ok, auth_result} ->
            test_with_auth_result(provider, auth_result)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp test_with_credentials(provider, credentials) do
    # Simple health check - try to list models
    case fetch_models_from_provider(provider, credentials) do
      {:ok, models} when is_list(models) ->
        {:ok,
         %{
           connection: :healthy,
           models_available: length(models),
           tested_at: DateTime.utc_now()
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_with_auth_result(provider, auth_result) do
    test_with_credentials(provider, auth_result.credentials)
  end

  defp get_provider_status(provider) do
    # Simple health check for provider availability
    case provider do
      :anthropic -> :available
      :google -> :available
      :openai -> :available
      _ -> :unknown
    end
  end

  defp get_user_id(conn) do
    # Try to get user_id from session or authentication
    case get_session(conn, "current_user") do
      %{"id" => user_id} ->
        user_id

      user_id when is_binary(user_id) ->
        user_id

      _ ->
        # For development, we could use a default user
        case Application.get_env(:the_maestro, :require_authentication, true) do
          false -> "anonymous_user"
          true -> nil
        end
    end
  end

  defp get_default_oauth_redirect do
    "http://localhost:4000/oauth2callback"
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
end
