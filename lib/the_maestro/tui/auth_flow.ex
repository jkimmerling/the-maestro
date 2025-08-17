defmodule TheMaestro.TUI.AuthFlow do
  @moduledoc """
  Authentication flow coordinator for TUI.

  This module coordinates the authentication flow, handling method selection,
  authentication execution, and state management for the TUI interface.
  """

  alias TheMaestro.Providers.Auth.{CredentialStore, ProviderRegistry}
  alias TheMaestro.TUI.{APIKeyHandler, MenuHelpers, OAuthHandler}

  @doc """
  Coordinates the complete authentication flow for a provider.

  ## Parameters
    - `provider`: The provider atom (:anthropic, :google, :openai)

  ## Returns
    - `{:ok, auth_context}`: Successfully authenticated
    - `{:error, reason}`: Authentication failed or user cancelled
  """
  @spec authenticate_provider(atom()) :: {:ok, map()} | {:error, atom() | String.t()}
  def authenticate_provider(provider) do
    # First check for existing credentials
    existing_creds = get_existing_credentials(provider)

    case existing_creds do
      [] ->
        # No existing credentials, proceed with normal auth flow
        proceed_with_auth_method_selection(provider)

      creds ->
        # Show existing credentials and allow user to choose
        display_credential_selection_menu(provider, creds)
        handle_credential_selection(provider, creds)
    end
  end

  @doc """
  Gets available authentication methods for a provider.

  ## Parameters
    - `provider`: The provider atom

  ## Returns
    List of available authentication methods
  """
  @spec get_available_auth_methods(atom()) :: [atom()]
  def get_available_auth_methods(provider) do
    ProviderRegistry.get_provider_methods(provider)
  end

  @doc """
  Checks if authentication is required based on configuration.

  ## Returns
    Boolean indicating if authentication is required
  """
  @spec authentication_required?() :: boolean()
  def authentication_required? do
    # Provider authentication is always required to use their APIs
    true
  end

  @doc """
  Validates an authentication context.

  ## Parameters
    - `auth_context`: The authentication context to validate

  ## Returns
    - `:ok`: Valid authentication context
    - `{:error, reason}`: Invalid or expired context
  """
  @spec validate_auth_context(map()) :: :ok | {:error, String.t()}
  def validate_auth_context(auth_context) do
    case auth_context do
      %{type: type, provider: provider, credentials: credentials}
      when is_atom(type) and is_atom(provider) and is_map(credentials) ->
        validate_auth_credentials(type, provider, credentials)

      _ ->
        {:error, "Invalid authentication context structure"}
    end
  end

  # Private helper functions

  defp display_auth_method_menu(provider, methods) do
    provider_name = get_provider_name(provider)

    options = Enum.map(methods, &format_auth_method/1)

    additional_info =
      methods
      |> Enum.with_index(1)
      |> Enum.reduce(%{}, fn {method, index}, acc ->
        Map.put(acc, index, get_auth_method_description(method))
      end)
      |> Map.put(length(methods) + 1, "Return to provider selection")

    all_options = options ++ ["Back to provider selection"]

    MenuHelpers.display_menu(
      "AUTHENTICATION FOR #{String.upcase(provider_name)}",
      all_options,
      additional_info
    )
  end

  defp handle_auth_method_selection(provider, methods) do
    max_choice = length(methods) + 1
    prompt = "Enter your choice (1-#{max_choice}): "

    case MenuHelpers.get_menu_choice(prompt, 1..max_choice) do
      {:ok, choice} when choice <= length(methods) ->
        method = Enum.at(methods, choice - 1)
        execute_authentication(provider, method)

      {:ok, _back_choice} ->
        {:error, :back_to_provider}

      {:error, :invalid_choice} ->
        MenuHelpers.display_error(
          "Invalid choice. Please select a number between 1 and #{max_choice}."
        )

        :timer.sleep(2000)
        authenticate_provider(provider)

      {:error, :quit} ->
        {:error, :quit}
    end
  end

  defp execute_authentication(provider, method) do
    case method do
      :api_key ->
        execute_api_key_auth(provider)

      :oauth ->
        execute_oauth_auth(provider)

      :device_flow ->
        # Device flow uses the same OAuth handler
        execute_oauth_auth(provider)

      :service_account ->
        execute_service_account_auth(provider)

      _ ->
        {:error, "Unsupported authentication method: #{method}"}
    end
  end

  defp execute_api_key_auth(provider) do
    case APIKeyHandler.handle_api_key_auth(provider) do
      {:ok, auth_context} ->
        save_auth_preference(provider, :api_key)
        {:ok, auth_context}

      {:error, :try_oauth} ->
        # User requested to try OAuth instead
        execute_oauth_auth(provider)

      {:error, :back} ->
        # User wants to go back to method selection
        authenticate_provider(provider)

      {:error, :back_to_provider} ->
        {:error, :back_to_provider}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_oauth_auth(provider) do
    if OAuthHandler.supports_oauth?(provider) do
      case OAuthHandler.handle_oauth_auth(provider) do
        {:ok, auth_context} ->
          save_auth_preference(provider, :oauth)
          {:ok, auth_context}

        {:error, :back_to_provider} ->
          {:error, :back_to_provider}

        {:error, reason} ->
          handle_oauth_error(provider, reason)
      end
    else
      MenuHelpers.display_error("OAuth is not supported for this provider")
      :timer.sleep(2000)
      authenticate_provider(provider)
    end
  end

  defp execute_service_account_auth(provider) do
    case provider do
      :google ->
        # Google supports service account authentication
        execute_google_service_account_auth()

      _ ->
        MenuHelpers.display_error(
          "Service account authentication not supported for this provider"
        )

        :timer.sleep(2000)
        authenticate_provider(provider)
    end
  end

  defp execute_google_service_account_auth do
    MenuHelpers.clear_screen()
    MenuHelpers.display_title("SERVICE ACCOUNT AUTHENTICATION")

    IO.puts([IO.ANSI.bright(), "Google Service Account Authentication", IO.ANSI.reset()])
    IO.puts("")

    IO.puts([
      IO.ANSI.faint(),
      "Service account authentication uses GOOGLE_APPLICATION_CREDENTIALS",
      IO.ANSI.reset()
    ])

    IO.puts([
      IO.ANSI.faint(),
      "environment variable pointing to your service account JSON file.",
      IO.ANSI.reset()
    ])

    IO.puts("")

    case System.get_env("GOOGLE_APPLICATION_CREDENTIALS") do
      nil ->
        MenuHelpers.display_error("GOOGLE_APPLICATION_CREDENTIALS environment variable not set")
        handle_service_account_error()

      credentials_path ->
        case File.exists?(credentials_path) do
          true ->
            MenuHelpers.display_loading("Validating service account credentials...")
            validate_service_account_credentials(credentials_path)

          false ->
            MenuHelpers.display_error("Service account file not found: #{credentials_path}")
            handle_service_account_error()
        end
    end
  end

  defp validate_service_account_credentials(credentials_path) do
    # Create service account auth context
    auth_context = %{
      type: :service_account,
      provider: :google,
      credentials: %{credentials_path: credentials_path},
      config: %{}
    }

    case validate_auth_context(auth_context) do
      :ok ->
        MenuHelpers.display_success("Service account credentials validated successfully!")
        :timer.sleep(1000)
        save_auth_preference(:google, :service_account)
        {:ok, auth_context}

      {:error, reason} ->
        MenuHelpers.display_error("Service account validation failed: #{reason}")
        handle_service_account_error()
    end
  end

  defp handle_service_account_error do
    IO.puts([IO.ANSI.bright(), "Options:", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "1. Set GOOGLE_APPLICATION_CREDENTIALS and retry", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "2. Try OAuth instead", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "3. Back to authentication methods", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "4. Exit", IO.ANSI.reset()])
    IO.puts("")

    case MenuHelpers.get_menu_choice("Enter your choice (1-4): ", 1..4) do
      {:ok, 1} ->
        execute_google_service_account_auth()

      {:ok, 2} ->
        execute_oauth_auth(:google)

      {:ok, 3} ->
        authenticate_provider(:google)

      {:ok, 4} ->
        {:error, :quit}

      {:error, :invalid_choice} ->
        MenuHelpers.display_error("Invalid choice. Please select a number between 1 and 4.")
        :timer.sleep(2000)
        handle_service_account_error()

      {:error, :quit} ->
        {:error, :quit}
    end
  end

  defp handle_oauth_error(provider, reason) do
    MenuHelpers.display_error("OAuth authentication failed: #{inspect(reason)}")

    IO.puts([IO.ANSI.bright(), "Options:", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "1. Retry OAuth", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "2. Try API Key instead", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "3. Back to provider selection", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "4. Exit", IO.ANSI.reset()])
    IO.puts("")

    case MenuHelpers.get_menu_choice("Enter your choice (1-4): ", 1..4) do
      {:ok, 1} ->
        execute_oauth_auth(provider)

      {:ok, 2} ->
        execute_api_key_auth(provider)

      {:ok, 3} ->
        {:error, :back_to_provider}

      {:ok, 4} ->
        {:error, :quit}

      {:error, :invalid_choice} ->
        MenuHelpers.display_error("Invalid choice. Please select a number between 1 and 4.")
        :timer.sleep(2000)
        handle_oauth_error(provider, reason)

      {:error, :quit} ->
        {:error, :quit}
    end
  end

  defp validate_auth_credentials(:api_key, _provider, credentials) do
    case Map.get(credentials, :api_key) do
      nil ->
        {:error, "Missing API key in credentials"}

      "" ->
        {:error, "Empty API key in credentials"}

      _api_key ->
        # Could add provider-specific validation here
        :ok
    end
  end

  defp validate_auth_credentials(:oauth, _provider, credentials) do
    case Map.get(credentials, :access_token) do
      nil -> {:error, "Missing access token in OAuth credentials"}
      "" -> {:error, "Empty access token in OAuth credentials"}
      _access_token -> :ok
    end
  end

  defp validate_auth_credentials(:service_account, :google, credentials) do
    case Map.get(credentials, :credentials_path) do
      nil ->
        {:error, "Missing credentials path for service account"}

      path ->
        if File.exists?(path), do: :ok, else: {:error, "Service account file not found"}
    end
  end

  defp validate_auth_credentials(type, provider, _credentials) do
    {:error, "Unsupported authentication type #{type} for provider #{provider}"}
  end

  defp save_auth_preference(provider, method) do
    # Save user's authentication preference for future sessions
    home_dir = System.user_home!()
    maestro_dir = Path.join(home_dir, ".maestro")
    pref_file = Path.join(maestro_dir, "auth_preferences.json")

    # Ensure directory exists
    File.mkdir_p!(maestro_dir)

    # Load existing preferences
    preferences =
      case File.read(pref_file) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, prefs} -> prefs
            {:error, _} -> %{}
          end

        {:error, _} ->
          %{}
      end

    # Update preference for this provider
    updated_preferences = Map.put(preferences, to_string(provider), to_string(method))

    # Save updated preferences
    case Jason.encode(updated_preferences) do
      {:ok, json} ->
        File.write!(pref_file, json)
        # Owner read/write only
        File.chmod!(pref_file, 0o600)

      {:error, _} ->
        # Continue silently if we can't save preferences
        :ok
    end
  rescue
    # Continue silently if we can't save preferences
    _ -> :ok
  end

  defp get_auth_method_description(:api_key), do: "Fast and simple - uses your API key"
  defp get_auth_method_description(:oauth), do: "Secure browser-based authentication"

  defp get_auth_method_description(:device_flow),
    do: "Secure device flow authentication (like Claude Code)"

  defp get_auth_method_description(:service_account),
    do: "Enterprise authentication for Google services"

  defp get_auth_method_description(_method), do: "Authentication method"

  defp format_auth_method(:api_key), do: "API Key"
  defp format_auth_method(:oauth), do: "OAuth (Browser)"
  defp format_auth_method(:device_flow), do: "Device Flow (Recommended)"
  defp format_auth_method(:service_account), do: "Service Account"
  defp format_auth_method(method), do: String.capitalize(to_string(method))

  defp get_provider_name(:anthropic), do: "Claude (Anthropic)"
  defp get_provider_name(:google), do: "Gemini (Google)"
  defp get_provider_name(:openai), do: "ChatGPT (OpenAI)"
  defp get_provider_name(provider), do: String.capitalize(to_string(provider))

  # New functions for enhanced credential management

  defp get_existing_credentials(provider) do
    provider_str = to_string(provider)

    case CredentialStore.list_credentials() do
      [] ->
        []

      all_creds ->
        Enum.filter(all_creds, fn cred -> cred.provider == provider_str end)
    end
  end

  defp proceed_with_auth_method_selection(provider) do
    case get_available_auth_methods(provider) do
      [] ->
        {:error, "No authentication methods available for this provider"}

      methods ->
        display_auth_method_menu(provider, methods)
        handle_auth_method_selection(provider, methods)
    end
  end

  defp display_credential_selection_menu(provider, existing_creds) do
    MenuHelpers.clear_screen()
    provider_name = get_provider_name(provider)
    MenuHelpers.display_title("EXISTING #{String.upcase(provider_name)} CREDENTIALS")

    IO.puts([
      IO.ANSI.bright(),
      "Found existing credentials for #{provider_name}:",
      IO.ANSI.reset()
    ])

    IO.puts("")

    # Display existing credentials as menu options
    existing_creds
    |> Enum.with_index(1)
    |> Enum.each(fn {cred, index} ->
      auth_method_name = format_auth_method(String.to_atom(cred.auth_method))

      status =
        if cred.expires_at && DateTime.compare(cred.expires_at, DateTime.utc_now()) == :lt do
          IO.ANSI.yellow() <> " (Expired)" <> IO.ANSI.reset()
        else
          IO.ANSI.green() <> " (Active)" <> IO.ANSI.reset()
        end

      IO.puts([
        IO.ANSI.faint(),
        "#{index}. #{auth_method_name}#{status}",
        IO.ANSI.reset()
      ])

      if cred.updated_at do
        updated_str = cred.updated_at |> DateTime.to_date() |> Date.to_string()
        IO.puts([IO.ANSI.faint(), "   Last updated: #{updated_str}", IO.ANSI.reset()])
      end

      IO.puts("")
    end)

    # Add options for new authentication
    new_auth_index = length(existing_creds) + 1
    IO.puts([IO.ANSI.faint(), "#{new_auth_index}. Set up new authentication", IO.ANSI.reset()])

    IO.puts([
      IO.ANSI.faint(),
      "#{new_auth_index + 1}. Back to provider selection",
      IO.ANSI.reset()
    ])

    IO.puts("")
  end

  defp handle_credential_selection(provider, existing_creds) do
    max_choice = length(existing_creds) + 2
    prompt = "Enter your choice (1-#{max_choice}): "

    case MenuHelpers.get_menu_choice(prompt, 1..max_choice) do
      {:ok, choice} when choice <= length(existing_creds) ->
        # User selected an existing credential
        selected_cred = Enum.at(existing_creds, choice - 1)
        use_existing_credential(provider, selected_cred)

      {:ok, new_auth_choice} when new_auth_choice == length(existing_creds) + 1 ->
        # User wants to set up new authentication
        proceed_with_auth_method_selection(provider)

      {:ok, _back_choice} ->
        # User wants to go back
        {:error, :back_to_provider}

      {:error, :invalid_choice} ->
        MenuHelpers.display_error(
          "Invalid choice. Please select a number between 1 and #{max_choice}."
        )

        :timer.sleep(2000)
        handle_credential_selection(provider, existing_creds)

      {:error, :quit} ->
        {:error, :quit}
    end
  end

  defp use_existing_credential(provider, cred) do
    MenuHelpers.display_info(
      "Loading existing #{format_auth_method(String.to_atom(cred.auth_method))} credentials..."
    )

    # Retrieve the actual credentials from the store
    case CredentialStore.get_credentials(
           String.to_atom(cred.provider),
           String.to_atom(cred.auth_method)
         ) do
      {:ok, credentials} ->
        # Convert to auth context format expected by the providers
        auth_context = %{
          type: String.to_atom(cred.auth_method),
          provider: String.to_atom(cred.provider),
          credentials: credentials,
          config: %{}
        }

        # Validate the credentials are still working
        case validate_auth_context(auth_context) do
          :ok ->
            MenuHelpers.display_success("Existing credentials loaded successfully!")
            :timer.sleep(1000)
            {:ok, auth_context}

          {:error, reason} ->
            MenuHelpers.display_error("Existing credentials are no longer valid: #{reason}")
            IO.puts("")
            IO.puts([IO.ANSI.bright(), "Options:", IO.ANSI.reset()])
            IO.puts([IO.ANSI.faint(), "1. Set up new authentication", IO.ANSI.reset()])
            IO.puts([IO.ANSI.faint(), "2. Back to credential selection", IO.ANSI.reset()])
            IO.puts("")

            case MenuHelpers.get_menu_choice("Enter your choice (1-2): ", 1..2) do
              {:ok, 1} ->
                proceed_with_auth_method_selection(provider)

              {:ok, 2} ->
                existing_creds = get_existing_credentials(provider)
                handle_credential_selection(provider, existing_creds)

              {:error, :quit} ->
                {:error, :quit}
            end
        end

      {:error, reason} ->
        MenuHelpers.display_error("Failed to load existing credentials: #{reason}")
        proceed_with_auth_method_selection(provider)
    end
  end
end
