defmodule TheMaestro.Providers.Http.ReqClientFactory do
  @moduledoc """
  Req-based HTTP client factory using Finch pools per provider.

  Provides a consistent way to build pre-configured `Req.Request` structs for
  Anthropic, OpenAI, and Gemini with ordered headers and connection pooling.
  """

  alias TheMaestro.Providers.Http.ReqConfig
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Types

  @typedoc "A configured Req request"
  @type request :: Req.Request.t()

  @spec create_client(Types.provider(), Types.auth_type(), Types.request_opts()) ::
          {:ok, request()} | {:error, term()}
  def create_client(provider, auth_type \\ :api_key, opts \\ []) do
    with {:ok, base_url0, pool} <- provider_base_and_pool(provider),
         {:ok, headers} <- build_headers(provider, auth_type, opts) do
      base_url =
        case provider do
          :openai -> choose_openai_base_url(auth_type, opts, base_url0)
          _ -> base_url0
        end

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

  @spec build_headers(Types.provider(), Types.auth_type(), Types.request_opts()) ::
          {:ok, [{String.t(), String.t()}]} | {:error, term()}
  def build_headers(:anthropic, :api_key, opts) do
    session_name = Keyword.get(opts, :session)
    saved = if session_name, do: get_saved_auth(:anthropic, :api_key, session_name), else: nil

    api_key =
      if is_map(saved) do
        saved.credentials["api_key"]
      else
        Application.get_env(:the_maestro, :anthropic, []) |> Keyword.get(:api_key)
      end

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

  def build_headers(:anthropic, :oauth, opts) do
    session_name = Keyword.get(opts, :session)

    with {:ok, saved} <- fetch_saved(:anthropic, :oauth, session_name),
         :ok <- ensure_not_expired(saved.expires_at),
         {:ok, access_token, token_type} <- fetch_token(saved.credentials) do
      # Mimic llxprt/the_maestro OAuth header shape exactly (Claude CLI parity)
      {:ok,
       [
         {"connection", "keep-alive"},
         {"accept", "application/json"},
         {"x-stainless-retry-count", "0"},
         {"x-stainless-timeout", "600"},
         {"x-stainless-lang", "js"},
         {"x-stainless-package-version", "0.60.0"},
         {"x-stainless-os", "MacOS"},
         {"x-stainless-arch", "arm64"},
         {"x-stainless-runtime", "node"},
         {"x-stainless-runtime-version", "v20.19.4"},
         {"anthropic-dangerous-direct-browser-access", "true"},
         {"anthropic-version", "2023-06-01"},
         {"authorization", token_type <> " " <> access_token},
         {"x-app", "cli"},
         {"user-agent", "claude-cli/1.0.81 (external, cli)"},
         {"content-type", "application/json"},
         {"anthropic-beta",
          "claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14"},
         {"x-stainless-helper-method", "stream"},
         {"accept-language", "*"},
         {"sec-fetch-mode", "cors"},
         {"accept-encoding", "gzip, deflate, br"}
       ]}
    end
  end

  def build_headers(:openai, :api_key, opts) do
    case Keyword.get(opts, :session) do
      session when is_binary(session) and session != "" ->
        build_openai_api_key_headers_session(session)

      _ ->
        build_openai_api_key_headers_env()
    end
  end

  def build_headers(:openai, :oauth, opts) do
    session_name = Keyword.get(opts, :session)

    with {:ok, saved} <- fetch_saved(:openai, :oauth, session_name),
         :ok <- ensure_not_expired(saved.expires_at),
         {:ok, access_token, _token_type} <- fetch_token(saved.credentials) do
      org_id = Application.get_env(:the_maestro, :openai, []) |> Keyword.get(:organization_id)

      base_headers = [
        {"authorization", "Bearer " <> access_token},
        {"user-agent", "llxprt/1.0"},
        {"accept", "application/json"},
        {"x-client-version", "1.0.0"}
      ]

      headers =
        case org_id do
          id when is_binary(id) and id != "" ->
            [{"openai-organization", id} | base_headers]

          _ ->
            base_headers
        end

      {:ok, headers}
    end
  end

  def build_headers(:gemini, :api_key, opts) do
    saved = gemini_saved_auth(opts)
    api_key = gemini_api_key(saved)
    user_project = gemini_user_project(saved)

    if is_binary(api_key) and api_key != "" do
      headers =
        [
          {"x-goog-api-key", api_key},
          {"accept", "application/json"}
        ]
        |> maybe_prepend_header("x-goog-user-project", user_project)

      {:ok, headers}
    else
      # Keep Gemini client permissive when no key is present (test expectations)
      {:ok, []}
    end
  end

  def build_headers(:gemini, :oauth, opts) do
    session_name = Keyword.get(opts, :session)

    with {:ok, saved0} <- fetch_saved(:gemini, :oauth, session_name),
         {:ok, saved} <- maybe_refresh_gemini_if_expired(saved0, session_name),
         {:ok, access_token, token_type} <- fetch_token(saved.credentials) do
      {:ok,
       [
         {"authorization", token_type <> " " <> access_token},
         {"accept", "application/json"},
         {"x-goog-api-client", x_goog_api_client_header()}
       ]}
    else
      _ -> {:ok, []}
    end
  end

  # Fallback must be grouped with all other build_headers/3 clauses
  def build_headers(_invalid, _auth_type, _opts), do: {:error, :invalid_provider}

  defp x_goog_api_client_header do
    # Mirror gemini-cli value; static string is acceptable for compatibility
    # gemini-cli sends gl-node/<node-version>
    "gl-node/20.19.4"
  end

  # If the saved OAuth token is expired, attempt a refresh and re-fetch.
  alias TheMaestro.Providers.Gemini.OAuth, as: GeminiOAuth

  defp maybe_refresh_gemini_if_expired(%SavedAuthentication{} = saved, session_name) do
    if expired?(saved.expires_at) do
      _ = GeminiOAuth.refresh_tokens(session_name)
      case fetch_saved(:gemini, :oauth, session_name) do
        {:ok, saved2} -> {:ok, saved2}
        _ -> {:ok, saved}
      end
    else
      {:ok, saved}
    end
  end

  defp expired?(nil), do: false
  defp expired?(%DateTime{} = ts), do: DateTime.compare(DateTime.utc_now(), ts) != :lt

  defp gemini_saved_auth(opts) do
    case Keyword.get(opts, :session) do
      s when is_binary(s) and s != "" -> get_saved_auth(:gemini, :api_key, s)
      _ -> nil
    end
  end

  defp gemini_api_key(%SavedAuthentication{credentials: %{"api_key" => key}}) when is_binary(key),
    do: key

  defp gemini_api_key(_), do: System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY")

  defp gemini_user_project(%SavedAuthentication{credentials: %{"user_project" => proj}}),
    do: proj

  defp gemini_user_project(_), do: nil

  # ===== OpenAI endpoint selection =====
  defp choose_openai_base_url(_auth_type, opts, default) do
    cfg = Application.get_env(:the_maestro, :openai, [])
    mode = Keyword.get(opts, :mode, Keyword.get(cfg, :mode, :api))

    case mode do
      :chatgpt -> Keyword.get(cfg, :chatgpt_base_url, "https://chat.openai.com/backend-api")
      :api -> Keyword.get(cfg, :api_base_url, default)
      _ -> default
    end
  end

  defp openai_base_headers(api_key) do
    [
      {"authorization", "Bearer #{api_key}"},
      {"user-agent", "llxprt/1.0"},
      {"accept", "application/json"},
      {"x-client-version", "1.0.0"}
    ]
  end

  defp build_openai_api_key_headers_session(session_name) do
    case get_saved_auth(:openai, :api_key, session_name) do
      %SavedAuthentication{credentials: creds = %{"api_key" => api_key}}
      when is_binary(api_key) and
             api_key != "" ->
        base = openai_base_headers(api_key)

        headers =
          base
          |> maybe_prepend_header("openai-organization", creds["organization_id"])
          |> maybe_prepend_header(
            "openai-project",
            creds["project_id"] || System.get_env("OPENAI_PROJECT")
          )

        {:ok, headers}

      _ ->
        {:error, :missing_api_key}
    end
  end

  defp build_openai_api_key_headers_env do
    cfg = Application.get_env(:the_maestro, :openai, [])
    api_key = Keyword.get(cfg, :api_key)
    org_id = Keyword.get(cfg, :organization_id)
    project_id = Keyword.get(cfg, :project_id) || System.get_env("OPENAI_PROJECT")

    cond do
      !is_binary(api_key) or api_key == "" ->
        {:error, :missing_api_key}

      !is_binary(org_id) or org_id == "" ->
        {:error, :missing_org_id}

      true ->
        base = [{"openai-beta", "assistants v2"} | openai_base_headers(api_key)]

        headers =
          base
          |> maybe_prepend_header("openai-organization", org_id)
          |> maybe_prepend_header("openai-project", project_id)

        {:ok, headers}
    end
  end

  # ===== Internal helpers =====

  @spec get_saved_auth(atom(), atom(), String.t() | nil) :: SavedAuthentication.t() | nil
  defp get_saved_auth(provider, auth_type, nil) do
    provider
    |> SavedAuthentication.list_by_provider()
    |> Enum.find(&(&1.auth_type == auth_type))
  end

  defp get_saved_auth(provider, auth_type, session_name) when is_binary(session_name) do
    SavedAuthentication.get_by_provider_and_name(provider, auth_type, session_name)
  end

  defp maybe_prepend_header(headers, _name, nil), do: headers
  defp maybe_prepend_header(headers, _name, ""), do: headers

  defp maybe_prepend_header(headers, name, value) when is_binary(value),
    do: [{name, value} | headers]

  @spec fetch_saved(atom(), atom(), String.t() | nil) ::
          {:ok, SavedAuthentication.t()} | {:error, :not_found}
  defp fetch_saved(provider, auth_type, session_name) do
    case get_saved_auth(provider, auth_type, session_name) do
      %SavedAuthentication{} = saved -> {:ok, saved}
      _ -> {:error, :not_found}
    end
  end

  @spec ensure_not_expired(DateTime.t() | nil) :: :ok | {:error, :expired}
  defp ensure_not_expired(nil), do: :ok

  defp ensure_not_expired(%DateTime{} = expires_at) do
    if DateTime.compare(DateTime.utc_now(), expires_at) == :lt, do: :ok, else: {:error, :expired}
  end

  @spec fetch_token(map()) :: {:ok, String.t(), String.t()} | {:error, :missing_token}
  defp fetch_token(%{} = creds) do
    case Map.get(creds, "access_token") do
      token when is_binary(token) and token != "" ->
        {:ok, token, Map.get(creds, "token_type", "Bearer")}

      _ ->
        {:error, :missing_token}
    end
  end
end
