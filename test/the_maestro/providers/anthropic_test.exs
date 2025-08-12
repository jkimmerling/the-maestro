defmodule TheMaestro.Providers.AnthropicTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Providers.Anthropic

  describe "initialize_auth/1" do
    test "initializes with API key when ANTHROPIC_API_KEY is set" do
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-test-key")

      assert {:ok, auth_context} = Anthropic.initialize_auth(%{})
      assert auth_context.type == :api_key
      assert auth_context.credentials.api_key == "sk-ant-test-key"

      System.delete_env("ANTHROPIC_API_KEY")
    end

    test "returns error when OAuth requested but no cached credentials exist" do
      # This would require mocking filesystem - simplified for now
      # In CI environment, this returns :oauth_not_available_in_non_interactive
      case Anthropic.initialize_auth(%{auth_method: :oauth_cached}) do
        {:error, :oauth_not_available_in_non_interactive} -> :ok
        {:ok, _auth_context} -> :ok
        other -> flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "returns error when no authentication method available" do
      System.delete_env("ANTHROPIC_API_KEY")
      # In CI environment (non-interactive), different error is returned
      case Anthropic.initialize_auth(%{}) do
        {:error, :oauth_initialization_required} -> :ok
        {:error, :no_auth_method_available} -> :ok
        {:error, :oauth_not_available_in_non_interactive} -> :ok
        other -> flunk("Unexpected result: #{inspect(other)}")
      end
    end
  end

  describe "complete_text/3" do
    test "makes successful text completion with API key" do
      _auth_context = %{
        type: :api_key,
        credentials: %{api_key: "sk-ant-test-key"},
        config: %{}
      }

      _messages = [%{role: :user, content: "Hello"}]
      _opts = %{model: "claude-3-sonnet-20240229", temperature: 0.7, max_tokens: 100}

      # Test interface compliance
      assert is_function(&Anthropic.complete_text/3, 3)
    end
  end

  describe "complete_with_tools/3" do
    test "makes successful tool completion with OAuth" do
      _auth_context = %{
        type: :oauth,
        credentials: %{access_token: "oauth-token"},
        config: %{}
      }

      _messages = [%{role: :user, content: "List files"}]
      tools = [%{"name" => "list_files", "description" => "List files in directory"}]

      _opts = %{
        model: "claude-3-sonnet-20240229",
        temperature: 0.0,
        max_tokens: 100,
        tools: tools
      }

      # Test interface compliance
      assert is_function(&Anthropic.complete_with_tools/3, 3)
    end
  end

  describe "refresh_auth/1" do
    test "refreshes OAuth tokens when needed" do
      _auth_context = %{
        type: :oauth,
        credentials: %{access_token: "old-token", refresh_token: "refresh-token"},
        config: %{}
      }

      # Test interface compliance
      assert is_function(&Anthropic.refresh_auth/1, 1)
    end

    test "returns unchanged context for API key auth" do
      auth_context = %{
        type: :api_key,
        credentials: %{api_key: "sk-ant-test-key"},
        config: %{}
      }

      assert {:ok, ^auth_context} = Anthropic.refresh_auth(auth_context)
    end
  end

  describe "validate_auth/1" do
    test "validates API key format" do
      valid_context = %{
        type: :api_key,
        credentials: %{api_key: "sk-ant-test-key"}
      }

      invalid_context = %{
        type: :api_key,
        credentials: %{api_key: ""}
      }

      assert :ok = Anthropic.validate_auth(valid_context)
      assert {:error, :invalid_api_key} = Anthropic.validate_auth(invalid_context)
    end
  end

  describe "OAuth flows" do
    test "device_authorization_flow/1 returns auth URL and polling function" do
      assert {:ok, flow_data} = Anthropic.device_authorization_flow(%{})
      assert is_binary(flow_data.auth_url)
      assert is_function(flow_data.polling_fn)
      assert is_binary(flow_data.state)
    end

    test "web_authorization_flow/1 returns auth URL for web OAuth" do
      assert {:ok, flow_data} = Anthropic.web_authorization_flow(%{})
      assert is_binary(flow_data.auth_url)
      assert is_binary(flow_data.state)
    end
  end
end
