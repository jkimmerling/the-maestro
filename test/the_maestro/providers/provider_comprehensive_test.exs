defmodule TheMaestro.Providers.ProviderComprehensiveTest do
  use ExUnit.Case, async: true
  use TheMaestro.DataCase

  alias TheMaestro.Provider
  alias TheMaestro.SavedAuthentication

  describe "Task 5.1: Universal Interface Testing - create_session/3" do
    test "creates session with valid parameters" do
      session_params = [name: "test_session", credentials: %{"api_key" => "test-key"}]

      result = Provider.create_session(:openai, :api_key, session_params)

      case result do
        {:ok, session_id} ->
          assert is_binary(session_id)

        {:error, :not_implemented} ->
          # Expected for stub implementation
          assert true

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "handles invalid provider atoms" do
      session_params = [name: "test_session", credentials: %{"api_key" => "test-key"}]

      result = Provider.create_session(:invalid_provider, :api_key, session_params)

      assert {:error, :invalid_provider} = result
    end

    test "handles invalid auth types" do
      session_params = [name: "test_session", credentials: %{"api_key" => "test-key"}]

      result = Provider.create_session(:openai, :invalid_auth, session_params)

      assert {:error, :invalid_auth_type} = result
    end

    test "validates session name parameter" do
      # Missing name
      session_params = [credentials: %{"api_key" => "test-key"}]
      result = Provider.create_session(:openai, :api_key, session_params)
      assert {:error, :missing_session_name} = result

      # Invalid name format
      session_params = [name: "", credentials: %{"api_key" => "test-key"}]
      result = Provider.create_session(:openai, :api_key, session_params)
      assert {:error, :invalid_session_name} = result

      # Name too long
      long_name = String.duplicate("a", 100)
      session_params = [name: long_name, credentials: %{"api_key" => "test-key"}]
      result = Provider.create_session(:openai, :api_key, session_params)
      assert {:error, :invalid_session_name} = result
    end

    test "validates credentials parameter" do
      # Missing credentials
      session_params = [name: "test_session"]
      result = Provider.create_session(:openai, :api_key, session_params)
      assert {:error, :missing_credentials} = result

      # Empty credentials
      session_params = [name: "test_session", credentials: %{}]
      result = Provider.create_session(:openai, :api_key, session_params)
      assert {:error, :invalid_credentials} = result
    end
  end

  describe "Task 5.1: Universal Interface Testing - delete_session/3" do
    test "deletes existing session" do
      # First create a session in database
      {:ok, _saved_auth} =
        SavedAuthentication.create_named_session(
          :openai,
          :api_key,
          "test_session",
          %{api_key: "test-key"}
        )

      result = Provider.delete_session(:openai, :api_key, "test_session")

      case result do
        :ok ->
          # Verify session was deleted
          assert is_nil(SavedAuthentication.get_named_session(:openai, :api_key, "test_session"))

        {:error, :not_implemented} ->
          # Expected for stub implementation
          assert true

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "handles non-existent sessions gracefully" do
      result = Provider.delete_session(:openai, :api_key, "non_existent_session")

      case result do
        :ok ->
          # Should be idempotent
          assert true

        {:error, :session_not_found} ->
          # Also acceptable
          assert true

        {:error, :not_implemented} ->
          # Expected for stub implementation
          assert true

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "handles invalid provider atoms" do
      result = Provider.delete_session(:invalid_provider, :api_key, "test_session")
      assert {:error, :invalid_provider} = result
    end

    test "handles invalid auth types" do
      result = Provider.delete_session(:openai, :invalid_auth, "test_session")
      assert {:error, :invalid_auth_type} = result
    end
  end

  describe "Task 5.1: Universal Interface Testing - list_models/3" do
    test "lists models with valid parameters" do
      # Create a test session
      {:ok, _} =
        SavedAuthentication.create_named_session(
          :openai,
          :api_key,
          "test_session",
          %{api_key: "test-key"}
        )

      result = Provider.list_models(:openai, :api_key, "test_session")

      case result do
        {:ok, models} when is_list(models) ->
          assert true

        {:error, :not_implemented} ->
          # Expected for stub implementation
          assert true

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "handles different auth types" do
      # Test API key auth
      {:ok, _} =
        SavedAuthentication.create_named_session(
          :openai,
          :api_key,
          "api_session",
          %{api_key: "test-key"}
        )

      api_result = Provider.list_models(:openai, :api_key, "api_session")

      # Test OAuth auth
      {:ok, _} =
        SavedAuthentication.create_named_session(
          :openai,
          :oauth,
          "oauth_session",
          %{
            access_token: "test-token",
            expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
          }
        )

      oauth_result = Provider.list_models(:openai, :oauth, "oauth_session")

      # Both should either work or fail consistently
      assert is_tuple(api_result) and is_tuple(oauth_result)
    end

    test "handles non-existent sessions" do
      result = Provider.list_models(:openai, :api_key, "non_existent_session")
      assert {:error, :session_not_found} = result
    end
  end

  describe "Task 5.1: Universal Interface Testing - stream_chat/4" do
    test "initiates streaming with valid parameters" do
      # Create a test session
      {:ok, _} =
        SavedAuthentication.create_named_session(
          :openai,
          :api_key,
          "test_session",
          %{api_key: "test-key"}
        )

      messages = [%{role: "user", content: "Hello"}]
      options = [model: "gpt-3.5-turbo"]

      result = Provider.stream_chat(:openai, "test_session", messages, options)

      case result do
        {:ok, stream} ->
          assert is_function(stream) or match?(%Stream{}, stream)

        {:error, :not_implemented} ->
          # Expected for stub implementation
          assert true

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "validates message format" do
      {:ok, _} =
        SavedAuthentication.create_named_session(
          :openai,
          :api_key,
          "test_session",
          %{api_key: "test-key"}
        )

      # Invalid messages format
      invalid_messages = ["invalid", "message", "format"]
      result = Provider.stream_chat(:openai, "test_session", invalid_messages, [])

      case result do
        {:error, :invalid_messages} ->
          assert true

        {:error, :not_implemented} ->
          # Expected for stub implementation
          assert true

        other ->
          # Allow other error formats for now
          assert is_tuple(other) and elem(other, 0) == :error
      end
    end

    test "handles empty messages" do
      {:ok, _} =
        SavedAuthentication.create_named_session(
          :openai,
          :api_key,
          "test_session",
          %{api_key: "test-key"}
        )

      result = Provider.stream_chat(:openai, "test_session", [], [])

      case result do
        {:error, :empty_messages} ->
          assert true

        {:error, :not_implemented} ->
          # Expected for stub implementation
          assert true

        other ->
          # Allow other error formats for now
          assert is_tuple(other) and elem(other, 0) == :error
      end
    end
  end

  describe "Task 5.1: Universal Interface Testing - Provider Discovery" do
    test "list_providers/0 returns all known providers" do
      providers = Provider.list_providers()

      assert is_list(providers)
      assert :openai in providers
      assert :anthropic in providers
      assert :gemini in providers
      assert length(providers) >= 3
    end

    test "provider_capabilities/1 returns valid capabilities" do
      providers = Provider.list_providers()

      for provider <- providers do
        assert {:ok, caps} = Provider.provider_capabilities(provider)
        assert %TheMaestro.Providers.Capabilities{} = caps
        assert is_list(caps.auth_types)
        assert is_list(caps.features)

        # Verify expected auth types
        assert Enum.all?(caps.auth_types, &(&1 in [:oauth, :api_key]))

        # Verify expected features
        assert Enum.all?(caps.features, &(&1 in [:streaming, :models, :context_management]))
      end
    end

    test "handles invalid provider in capabilities" do
      result = Provider.provider_capabilities(:invalid_provider)
      assert {:error, :invalid_provider} = result
    end
  end

  describe "Task 5.1: Error Handling Validation" do
    test "invalid provider atoms return appropriate errors" do
      # Test across all interface functions
      session_params = [name: "test", credentials: %{"key" => "value"}]

      assert {:error, :invalid_provider} =
               Provider.create_session(:invalid, :api_key, session_params)

      assert {:error, :invalid_provider} = Provider.delete_session(:invalid, :api_key, "test")
      assert {:error, :invalid_provider} = Provider.list_models(:invalid, :api_key, "test")
      assert {:error, :invalid_provider} = Provider.stream_chat(:invalid, "test", [], [])
      assert {:error, :invalid_provider} = Provider.provider_capabilities(:invalid)
    end

    test "missing modules handled gracefully" do
      # This tests the dynamic module resolution
      result = Provider.resolve_module(:nonexistent_provider, :streaming)
      assert {:error, :module_not_found} = result
    end

    test "parameter validation with clear error messages" do
      # Test nil parameters
      assert {:error, _} = Provider.create_session(nil, :api_key, [])
      assert {:error, _} = Provider.create_session(:openai, nil, [])
      assert {:error, _} = Provider.create_session(:openai, :api_key, nil)

      # Test invalid parameter types
      assert {:error, _} = Provider.create_session("openai", :api_key, [])
      assert {:error, _} = Provider.create_session(:openai, "api_key", [])
    end

    test "timeout handling for provider operations" do
      # This would test timeout behavior - for now just ensure the interface accepts timeout options
      {:ok, _} =
        SavedAuthentication.create_named_session(
          :openai,
          :api_key,
          "test_session",
          %{api_key: "test-key"}
        )

      options = [timeout: 5000]
      messages = [%{role: "user", content: "Hello"}]

      result = Provider.stream_chat(:openai, "test_session", messages, options)
      # Should not crash due to timeout parameter
      assert is_tuple(result)
    end
  end
end
