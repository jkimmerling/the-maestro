defmodule TheMaestro.TUI.APIKeyHandler do
  @moduledoc """
  API Key input and validation handler for TUI.

  This module provides secure API key input with masking and real-time validation
  for different providers.
  """

  alias TheMaestro.TUI.MenuHelpers
  alias TheMaestro.Providers.{Anthropic, Gemini, OpenAI}

  @doc """
  Handles API key input and validation for a specific provider.

  ## Parameters
    - `provider`: The provider atom (:anthropic, :google, :openai)

  ## Returns
    - `{:ok, auth_context}`: Successfully validated API key
    - `{:error, reason}`: Failed validation or user cancelled
  """
  @spec handle_api_key_auth(atom()) :: {:ok, map()} | {:error, atom() | String.t()}
  def handle_api_key_auth(provider) do
    display_api_key_instructions(provider)

    case get_api_key_input(provider) do
      {:ok, api_key} ->
        validate_and_create_auth_context(provider, api_key)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates an API key format for a specific provider.

  ## Parameters
    - `provider`: The provider atom
    - `api_key`: The API key string

  ## Returns
    - `{:ok, api_key}`: Valid format
    - `{:error, :invalid_format}`: Invalid format
  """
  @spec validate_api_key_format(atom(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate_api_key_format(provider, api_key) do
    # API Key format patterns for basic validation
    api_key_patterns = %{
      anthropic: ~r/^sk-ant-api03-[A-Za-z0-9_-]{95}$/,
      google: ~r/^[A-Za-z0-9_-]{39}$/,
      openai: ~r/^sk-[A-Za-z0-9]{48}$/
    }

    pattern = Map.get(api_key_patterns, provider)

    cond do
      is_nil(pattern) ->
        # No specific pattern for this provider, accept any non-empty string
        if String.trim(api_key) != "", do: {:ok, api_key}, else: {:error, :invalid_format}

      Regex.match?(pattern, api_key) ->
        {:ok, api_key}

      true ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Tests an API key by making a simple API call to the provider.

  ## Parameters
    - `provider`: The provider atom
    - `api_key`: The API key to test

  ## Returns
    - `:ok`: API key works
    - `{:error, reason}`: API key validation failed
  """
  @spec test_api_key(atom(), String.t()) :: :ok | {:error, String.t()}
  def test_api_key(provider, api_key) do
    MenuHelpers.display_loading("Testing API key connection...")

    case make_test_call(provider, api_key) do
      {:ok, _response} ->
        :ok

      {:error, :unauthorized} ->
        {:error, "Invalid API key - authentication failed"}

      {:error, :rate_limited} ->
        {:error, "Rate limited - please wait and try again"}

      {:error, :network_error} ->
        {:error, "Network error - please check your internet connection"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, _other} ->
        {:error, "Failed to validate API key"}
    end
  end

  # Private helper functions

  defp display_api_key_instructions(provider) do
    MenuHelpers.clear_screen()
    MenuHelpers.display_title("API KEY AUTHENTICATION")

    provider_name = get_provider_name(provider)
    IO.puts([IO.ANSI.bright(), "Enter your #{provider_name} API Key", IO.ANSI.reset()])
    IO.puts("")

    display_provider_specific_instructions(provider)

    IO.puts([
      IO.ANSI.faint(),
      "Your API key will be masked as you type for security.",
      IO.ANSI.reset()
    ])

    IO.puts([IO.ANSI.faint(), "Press Ctrl+C to cancel at any time.", IO.ANSI.reset()])
    IO.puts("")
  end

  defp display_provider_specific_instructions(:anthropic) do
    IO.puts([IO.ANSI.bright(), "Where to find your Claude API key:", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "1. Visit https://console.anthropic.com/", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "2. Sign in or create an account", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "3. Go to API Keys section", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "4. Create a new API key", IO.ANSI.reset()])
    IO.puts("")
    IO.puts([IO.ANSI.yellow(), "Format: sk-ant-api03-...", IO.ANSI.reset()])
    IO.puts("")
  end

  defp display_provider_specific_instructions(:google) do
    IO.puts([IO.ANSI.bright(), "Where to find your Gemini API key:", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "1. Visit https://aistudio.google.com/app/apikey", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "2. Sign in with your Google account", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "3. Create a new API key", IO.ANSI.reset()])
    IO.puts("")
    IO.puts([IO.ANSI.yellow(), "Format: 39 characters alphanumeric", IO.ANSI.reset()])
    IO.puts("")
  end

  defp display_provider_specific_instructions(:openai) do
    IO.puts([IO.ANSI.bright(), "Where to find your OpenAI API key:", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "1. Visit https://platform.openai.com/api-keys", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "2. Sign in or create an account", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "3. Create a new secret key", IO.ANSI.reset()])
    IO.puts("")
    IO.puts([IO.ANSI.yellow(), "Format: sk-...", IO.ANSI.reset()])
    IO.puts("")
  end

  defp get_api_key_input(provider) do
    case MenuHelpers.get_secure_input("API Key: ", "*") do
      {:ok, api_key} ->
        trimmed_key = String.trim(api_key)

        if trimmed_key == "" do
          MenuHelpers.display_error("API key cannot be empty")
          handle_input_error(provider)
        else
          case validate_api_key_format(provider, trimmed_key) do
            {:ok, validated_key} ->
              {:ok, validated_key}

            {:error, :invalid_format} ->
              display_format_error(provider)
              handle_input_error(provider)
          end
        end

      {:error, :cancelled} ->
        {:error, :cancelled}
    end
  end

  defp display_format_error(provider) do
    case provider do
      :anthropic ->
        MenuHelpers.display_error(
          "Invalid API key format. Claude API keys should start with 'sk-ant-api03-' and be 104 characters long."
        )

      :google ->
        MenuHelpers.display_error(
          "Invalid API key format. Gemini API keys should be 39 characters of letters, numbers, underscores, and hyphens."
        )

      :openai ->
        MenuHelpers.display_error(
          "Invalid API key format. OpenAI API keys should start with 'sk-' and be 51 characters long."
        )

      _ ->
        MenuHelpers.display_error("Invalid API key format for this provider.")
    end
  end

  defp handle_input_error(provider) do
    IO.puts([IO.ANSI.bright(), "Options:", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "1. Try again", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "2. Back to authentication method selection", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "3. Exit", IO.ANSI.reset()])
    IO.puts("")

    case MenuHelpers.get_menu_choice("Enter your choice (1-3): ", 1..3) do
      {:ok, 1} ->
        get_api_key_input(provider)

      {:ok, 2} ->
        {:error, :back}

      {:ok, 3} ->
        {:error, :quit}

      {:error, :invalid_choice} ->
        MenuHelpers.display_error("Invalid choice. Please select 1, 2, or 3.")
        :timer.sleep(2000)
        handle_input_error(provider)

      {:error, :quit} ->
        {:error, :quit}
    end
  end

  defp validate_and_create_auth_context(provider, api_key) do
    case test_api_key(provider, api_key) do
      :ok ->
        MenuHelpers.display_success("API key validated successfully!")
        :timer.sleep(1000)

        auth_context = %{
          type: :api_key,
          provider: provider,
          credentials: %{api_key: api_key},
          config: %{}
        }

        {:ok, auth_context}

      {:error, reason} ->
        MenuHelpers.display_error("API key validation failed: #{reason}")
        handle_validation_error(provider, reason)
    end
  end

  defp handle_validation_error(provider, _reason) do
    IO.puts([IO.ANSI.bright(), "Options:", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "1. Re-enter API key", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "2. Try OAuth instead", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "3. Back to provider selection", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "4. Exit", IO.ANSI.reset()])
    IO.puts("")

    case MenuHelpers.get_menu_choice("Enter your choice (1-4): ", 1..4) do
      {:ok, 1} ->
        handle_api_key_auth(provider)

      {:ok, 2} ->
        {:error, :try_oauth}

      {:ok, 3} ->
        {:error, :back_to_provider}

      {:ok, 4} ->
        {:error, :quit}

      {:error, :invalid_choice} ->
        MenuHelpers.display_error("Invalid choice. Please select a number between 1 and 4.")
        :timer.sleep(2000)
        handle_validation_error(provider, "validation failed")

      {:error, :quit} ->
        {:error, :quit}
    end
  end

  defp make_test_call(provider, api_key) do
    # Create a minimal test auth context
    auth_context = %{
      type: :api_key,
      credentials: %{api_key: api_key},
      config: %{}
    }

    case provider do
      :anthropic ->
        test_anthropic_key(auth_context)

      :google ->
        test_gemini_key(auth_context)

      :openai ->
        test_openai_key(auth_context)

      _ ->
        {:error, "Unsupported provider for testing"}
    end
  end

  defp test_anthropic_key(auth_context) do
    # Make a simple test call to validate the API key
    case Anthropic.validate_auth(auth_context) do
      :ok -> {:ok, "validated"}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, "Network error"}
  end

  defp test_gemini_key(auth_context) do
    # Make a simple test call to validate the API key
    case Gemini.validate_auth(auth_context) do
      :ok -> {:ok, "validated"}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, "Network error"}
  end

  defp test_openai_key(auth_context) do
    # Make a simple test call to validate the API key
    case OpenAI.validate_auth(auth_context) do
      :ok -> {:ok, "validated"}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, "Network error"}
  end

  defp get_provider_name(:anthropic), do: "Claude (Anthropic)"
  defp get_provider_name(:google), do: "Gemini (Google)"
  defp get_provider_name(:openai), do: "ChatGPT (OpenAI)"
  defp get_provider_name(provider), do: String.capitalize(to_string(provider))
end
