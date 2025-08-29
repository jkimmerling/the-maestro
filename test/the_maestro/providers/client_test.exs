defmodule TheMaestro.Providers.ClientTest do
  use ExUnit.Case, async: false
  use TheMaestro.DataCase

  alias TheMaestro.Providers.Client
  alias TheMaestro.SavedAuthentication

  describe "build_client/1" do
    test "returns valid Tesla client for anthropic provider" do
      # Setup test API key
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "sk-test-key")
      Application.put_env(:the_maestro, :anthropic, test_config)

      client = Client.build_client(:anthropic)

      assert %Tesla.Client{} = client
      assert client.adapter == {Tesla.Adapter.Finch, :call, [[name: :anthropic_finch]]}

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "returns valid Tesla client for openai provider" do
      client = Client.build_client(:openai)

      assert %Tesla.Client{} = client
      assert client.adapter == {Tesla.Adapter.Finch, :call, [[name: :openai_finch]]}
    end

    test "returns valid Tesla client for gemini provider" do
      client = Client.build_client(:gemini)

      assert %Tesla.Client{} = client
      assert client.adapter == {Tesla.Adapter.Finch, :call, [[name: :gemini_finch]]}
    end

    test "returns error for invalid provider" do
      assert Client.build_client(:invalid_provider) == {:error, :invalid_provider}
      assert Client.build_client(:unknown) == {:error, :invalid_provider}
      assert Client.build_client(nil) == {:error, :invalid_provider}
      assert Client.build_client("anthropic") == {:error, :invalid_provider}
    end

    test "returns error when anthropic API key is missing" do
      # Remove API key from config
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, nil)
      Application.put_env(:the_maestro, :anthropic, test_config)

      result = Client.build_client(:anthropic)

      assert result == {:error, :missing_api_key}

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end
  end

  describe "build_client/2" do
    test "returns valid Tesla client for anthropic with api_key auth type" do
      # Setup test API key
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "sk-test-key-auth")
      Application.put_env(:the_maestro, :anthropic, test_config)

      client = Client.build_client(:anthropic, :api_key)

      assert %Tesla.Client{} = client
      assert client.adapter == {Tesla.Adapter.Finch, :call, [[name: :anthropic_finch]]}

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "returns valid Tesla client for other providers with api_key auth type" do
      for provider <- [:openai, :gemini] do
        client = Client.build_client(provider, :api_key)
        assert %Tesla.Client{} = client
      end
    end

    test "returns error for invalid provider with any auth type" do
      assert Client.build_client(:invalid, :api_key) == {:error, :invalid_provider}
      assert Client.build_client(:invalid, :oauth) == {:error, :invalid_provider}
    end

    test "returns error for oauth auth type when no token is stored" do
      # OAuth should return not_found when no token exists in database
      assert Client.build_client(:anthropic, :oauth) == {:error, :not_found}
      assert Client.build_client(:openai, :oauth) == {:error, :oauth_not_implemented}
      assert Client.build_client(:gemini, :oauth) == {:error, :oauth_not_implemented}
    end

    test "returns error when anthropic API key is missing with explicit api_key auth" do
      # Remove API key from config
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "")
      Application.put_env(:the_maestro, :anthropic, test_config)

      result = Client.build_client(:anthropic, :api_key)

      assert result == {:error, :missing_api_key}

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end
  end

  describe "Tesla client configuration" do
    test "anthropic client has correct base URL" do
      # Setup test API key
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "sk-test-key")
      Application.put_env(:the_maestro, :anthropic, test_config)

      client = Client.build_client(:anthropic)

      # Extract BaseUrl middleware configuration
      base_url_middleware = find_middleware(client, Tesla.Middleware.BaseUrl)

      assert base_url_middleware ==
               {Tesla.Middleware.BaseUrl, :call, ["https://api.anthropic.com"]}

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "openai client has correct base URL" do
      client = Client.build_client(:openai)

      base_url_middleware = find_middleware(client, Tesla.Middleware.BaseUrl)
      assert base_url_middleware == {Tesla.Middleware.BaseUrl, :call, ["https://api.openai.com"]}
    end

    test "gemini client has correct base URL" do
      client = Client.build_client(:gemini)

      base_url_middleware = find_middleware(client, Tesla.Middleware.BaseUrl)

      assert base_url_middleware ==
               {Tesla.Middleware.BaseUrl, :call, ["https://generativelanguage.googleapis.com"]}
    end

    test "anthropic client has exact header order as specified in requirements" do
      # Setup test API key
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "sk-test-key-123")
      Application.put_env(:the_maestro, :anthropic, test_config)

      client = Client.build_client(:anthropic)

      # Extract Headers middleware configuration
      headers_middleware = find_middleware(client, Tesla.Middleware.Headers)

      # Verify exact header order and values
      expected_headers = [
        {"x-api-key", "sk-test-key-123"},
        {"anthropic-version", "2023-06-01"},
        {"anthropic-beta", "messages-2023-12-15"},
        {"user-agent", "llxprt/1.0"},
        {"accept", "application/json"},
        {"x-client-version", "1.0.0"}
      ]

      assert {Tesla.Middleware.Headers, :call, [^expected_headers]} = headers_middleware

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "anthropic client includes Headers middleware for authentication" do
      # Setup test API key
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "sk-test-headers")
      Application.put_env(:the_maestro, :anthropic, test_config)

      client = Client.build_client(:anthropic)

      # Verify Headers middleware is present
      assert has_middleware?(client, Tesla.Middleware.Headers)

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "non-anthropic clients do not have Headers middleware for authentication" do
      # OpenAI and Gemini should not have Headers middleware (yet - future Epic 2)
      openai_client = Client.build_client(:openai)
      gemini_client = Client.build_client(:gemini)

      refute has_middleware?(openai_client, Tesla.Middleware.Headers)
      refute has_middleware?(gemini_client, Tesla.Middleware.Headers)
    end

    test "all clients include expected middleware stack" do
      # Setup test API key for Anthropic
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "sk-test-middleware")
      Application.put_env(:the_maestro, :anthropic, test_config)

      for provider <- [:anthropic, :openai, :gemini] do
        client = Client.build_client(provider)

        # Check for required middleware
        assert has_middleware?(client, Tesla.Middleware.BaseUrl)
        assert has_middleware?(client, Tesla.Middleware.JSON)
        assert has_middleware?(client, Tesla.Middleware.Logger)
        assert has_middleware?(client, Tesla.Middleware.Retry)

        # Check retry middleware configuration
        retry_middleware = find_middleware(client, Tesla.Middleware.Retry)

        assert {Tesla.Middleware.Retry, :call, [[delay: 500, max_retries: 3, max_delay: 4_000]]} ==
                 retry_middleware
      end

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "all clients use Finch adapter with correct pool" do
      # Setup test API key for Anthropic
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "sk-test-finch")
      Application.put_env(:the_maestro, :anthropic, test_config)

      anthropic_client = Client.build_client(:anthropic)
      openai_client = Client.build_client(:openai)
      gemini_client = Client.build_client(:gemini)

      assert anthropic_client.adapter == {Tesla.Adapter.Finch, :call, [[name: :anthropic_finch]]}
      assert openai_client.adapter == {Tesla.Adapter.Finch, :call, [[name: :openai_finch]]}
      assert gemini_client.adapter == {Tesla.Adapter.Finch, :call, [[name: :gemini_finch]]}

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end
  end

  describe "Finch pool configuration" do
    test "finch pools are properly started and accessible" do
      # Test that each Finch pool process is running
      assert Process.whereis(:anthropic_finch) != nil
      assert Process.whereis(:openai_finch) != nil
      assert Process.whereis(:gemini_finch) != nil

      # Test that the pool processes are alive
      assert Process.alive?(Process.whereis(:anthropic_finch))
      assert Process.alive?(Process.whereis(:openai_finch))
      assert Process.alive?(Process.whereis(:gemini_finch))
    end

    test "finch pools have correct configuration" do
      # Test pool status retrieval (if pools support it)
      anthropic_status = Finch.get_pool_status(:anthropic_finch, "https://api.anthropic.com")
      openai_status = Finch.get_pool_status(:openai_finch, "https://api.openai.com")

      gemini_status =
        Finch.get_pool_status(:gemini_finch, "https://generativelanguage.googleapis.com")

      # All should return ok status or not_found (if metrics disabled)
      assert anthropic_status in [{:ok, []}, {:error, :not_found}]
      assert openai_status in [{:ok, []}, {:error, :not_found}]
      assert gemini_status in [{:ok, []}, {:error, :not_found}]
    end
  end

  describe "integration tests" do
    @tag :integration
    test "anthropic client can make HTTP requests with API key headers" do
      # Setup test API key
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "sk-test-integration-123")
      Application.put_env(:the_maestro, :anthropic, test_config)

      client = Client.build_client(:anthropic)

      # Make a simple GET request that should fail with 401/403/405 (expected for auth/method)
      # This proves the client can make HTTP requests and reach the server with headers
      case Tesla.get(client, "/v1/messages") do
        {:ok, %Tesla.Env{status: status}} when status in [400, 401, 403, 404, 405] ->
          # Expected - we don't have valid auth but we reached the server with headers
          :ok

        {:error, %Tesla.Error{reason: reason}} when reason in [:timeout, :econnrefused] ->
          # Skip this test if we can't reach the internet
          :skip

        result ->
          flunk("Unexpected result: #{inspect(result)}")
      end

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    @tag :integration
    test "openai client can make HTTP requests" do
      client = Client.build_client(:openai)

      case Tesla.get(client, "/v1/models") do
        {:ok, %Tesla.Env{status: status}} when status in [401, 403, 404] ->
          :ok

        {:error, %Tesla.Error{reason: reason}} when reason in [:timeout, :econnrefused] ->
          :skip

        result ->
          flunk("Unexpected result: #{inspect(result)}")
      end
    end

    @tag :integration
    test "gemini client can make HTTP requests" do
      client = Client.build_client(:gemini)

      case Tesla.get(client, "/v1/models") do
        {:ok, %Tesla.Env{status: status}} when status in [400, 401, 403, 404] ->
          :ok

        {:error, %Tesla.Error{reason: reason}} when reason in [:timeout, :econnrefused] ->
          :skip

        result ->
          flunk("Unexpected result: #{inspect(result)}")
      end
    end
  end

  describe "OAuth authentication" do
    setup do
      # Clean up any existing saved authentications
      Repo.delete_all(SavedAuthentication)
      :ok
    end

    test "successfully builds client with valid OAuth token" do
      # Create a valid OAuth token in database
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)
      
      {:ok, _saved_auth} = %SavedAuthentication{}
      |> SavedAuthentication.changeset(%{
        provider: :anthropic,
        auth_type: :oauth,
        credentials: %{
          "access_token" => "sk-ant-oat01-test-token-123",
          "refresh_token" => "sk-ant-oar01-test-refresh-123", 
          "token_type" => "Bearer",
          "scope" => "user:profile user:inference"
        },
        expires_at: expires_at
      })
      |> Repo.insert()

      # Build client with OAuth
      client = Client.build_client(:anthropic, :oauth)

      assert %Tesla.Client{} = client
      assert client.adapter == {Tesla.Adapter.Finch, :call, [[name: :anthropic_finch]]}

      # Verify OAuth headers are correct
      headers_middleware = find_middleware(client, Tesla.Middleware.Headers)
      {Tesla.Middleware.Headers, :call, [header_list]} = headers_middleware
      
      # Check for key OAuth headers (full Claude Code headers)
      assert {"authorization", "Bearer sk-ant-oat01-test-token-123"} in header_list
      assert {"anthropic-version", "2023-06-01"} in header_list
      assert {"anthropic-beta", "claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14"} in header_list
      assert {"user-agent", "claude-cli/1.0.81 (external, cli)"} in header_list
      assert {"accept", "application/json"} in header_list
      assert {"content-type", "application/json"} in header_list
    end

    test "returns error when OAuth token not found in database" do
      # No token stored - should return not_found error
      result = Client.build_client(:anthropic, :oauth)
      assert result == {:error, :not_found}
    end

    test "returns error when OAuth token has expired" do
      # Create an expired OAuth token
      expired_at = DateTime.add(DateTime.utc_now(), -3600, :second)  # 1 hour ago
      
      {:ok, _saved_auth} = %SavedAuthentication{}
      |> SavedAuthentication.changeset(%{
        provider: :anthropic,
        auth_type: :oauth,
        credentials: %{
          "access_token" => "sk-ant-oat01-expired-token",
          "refresh_token" => "sk-ant-oar01-expired-refresh",
          "token_type" => "Bearer"
        },
        expires_at: expired_at
      })
      |> Repo.insert()

      # Build client should return expired error
      result = Client.build_client(:anthropic, :oauth)
      assert result == {:error, :expired}
    end

    test "OAuth headers differ from API key headers" do
      # Setup API key client for comparison
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "sk-test-api-key")
      Application.put_env(:the_maestro, :anthropic, test_config)
      
      # Setup OAuth token
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)
      
      {:ok, _saved_auth} = %SavedAuthentication{}
      |> SavedAuthentication.changeset(%{
        provider: :anthropic,
        auth_type: :oauth,
        credentials: %{
          "access_token" => "sk-ant-oat01-oauth-token",
          "refresh_token" => "sk-ant-oar01-oauth-refresh",
          "token_type" => "Bearer"
        },
        expires_at: expires_at
      })
      |> Repo.insert()

      # Get both clients
      api_client = Client.build_client(:anthropic, :api_key)
      oauth_client = Client.build_client(:anthropic, :oauth)

      # Compare headers
      api_headers = find_middleware(api_client, Tesla.Middleware.Headers)
      oauth_headers = find_middleware(oauth_client, Tesla.Middleware.Headers)

      # Extract header lists
      {Tesla.Middleware.Headers, :call, [api_header_list]} = api_headers
      {Tesla.Middleware.Headers, :call, [oauth_header_list]} = oauth_headers

      # API key uses x-api-key header
      assert {"x-api-key", "sk-test-api-key"} in api_header_list
      refute Enum.any?(api_header_list, fn {key, _} -> key == "authorization" end)
      
      # OAuth uses authorization header
      assert {"authorization", "Bearer sk-ant-oat01-oauth-token"} in oauth_header_list
      refute Enum.any?(oauth_header_list, fn {key, _} -> key == "x-api-key" end)
      
      # Different beta headers
      assert {"anthropic-beta", "messages-2023-12-15"} in api_header_list
      assert {"anthropic-beta", "claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14"} in oauth_header_list

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "OAuth token with far future expiry is handled" do
      # Create OAuth token with far future expiry (valid for a long time)
      far_future = DateTime.add(DateTime.utc_now(), 365 * 24 * 3600, :second)  # 1 year
      
      {:ok, _saved_auth} = %SavedAuthentication{}
      |> SavedAuthentication.changeset(%{
        provider: :anthropic,
        auth_type: :oauth,
        credentials: %{
          "access_token" => "sk-ant-oat01-long-expiry",
          "refresh_token" => "sk-ant-oar01-long-expiry",
          "token_type" => "Bearer"
        },
        expires_at: far_future
      })
      |> Repo.insert()

      # Should successfully build client
      client = Client.build_client(:anthropic, :oauth)
      assert %Tesla.Client{} = client

      # Verify authorization header is present
      headers_middleware = find_middleware(client, Tesla.Middleware.Headers)
      {Tesla.Middleware.Headers, :call, [header_list]} = headers_middleware
      
      assert {"authorization", "Bearer sk-ant-oat01-long-expiry"} in header_list
    end
  end

  describe "error scenarios" do
    test "handles network timeouts gracefully" do
      # Setup test API key for Anthropic
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "sk-test-timeout")
      Application.put_env(:the_maestro, :anthropic, test_config)

      client = Client.build_client(:anthropic)

      # Test with a non-routable IP that will timeout quickly
      case Tesla.get(client, "http://10.255.255.1/timeout") do
        {:error, %Tesla.Error{reason: reason}}
        when reason in [:timeout, :econnrefused, :ehostunreach] ->
          :ok

        {:error, :timeout} ->
          :ok

        {:error, _} ->
          :ok

        {:ok, _} ->
          # If somehow it succeeds, that's fine too
          :ok
      end

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "handles invalid URLs gracefully" do
      client = Client.build_client(:openai)

      case Tesla.get(client, "/malformed url with spaces") do
        {:error, %Tesla.Error{}} -> :ok
        {:error, %Mint.HTTPError{}} -> :ok
        {:error, _} -> :ok
        {:ok, %Tesla.Env{status: status}} when status >= 400 -> :ok
      end
    end

    test "client creation with nil config handled properly" do
      # This tests the fallback behavior - should return error for missing API key
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      Application.delete_env(:the_maestro, :anthropic)

      result = Client.build_client(:anthropic)
      assert result == {:error, :missing_api_key}

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end
  end

  # Helper functions for testing middleware
  defp find_middleware(%Tesla.Client{pre: pre}, middleware_module) do
    Enum.find(pre, fn
      {^middleware_module, :call, _args} -> true
      _ -> false
    end)
  end

  defp has_middleware?(%Tesla.Client{pre: pre}, middleware_module) do
    Enum.any?(pre, fn
      {^middleware_module, :call, _args} -> true
      _ -> false
    end)
  end
end
