defmodule TheMaestro.Providers.Http.ReqClientFactory do
  @moduledoc """
  Req-based HTTP client factory using Finch pools per provider.

  Provides a consistent way to build pre-configured `Req.Request` structs for
  Anthropic, OpenAI, and Gemini with ordered headers and connection pooling.
  """

  alias TheMaestro.Providers.Http.ReqConfig
  alias TheMaestro.Types

  @typedoc "A configured Req request"
  @type request :: Req.Request.t()

  @spec create_client(Types.provider(), Types.auth_type(), keyword()) ::
          {:ok, request()} | {:error, term()}
  def create_client(provider, auth_type \\ :api_key, opts \\ []) do
    with {:ok, base_url, pool} <- provider_base_and_pool(provider),
         {:ok, headers} <- build_headers(provider, auth_type, opts) do
      # Merge base options with provider-specific options; caller opts (like :retry)
      # should take precedence when provided.
      merged_opts =
        ReqConfig.merge_with_base(
          base_url: base_url,
          finch: pool,
          headers: headers
        )

      req = Req.new(merged_opts)

      {:ok, req}
    end
  end

  @spec provider_base_and_pool(Types.provider()) ::
          {:ok, String.t(), atom()} | {:error, :invalid_provider}
  def provider_base_and_pool(:anthropic),
    do: {:ok, "https://api.anthropic.com", :anthropic_finch}

  def provider_base_and_pool(:openai),
    do: {:ok, "https://api.openai.com", :openai_finch}

  def provider_base_and_pool(:gemini),
    do: {:ok, "https://generativelanguage.googleapis.com", :gemini_finch}

  def provider_base_and_pool(_), do: {:error, :invalid_provider}

  @spec build_headers(Types.provider(), Types.auth_type(), keyword()) ::
          {:ok, [{String.t(), String.t()}]} | {:error, term()}
  def build_headers(:anthropic, :api_key, _opts) do
    api_key = Application.get_env(:the_maestro, :anthropic, []) |> Keyword.get(:api_key)

    case is_binary(api_key) and api_key != "" do
      true ->
        headers = [
          {"x-api-key", api_key},
          {"anthropic-version", "2023-06-01"},
          {"anthropic-beta", "messages-2023-12-15"},
          {"user-agent", "llxprt/1.0"},
          {"accept", "application/json"},
          {"x-client-version", "1.0.0"}
        ]

        {:ok, headers}

      false ->
        {:error, :missing_api_key}
    end
  end

  def build_headers(:anthropic, :oauth, _opts) do
    # OAuth header composition would include Bearer token pulled from DB/session
    # For Story 0.2, leave unimplemented.
    {:error, :not_implemented}
  end

  def build_headers(:openai, :api_key, _opts) do
    cfg = Application.get_env(:the_maestro, :openai, [])
    api_key = Keyword.get(cfg, :api_key)
    org_id = Keyword.get(cfg, :organization_id)

    cond do
      !is_binary(api_key) or api_key == "" ->
        {:error, :missing_api_key}

      !is_binary(org_id) or org_id == "" ->
        {:error, :missing_org_id}

      true ->
        headers = [
          {"authorization", "Bearer #{api_key}"},
          {"openai-organization", org_id},
          {"openai-beta", "assistants v2"},
          {"user-agent", "llxprt/1.0"},
          {"accept", "application/json"},
          {"x-client-version", "1.0.0"}
        ]

        {:ok, headers}
    end
  end

  def build_headers(:openai, :oauth, _opts), do: {:error, :not_implemented}

  def build_headers(:gemini, _auth_type, _opts) do
    # No default headers for Gemini at this time
    headers = []
    {:ok, headers}
  end

  def build_headers(_invalid, _auth_type, _opts), do: {:error, :invalid_provider}
end
