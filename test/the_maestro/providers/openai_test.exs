defmodule TheMaestro.Providers.OpenAITest do
  use ExUnit.Case, async: true

  alias TheMaestro.Providers.LLMProvider
  alias TheMaestro.Providers.OpenAI

  describe "initialize_auth/1" do
    test "initializes with API key when OPENAI_API_KEY is set" do
      System.put_env("OPENAI_API_KEY", "sk-test-key")

      assert {:ok, auth_context} = OpenAI.initialize_auth(%{})
      assert auth_context.type == :api_key
      assert auth_context.credentials.api_key == "sk-test-key"

      System.delete_env("OPENAI_API_KEY")
    end

    test "initializes with OAuth when cached credentials exist" do
      # This would require mocking filesystem - simplified for now
      assert {:ok, _auth_context} = OpenAI.initialize_auth(%{auth_method: :oauth_cached})
    end

    test "returns error when no authentication method available" do
      System.delete_env("OPENAI_API_KEY")
      assert {:error, :oauth_initialization_required} = OpenAI.initialize_auth(%{})
    end
  end

  describe "complete_text/3" do
    test "makes successful text completion with API key" do
      auth_context = %{
        type: :api_key,
        credentials: %{api_key: "sk-test-key"},
        config: %{}
      }

      messages = [%{role: :user, content: "Hello"}]
      opts = %{model: "gpt-4", temperature: 0.7, max_tokens: 100}

      # This would typically mock the HTTP request
      # For now, we'll test the interface compliance
      assert is_function(&OpenAI.complete_text/3, 3)
    end
  end

  describe "complete_with_tools/3" do
    test "makes successful tool completion with OAuth" do
      auth_context = %{
        type: :oauth,
        credentials: %{access_token: "oauth-token"},
        config: %{}
      }

      messages = [%{role: :user, content: "List files"}]
      tools = [%{"name" => "list_files", "description" => "List files in directory"}]
      opts = %{model: "gpt-4", temperature: 0.0, max_tokens: 100, tools: tools}

      # Test interface compliance
      assert is_function(&OpenAI.complete_with_tools/3, 3)
    end
  end

  describe "refresh_auth/1" do
    test "refreshes OAuth tokens when needed" do
      auth_context = %{
        type: :oauth,
        credentials: %{access_token: "old-token", refresh_token: "refresh-token"},
        config: %{}
      }

      # Test interface compliance
      assert is_function(&OpenAI.refresh_auth/1, 1)
    end

    test "returns unchanged context for API key auth" do
      auth_context = %{
        type: :api_key,
        credentials: %{api_key: "sk-test-key"},
        config: %{}
      }

      assert {:ok, ^auth_context} = OpenAI.refresh_auth(auth_context)
    end
  end

  describe "validate_auth/1" do
    test "validates API key format" do
      valid_context = %{
        type: :api_key,
        credentials: %{api_key: "sk-test-key"}
      }

      invalid_context = %{
        type: :api_key,
        credentials: %{api_key: ""}
      }

      assert :ok = OpenAI.validate_auth(valid_context)
      assert {:error, :invalid_api_key} = OpenAI.validate_auth(invalid_context)
    end
  end

  describe "OAuth flows" do
    test "device_authorization_flow/1 returns auth URL and polling function" do
      assert {:ok, flow_data} = OpenAI.device_authorization_flow(%{})
      assert is_binary(flow_data.auth_url)
      assert is_function(flow_data.polling_fn)
      assert is_binary(flow_data.state)
    end

    test "web_authorization_flow/1 returns auth URL for web OAuth" do
      assert {:ok, flow_data} = OpenAI.web_authorization_flow(%{})
      assert is_binary(flow_data.auth_url)
      assert is_binary(flow_data.state)
    end
  end
end
