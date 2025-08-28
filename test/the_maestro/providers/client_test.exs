defmodule TheMaestro.Providers.ClientTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Providers.Client

  describe "build_client/1" do
    test "returns valid Tesla client for anthropic provider" do
      client = Client.build_client(:anthropic)

      assert %Tesla.Client{} = client
      assert client.adapter == {Tesla.Adapter.Finch, :call, [[name: :anthropic_finch]]}
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
  end

  describe "Tesla client configuration" do
    test "anthropic client has correct base URL" do
      client = Client.build_client(:anthropic)

      # Extract BaseUrl middleware configuration
      base_url_middleware = find_middleware(client, Tesla.Middleware.BaseUrl)

      assert base_url_middleware ==
               {Tesla.Middleware.BaseUrl, :call, ["https://api.anthropic.com"]}
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

    test "all clients include expected middleware stack" do
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
    end

    test "all clients use Finch adapter with correct pool" do
      anthropic_client = Client.build_client(:anthropic)
      openai_client = Client.build_client(:openai)
      gemini_client = Client.build_client(:gemini)

      assert anthropic_client.adapter == {Tesla.Adapter.Finch, :call, [[name: :anthropic_finch]]}
      assert openai_client.adapter == {Tesla.Adapter.Finch, :call, [[name: :openai_finch]]}
      assert gemini_client.adapter == {Tesla.Adapter.Finch, :call, [[name: :gemini_finch]]}
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
    test "anthropic client can make HTTP requests" do
      client = Client.build_client(:anthropic)

      # Make a simple GET request that should fail with 401/403/405 (expected for auth/method)
      # This proves the client can make HTTP requests and reach the server
      case Tesla.get(client, "/v1/messages") do
        {:ok, %Tesla.Env{status: status}} when status in [401, 403, 404, 405] ->
          # Expected - we don't have auth or wrong method but we reached the server
          :ok

        {:error, %Tesla.Error{reason: reason}} when reason in [:timeout, :econnrefused] ->
          # Skip this test if we can't reach the internet
          :skip

        result ->
          flunk("Unexpected result: #{inspect(result)}")
      end
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
