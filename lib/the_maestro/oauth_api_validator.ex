defmodule TheMaestro.OAuthAPIValidator do
  @moduledoc """
  CRITICAL: OAuth API Validator for ensuring ZERO drift in API calls.

  This module captures and validates that OAuth API calls remain EXACTLY
  the same before and after any refactoring. Each provider has strict
  proprietary requirements that MUST be maintained.
  """

  require Logger

  @capture_dir "oauth_api_baseline"

  # CRITICAL OAuth Requirements that MUST NOT change
  @anthropic_oauth_requirements %{
    headers: [
      # MUST have these exact headers for Claude Code compatibility
      "connection: keep-alive",
      "accept: application/json",
      "x-stainless-retry-count: 0",
      "x-stainless-timeout: 600",
      "x-stainless-lang: js",
      "x-stainless-package-version: 0.60.0",
      "x-stainless-os: MacOS",
      "x-stainless-arch: arm64",
      "x-stainless-runtime: node",
      # Version may vary but field must exist
      "x-stainless-runtime-version",
      "anthropic-dangerous-direct-browser-access: true",
      "anthropic-version: 2023-06-01",
      # Must have Bearer token
      "authorization: Bearer",
      "x-app: cli",
      # Must contain claude-cli
      "user-agent: claude-cli",
      "content-type: application/json",
      # Must have all beta features
      "anthropic-beta",
      "x-stainless-helper-method: stream",
      "accept-language: *",
      "sec-fetch-mode: cors",
      "accept-encoding: gzip, deflate, br"
    ],
    endpoints: [
      # OAuth uses beta endpoint
      "/v1/messages?beta=true",
      "/v1/complete"
    ],
    critical_fields: %{
      # OAuth must have system blocks
      system_blocks: true,
      # OAuth must have tools
      claude_code_tools: true,
      # OAuth must have user_id in metadata
      user_metadata: true
    }
  }

  @openai_oauth_requirements %{
    headers: [
      # MUST be Bearer token
      "authorization: Bearer",
      "user-agent: llxprt/1.0",
      "accept: application/json",
      "x-client-version: 1.0.0"
      # Optional: openai-organization (if configured)
    ],
    endpoints: [
      "/v1/chat/completions",
      "/v1/models"
    ],
    base_urls: [
      "https://api.openai.com",
      # ChatGPT mode
      "https://chat.openai.com/backend-api"
    ]
  }

  @gemini_oauth_requirements %{
    headers: [
      # MUST be Bearer token
      "authorization: Bearer",
      "accept: application/json",
      # MUST have API client identifier
      "x-goog-api-client"
    ],
    endpoints: [
      "/v1beta/models",
      "/v1/models"
    ],
    base_url: "https://generativelanguage.googleapis.com"
  }

  def capture_baseline(provider, auth_type \\ :oauth) do
    File.mkdir_p!(@capture_dir)

    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    capture_file = Path.join(@capture_dir, "#{provider}_#{auth_type}_#{timestamp}.json")

    # Hook into the actual HTTP client to capture requests
    with {:ok, client} <- create_client(provider, auth_type),
         {:ok, captured} <- capture_request_details(client, provider) do
      # Save baseline
      File.write!(capture_file, Jason.encode!(captured, pretty: true))

      Logger.info("""
      ✅ Captured #{provider} #{auth_type} baseline:
      File: #{capture_file}
      Headers: #{length(captured.headers)} headers captured
      """)

      {:ok, capture_file}
    else
      error ->
        Logger.error("Failed to capture baseline: #{inspect(error)}")
        error
    end
  end

  def validate_against_baseline(provider, auth_type, baseline_file) do
    with {:ok, baseline_json} <- File.read(baseline_file),
         {:ok, baseline} <- Jason.decode(baseline_json),
         {:ok, client} <- create_client(provider, auth_type),
         {:ok, current} <- capture_request_details(client, provider) do
      # Compare headers
      header_diff = compare_headers(baseline["headers"], current.headers)

      # Compare endpoints
      endpoint_diff = compare_endpoints(baseline["endpoints"], current.endpoints)

      # Check critical requirements
      requirements_met = check_requirements(provider, current)

      if header_diff == [] and endpoint_diff == [] and requirements_met do
        {:ok, "✅ No API drift detected"}
      else
        {:error, build_error_report(header_diff, endpoint_diff, requirements_met)}
      end
    end
  end

  defp create_client(provider, auth_type) do
    # Use the actual factory to create a client
    alias TheMaestro.Providers.Http.ReqClientFactory

    # For testing, we might need a valid session
    opts =
      case get_test_session(provider, auth_type) do
        nil -> []
        session -> [session: session]
      end

    ReqClientFactory.create_client(provider, auth_type, opts)
  end

  defp capture_request_details(%Req.Request{} = client, provider) do
    # Extract all configuration from the Req client
    headers = client.headers

    captured = %{
      provider: provider,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      headers: format_headers(headers),
      base_url: client.options[:base_url],
      finch_pool: client.options[:finch],
      endpoints: get_provider_endpoints(provider),

      # Capture provider-specific details
      provider_specific: capture_provider_specific(provider, client)
    }

    {:ok, captured}
  end

  defp format_headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.sort()
  end

  defp get_provider_endpoints(:anthropic), do: Map.get(@anthropic_oauth_requirements, :endpoints)
  defp get_provider_endpoints(:openai), do: Map.get(@openai_oauth_requirements, :endpoints)
  defp get_provider_endpoints(:gemini), do: Map.get(@gemini_oauth_requirements, :endpoints)

  defp capture_provider_specific(:anthropic, _client) do
    %{
      requires_beta_endpoint: true,
      requires_claude_code_headers: true,
      requires_system_blocks: true
    }
  end

  defp capture_provider_specific(:openai, _client) do
    %{
      supports_chatgpt_mode: true,
      # Conditional based on config
      requires_org_headers: false
    }
  end

  defp capture_provider_specific(:gemini, _client) do
    %{
      requires_goog_api_client: true
    }
  end

  defp compare_headers(baseline, current) do
    baseline_set = MapSet.new(baseline)
    current_set = MapSet.new(current)

    missing = MapSet.difference(baseline_set, current_set) |> MapSet.to_list()
    added = MapSet.difference(current_set, baseline_set) |> MapSet.to_list()

    changes = []
    changes = if missing != [], do: [{:missing_headers, missing} | changes], else: changes
    changes = if added != [], do: [{:added_headers, added} | changes], else: changes

    changes
  end

  defp compare_endpoints(baseline, current) do
    baseline_set = MapSet.new(baseline)
    current_set = MapSet.new(current)

    if baseline_set == current_set do
      []
    else
      [{:endpoint_mismatch, %{baseline: baseline, current: current}}]
    end
  end

  defp check_requirements(:anthropic, captured) do
    required = @anthropic_oauth_requirements.headers
    current_headers = captured.headers

    Enum.all?(required, fn req_header ->
      [key | _] = String.split(req_header, ":")
      Enum.any?(current_headers, &String.starts_with?(&1, key))
    end)
  end

  defp check_requirements(:openai, captured) do
    required = @openai_oauth_requirements.headers
    current_headers = captured.headers

    Enum.all?(required, fn req_header ->
      [key | _] = String.split(req_header, ":")
      Enum.any?(current_headers, &String.starts_with?(&1, key))
    end)
  end

  defp check_requirements(:gemini, captured) do
    required = @gemini_oauth_requirements.headers
    current_headers = captured.headers

    Enum.all?(required, fn req_header ->
      [key | _] = String.split(req_header, ":")
      Enum.any?(current_headers, &String.starts_with?(&1, key))
    end)
  end

  defp build_error_report(header_diff, endpoint_diff, requirements_met) do
    """
    ❌ CRITICAL: API DRIFT DETECTED!

    Header Changes: #{inspect(header_diff)}
    Endpoint Changes: #{inspect(endpoint_diff)}
    Requirements Met: #{requirements_met}

    THIS IS A BREAKING CHANGE AND MUST BE REVERTED IMMEDIATELY!
    """
  end

  defp get_test_session(provider, :oauth) do
    # Try to find an existing OAuth session for testing
    alias TheMaestro.SavedAuthentication

    case SavedAuthentication.list_by_provider(provider) do
      [] ->
        nil

      auths ->
        case Enum.find(auths, &(&1.auth_type == :oauth)) do
          nil -> nil
          # Use 'name' field instead of 'session_name'
          auth -> auth.name
        end
    end
  end

  defp get_test_session(_, _), do: nil

  # Public functions for testing

  def capture_all_baselines do
    Logger.info("Capturing all OAuth baselines...")

    for provider <- [:anthropic, :openai, :gemini] do
      capture_baseline(provider, :oauth)
    end

    Logger.info("All baselines captured in #{@capture_dir}/")
  end

  def validate_all do
    Logger.info("Validating all providers against baselines...")

    # Find the most recent baseline for each provider
    for provider <- [:anthropic, :openai, :gemini] do
      pattern = Path.join(@capture_dir, "#{provider}_oauth_*.json")

      case Path.wildcard(pattern) |> List.last() do
        nil ->
          Logger.warning("No baseline found for #{provider}")

        baseline_file ->
          Logger.info("Validating #{provider} against #{baseline_file}")

          case validate_against_baseline(provider, :oauth, baseline_file) do
            {:ok, msg} -> Logger.info(msg)
            {:error, msg} -> Logger.error(msg)
          end
      end
    end
  end
end
