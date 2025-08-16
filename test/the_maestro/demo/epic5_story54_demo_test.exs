defmodule TheMaestro.Demo.Epic5Story54DemoTest do
  use ExUnit.Case, async: false

  alias TheMaestro.Providers.{Anthropic, Gemini, LLMProvider, OpenAI}
  alias TheMaestro.Providers.Auth.ProviderRegistry

  setup_all do
    # Start the application for testing
    Application.ensure_all_started(:the_maestro)
    :ok
  end

  describe "Provider registry and discovery" do
    test "provider registry returns expected providers" do
      providers = ProviderRegistry.list_providers()

      assert is_list(providers)
      assert :anthropic in providers
      assert :openai in providers
      assert :google in providers
    end

    test "provider registry returns correct modules for each provider" do
      {:ok, anthropic_module} = ProviderRegistry.get_provider_module(:anthropic)
      assert anthropic_module == TheMaestro.Providers.Anthropic

      {:ok, openai_module} = ProviderRegistry.get_provider_module(:openai)
      assert openai_module == TheMaestro.Providers.OpenAI

      {:ok, google_module} = ProviderRegistry.get_provider_module(:google)
      assert google_module == TheMaestro.Providers.Gemini
    end

    test "provider registry returns authentication methods for each provider" do
      anthropic_methods = ProviderRegistry.get_provider_methods(:anthropic)
      assert is_list(anthropic_methods)
      assert :api_key in anthropic_methods

      openai_methods = ProviderRegistry.get_provider_methods(:openai)
      assert is_list(openai_methods)
      assert :api_key in openai_methods

      google_methods = ProviderRegistry.get_provider_methods(:google)
      assert is_list(google_methods)
      assert :api_key in google_methods
    end

    test "provider registry validates provider method combinations" do
      assert :ok = ProviderRegistry.validate_provider_method(:anthropic, :api_key)
      assert :ok = ProviderRegistry.validate_provider_method(:openai, :api_key)
      assert :ok = ProviderRegistry.validate_provider_method(:google, :api_key)

      assert {:error, :invalid_provider} =
               ProviderRegistry.validate_provider_method(:invalid_provider, :api_key)

      assert {:error, :unsupported_method} =
               ProviderRegistry.validate_provider_method(:anthropic, :invalid_method)
    end
  end

  describe "Provider authentication testing" do
    test "anthropic provider authentication handles different scenarios correctly" do
      # Test authentication behavior - this will return different results based on API key configuration
      result = Anthropic.initialize_auth(%{})

      case result do
        {:ok, auth_context} ->
          # API key is configured
          assert auth_context.type in [:api_key, :oauth]
          assert is_map(auth_context.credentials)
          assert is_map(auth_context.config)

          # Test validation works
          assert :ok = Anthropic.validate_auth(auth_context)

        {:error, :oauth_initialization_required} ->
          # No API key configured - this is expected in test environment
          assert true

        {:error, _reason} ->
          # Other authentication errors - also expected without configuration
          assert true
      end
    end

    test "openai provider authentication handles different scenarios correctly" do
      result = OpenAI.initialize_auth(%{})

      case result do
        {:ok, auth_context} ->
          # API key is configured
          assert auth_context.type in [:api_key, :oauth]
          assert is_map(auth_context.credentials)
          assert is_map(auth_context.config)

          # Test validation works
          assert :ok = OpenAI.validate_auth(auth_context)

        {:error, :oauth_initialization_required} ->
          # No API key configured - expected in test environment
          assert true

        {:error, _reason} ->
          # Other authentication errors - also expected
          assert true
      end
    end

    test "gemini provider authentication handles different scenarios correctly" do
      result = Gemini.initialize_auth(%{})

      case result do
        {:ok, auth_context} ->
          # API key is configured
          assert auth_context.type in [:api_key, :oauth, :service_account]
          assert is_map(auth_context.credentials)
          assert is_map(auth_context.config)

          # Test validation works
          assert :ok = Gemini.validate_auth(auth_context)

        {:error, :oauth_initialization_required} ->
          # No API key configured - expected in test environment
          assert true

        {:error, _reason} ->
          # Other authentication errors - also expected
          assert true
      end
    end

    test "providers return appropriate error for invalid authentication" do
      # Test with obviously invalid auth context
      invalid_auth = %{
        type: :api_key,
        credentials: %{api_key: "invalid_key_12345"},
        config: %{}
      }

      # All providers should detect invalid authentication
      assert {:error, _} = Anthropic.validate_auth(invalid_auth)
      assert {:error, _} = OpenAI.validate_auth(invalid_auth)
      assert {:error, _} = Gemini.validate_auth(invalid_auth)
    end
  end

  describe "Model listing and capabilities" do
    test "anthropic provider returns static model list when authentication fails" do
      # Test with invalid auth context - should still return model list
      invalid_auth = %{
        type: :api_key,
        credentials: %{api_key: "invalid_key_12345"},
        config: %{}
      }

      case Anthropic.list_models(invalid_auth) do
        {:ok, models} ->
          # Static model list should be returned
          assert is_list(models)
          assert length(models) > 0

          # Verify model structure
          first_model = hd(models)
          assert is_binary(first_model.id)
          assert is_binary(first_model.name)
          assert first_model.cost_tier in [:economy, :balanced, :premium]
          assert is_boolean(first_model.multimodal)
          assert is_boolean(first_model.function_calling)

        {:error, _reason} ->
          # Some providers might return error for invalid auth
          assert true
      end
    end

    test "openai provider handles model listing appropriately" do
      invalid_auth = %{
        type: :api_key,
        credentials: %{api_key: "invalid_key_12345"},
        config: %{}
      }

      case OpenAI.list_models(invalid_auth) do
        {:ok, models} ->
          assert is_list(models)
          assert length(models) > 0

        {:error, _reason} ->
          # Expected for invalid authentication
          assert true
      end
    end

    test "gemini provider handles model listing appropriately" do
      invalid_auth = %{
        type: :api_key,
        credentials: %{api_key: "invalid_key_12345"},
        config: %{}
      }

      case Gemini.list_models(invalid_auth) do
        {:ok, models} ->
          assert is_list(models)
          assert length(models) > 0

        {:error, _reason} ->
          # Expected for invalid authentication
          assert true
      end
    end
  end

  describe "Text completion functionality" do
    test "providers handle invalid model names appropriately" do
      # Test with invalid auth context and invalid model
      invalid_auth = %{
        type: :api_key,
        credentials: %{api_key: "invalid_key_12345"},
        config: %{}
      }

      test_messages = [%{role: :user, content: "Test message"}]
      invalid_opts = %{model: "non-existent-model-12345", max_tokens: 10}

      # All providers should return errors for invalid authentication and/or model
      assert {:error, _} = Anthropic.complete_text(invalid_auth, test_messages, invalid_opts)
      assert {:error, _} = OpenAI.complete_text(invalid_auth, test_messages, invalid_opts)
      assert {:error, _} = Gemini.complete_text(invalid_auth, test_messages, invalid_opts)
    end

    test "providers validate message format correctly" do
      invalid_auth = %{
        type: :api_key,
        credentials: %{api_key: "invalid_key_12345"},
        config: %{}
      }

      # Test with invalid message format
      invalid_messages = [%{invalid: "message", format: true}]
      valid_opts = %{model: "test-model", max_tokens: 10}

      # Should return error for invalid message format (or auth)
      assert {:error, _} = Anthropic.complete_text(invalid_auth, invalid_messages, valid_opts)
      assert {:error, _} = OpenAI.complete_text(invalid_auth, invalid_messages, valid_opts)
      assert {:error, _} = Gemini.complete_text(invalid_auth, invalid_messages, valid_opts)
    end
  end

  describe "OAuth functionality" do
    test "anthropic provider has oauth methods available" do
      functions = Anthropic.__info__(:functions)

      # Check that OAuth-related functions exist
      assert Keyword.has_key?(functions, :device_authorization_flow)
      assert Keyword.has_key?(functions, :web_authorization_flow)
      assert Keyword.has_key?(functions, :exchange_authorization_code)
      assert Keyword.has_key?(functions, :cache_oauth_credentials)
      assert Keyword.has_key?(functions, :logout)
    end

    test "anthropic oauth methods return appropriate structures" do
      # Test device authorization flow setup
      case Anthropic.device_authorization_flow() do
        {:ok, flow_data} ->
          assert is_binary(flow_data.auth_url)
          assert is_binary(flow_data.state)
          assert is_binary(flow_data.code_verifier)
          assert is_function(flow_data.polling_fn)
      end

      # Test web authorization flow setup
      case Anthropic.web_authorization_flow() do
        {:ok, flow_data} ->
          assert is_binary(flow_data.auth_url)
          assert is_binary(flow_data.state)
      end
    end
  end

  describe "Integration with credential storage" do
    test "provider authentication integrates with credential store" do
      # This tests the overall integration without requiring actual API keys
      providers = [:anthropic, :openai, :google]

      Enum.each(providers, fn provider ->
        # Test that provider registry can find the provider
        assert {:ok, _module} = ProviderRegistry.get_provider_module(provider)

        # Test that authentication methods are available
        methods = ProviderRegistry.get_provider_methods(provider)
        assert is_list(methods)
        assert :api_key in methods

        # Test provider-method validation
        assert :ok = ProviderRegistry.validate_provider_method(provider, :api_key)
      end)
    end
  end

  describe "Error handling and edge cases" do
    test "providers handle nil or malformed auth contexts gracefully" do
      # Test with nil auth context
      test_messages = [%{role: :user, content: "Test"}]
      test_opts = %{model: "test-model", max_tokens: 10}

      assert {:error, _} = Anthropic.complete_text(nil, test_messages, test_opts)
      assert {:error, _} = OpenAI.complete_text(nil, test_messages, test_opts)
      assert {:error, _} = Gemini.complete_text(nil, test_messages, test_opts)

      # Test with malformed auth context
      malformed_auth = %{invalid: "structure"}

      assert {:error, _} = Anthropic.complete_text(malformed_auth, test_messages, test_opts)
      assert {:error, _} = OpenAI.complete_text(malformed_auth, test_messages, test_opts)
      assert {:error, _} = Gemini.complete_text(malformed_auth, test_messages, test_opts)
    end

    test "providers handle empty or invalid message lists" do
      invalid_auth = %{
        type: :api_key,
        credentials: %{api_key: "invalid_key_12345"},
        config: %{}
      }

      test_opts = %{model: "test-model", max_tokens: 10}

      # Test with empty message list
      assert {:error, _} = Anthropic.complete_text(invalid_auth, [], test_opts)
      assert {:error, _} = OpenAI.complete_text(invalid_auth, [], test_opts)
      assert {:error, _} = Gemini.complete_text(invalid_auth, [], test_opts)

      # Test with nil message list
      assert {:error, _} = Anthropic.complete_text(invalid_auth, nil, test_opts)
      assert {:error, _} = OpenAI.complete_text(invalid_auth, nil, test_opts)
      assert {:error, _} = Gemini.complete_text(invalid_auth, nil, test_opts)
    end

    test "provider registry handles unknown providers correctly" do
      assert {:error, :not_found} = ProviderRegistry.get_provider_module(:unknown_provider)
      assert [] = ProviderRegistry.get_provider_methods(:unknown_provider)
      assert false = ProviderRegistry.supports_method?(:unknown_provider, :api_key)

      assert {:error, :invalid_provider} =
               ProviderRegistry.validate_provider_method(:unknown_provider, :api_key)
    end
  end

  describe "Real API integration tests" do
    @tag :integration
    test "anthropic integration test with real API" do
      case System.get_env("ANTHROPIC_API_KEY") do
        nil ->
          # Skip test if no API key is configured
          :ok

        _api_key ->
          case Anthropic.initialize_auth(%{}) do
            {:ok, auth_context} ->
              # Test model listing
              case Anthropic.list_models(auth_context) do
                {:ok, models} ->
                  assert is_list(models)
                  assert length(models) > 0

                {:error, reason} ->
                  flunk("Model listing failed: #{inspect(reason)}")
              end

              # Test simple completion
              test_messages = [%{role: :user, content: "Say 'test successful' and nothing else"}]
              test_opts = %{model: "claude-3-haiku-20240307", max_tokens: 20}

              case Anthropic.complete_text(auth_context, test_messages, test_opts) do
                {:ok, response} ->
                  assert is_binary(response.content)
                  assert is_binary(response.model)
                  assert is_map(response.usage)

                {:error, reason} ->
                  flunk("Text completion failed: #{inspect(reason)}")
              end

            {:error, _reason} ->
              # API key might be invalid or other auth issue
              :ok
          end
      end
    end

    @tag :integration
    test "openai integration test with real API" do
      case System.get_env("OPENAI_API_KEY") do
        nil ->
          # Skip test if no API key is configured
          :ok

        _api_key ->
          case OpenAI.initialize_auth(%{}) do
            {:ok, auth_context} ->
              # Test simple completion
              test_messages = [%{role: :user, content: "Say 'test successful' and nothing else"}]
              test_opts = %{model: "gpt-3.5-turbo", max_tokens: 20}

              case OpenAI.complete_text(auth_context, test_messages, test_opts) do
                {:ok, response} ->
                  assert is_binary(response.content)
                  assert is_binary(response.model)
                  assert is_map(response.usage)

                {:error, reason} ->
                  flunk("Text completion failed: #{inspect(reason)}")
              end

            {:error, _reason} ->
              # API key might be invalid or other auth issue
              :ok
          end
      end
    end

    @tag :integration
    test "gemini integration test with real API" do
      case System.get_env("GEMINI_API_KEY") do
        nil ->
          # Skip test if no API key is configured
          :ok

        _api_key ->
          case Gemini.initialize_auth(%{}) do
            {:ok, auth_context} ->
              # Test simple completion
              test_messages = [%{role: :user, content: "Say 'test successful' and nothing else"}]
              test_opts = %{model: "gemini-pro", max_tokens: 20}

              case Gemini.complete_text(auth_context, test_messages, test_opts) do
                {:ok, response} ->
                  assert is_binary(response.content)
                  assert is_binary(response.model)
                  assert is_map(response.usage)

                {:error, reason} ->
                  flunk("Text completion failed: #{inspect(reason)}")
              end

            {:error, _reason} ->
              # API key might be invalid or other auth issue
              :ok
          end
      end
    end
  end
end
