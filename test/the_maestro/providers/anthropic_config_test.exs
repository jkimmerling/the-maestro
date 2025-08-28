defmodule TheMaestro.Providers.AnthropicConfigTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Providers.AnthropicConfig

  describe "load/0" do
    test "loads configuration successfully when API key is present" do
      # Arrange - Set up test configuration
      api_key = "sk-test-key-123"

      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, api_key)
      Application.put_env(:the_maestro, :anthropic, test_config)

      # Act
      result = AnthropicConfig.load()

      # Assert
      assert {:ok, config} = result
      assert config.api_key == api_key
      assert config.version == "2023-06-01"
      assert config.beta == "messages-2023-12-15"
      assert config.user_agent == "llxprt/1.0"
      assert config.accept == "application/json"
      assert config.client_version == "1.0.0"
      assert config.base_url == "https://api.anthropic.com"

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "returns error when API key is nil" do
      # Arrange
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, nil)
      Application.put_env(:the_maestro, :anthropic, test_config)

      # Act
      result = AnthropicConfig.load()

      # Assert
      assert result == {:error, :missing_api_key}

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "returns error when API key is empty string" do
      # Arrange
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      test_config = Keyword.put(original_config, :api_key, "")
      Application.put_env(:the_maestro, :anthropic, test_config)

      # Act
      result = AnthropicConfig.load()

      # Assert
      assert result == {:error, :missing_api_key}

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "uses default values when specific config keys are missing" do
      # Arrange
      api_key = "sk-test-key-456"
      # Only set api_key, let others use defaults
      test_config = [api_key: api_key]
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      Application.put_env(:the_maestro, :anthropic, test_config)

      # Act
      {:ok, config} = AnthropicConfig.load()

      # Assert - Default values should be used
      assert config.api_key == api_key
      assert config.version == "2023-06-01"
      assert config.beta == "messages-2023-12-15"
      assert config.user_agent == "llxprt/1.0"
      assert config.accept == "application/json"
      assert config.client_version == "1.0.0"
      assert config.base_url == "https://api.anthropic.com"

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "uses custom configuration values when provided" do
      # Arrange
      custom_config = [
        api_key: "sk-custom-key",
        version: "2024-01-01",
        beta: "custom-beta",
        user_agent: "custom/2.0",
        client_version: "2.0.0",
        base_url: "https://custom.api.com"
      ]

      original_config = Application.get_env(:the_maestro, :anthropic, [])
      Application.put_env(:the_maestro, :anthropic, custom_config)

      # Act
      {:ok, config} = AnthropicConfig.load()

      # Assert - Custom values should be used
      assert config.api_key == "sk-custom-key"
      assert config.version == "2024-01-01"
      assert config.beta == "custom-beta"
      assert config.user_agent == "custom/2.0"
      # Always defaults to this
      assert config.accept == "application/json"
      assert config.client_version == "2.0.0"
      assert config.base_url == "https://custom.api.com"

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end

    test "handles missing configuration section gracefully" do
      # Arrange - Remove the entire anthropic config section
      original_config = Application.get_env(:the_maestro, :anthropic, [])
      Application.delete_env(:the_maestro, :anthropic)

      # Act
      result = AnthropicConfig.load()

      # Assert
      assert result == {:error, :missing_api_key}

      # Cleanup
      Application.put_env(:the_maestro, :anthropic, original_config)
    end
  end
end
