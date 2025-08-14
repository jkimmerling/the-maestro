defmodule TheMaestro.TUI.OAuthHandler do
  @moduledoc """
  OAuth authentication handler for TUI environments.

  This module provides OAuth authentication flow optimized for terminal
  interfaces, including browser-based authorization and device code flows.
  """

  alias TheMaestro.TUI.MenuHelpers
  alias TheMaestro.Providers.{Anthropic, Gemini, OpenAI}
  alias TheMaestro.TUI.EmbeddedServer

  @doc """
  Handles OAuth authentication for a specific provider.

  ## Parameters
    - `provider`: The provider atom (:anthropic, :google, :openai)

  ## Returns
    - `{:ok, auth_context}`: Successfully authenticated
    - `{:error, reason}`: Authentication failed or user cancelled
  """
  @spec handle_oauth_auth(atom()) :: {:ok, map()} | {:error, atom() | String.t()}
  def handle_oauth_auth(provider) do
    display_oauth_instructions(provider)

    case initiate_oauth_flow(provider) do
      {:ok, flow_data} ->
        handle_oauth_completion(provider, flow_data)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Initiates the OAuth flow for a provider.

  ## Parameters
    - `provider`: The provider atom

  ## Returns
    - `{:ok, flow_data}`: OAuth flow initiated
    - `{:error, reason}`: Failed to initiate
  """
  @spec initiate_oauth_flow(atom()) :: {:ok, map()} | {:error, String.t()}
  def initiate_oauth_flow(provider) do
    case provider do
      :anthropic ->
        initiate_anthropic_oauth()

      :google ->
        initiate_google_oauth()

      :openai ->
        initiate_openai_oauth()

      _ ->
        {:error, "OAuth not supported for provider: #{provider}"}
    end
  end

  @doc """
  Checks if a provider supports OAuth authentication.

  ## Parameters
    - `provider`: The provider atom

  ## Returns
    Boolean indicating OAuth support
  """
  @spec supports_oauth?(atom()) :: boolean()
  def supports_oauth?(provider) do
    provider in [:anthropic, :google, :openai]
  end

  @doc """
  Starts OAuth callback server for browser-based OAuth flows.

  ## Returns
    - `{:ok, callback_url}`: Server started successfully
    - `{:error, reason}`: Failed to start server
  """
  @spec start_oauth_server() :: {:ok, String.t()} | {:error, String.t()}
  def start_oauth_server do
    case EmbeddedServer.start_link() do
      {:ok, _pid} ->
        port = EmbeddedServer.get_port()
        callback_url = "http://localhost:#{port}/oauth/callback"
        {:ok, callback_url}

      {:error, reason} ->
        {:error, "Failed to start OAuth server: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets OAuth result from embedded server.

  ## Returns
    - `{:ok, auth_data}`: Authorization completed
    - `{:error, :pending}`: Still waiting for authorization
    - `{:error, reason}`: Authorization failed
  """
  @spec get_oauth_result() :: {:ok, map()} | {:error, atom() | String.t()}
  def get_oauth_result do
    # This would need to be implemented based on the specific OAuth flow
    # For now, return pending to indicate polling is needed
    {:error, :pending}
  end

  # Private helper functions

  defp display_oauth_instructions(provider) do
    MenuHelpers.clear_screen()
    MenuHelpers.display_title("OAUTH AUTHENTICATION")

    provider_name = get_provider_name(provider)
    IO.puts([IO.ANSI.bright(), "OAuth Authentication for #{provider_name}", IO.ANSI.reset()])
    IO.puts("")

    IO.puts([
      IO.ANSI.faint(),
      "OAuth provides secure authentication without storing API keys.",
      IO.ANSI.reset()
    ])

    IO.puts([
      IO.ANSI.faint(),
      "You'll be redirected to your browser to sign in.",
      IO.ANSI.reset()
    ])

    IO.puts("")

    display_oauth_benefits()
  end

  defp display_oauth_benefits do
    IO.puts([IO.ANSI.bright(), "Benefits of OAuth:", IO.ANSI.reset()])
    IO.puts([IO.ANSI.green(), "  ✓ No need to manage API keys", IO.ANSI.reset()])
    IO.puts([IO.ANSI.green(), "  ✓ Secure browser-based authentication", IO.ANSI.reset()])
    IO.puts([IO.ANSI.green(), "  ✓ Easy revocation of access", IO.ANSI.reset()])
    IO.puts([IO.ANSI.green(), "  ✓ Automatic token refresh", IO.ANSI.reset()])
    IO.puts("")
  end

  defp initiate_anthropic_oauth do
    MenuHelpers.display_info("Starting Anthropic OAuth flow...")

    case Anthropic.initiate_oauth_flow() do
      {:ok, %{auth_url: auth_url, state: state, code_verifier: code_verifier}} ->
        flow_data = %{
          provider: :anthropic,
          auth_url: auth_url,
          state: state,
          code_verifier: code_verifier
        }

        display_browser_instructions(flow_data)
        {:ok, flow_data}

      {:error, reason} ->
        {:error, "Failed to start OAuth flow: #{inspect(reason)}"}
    end
  end

  defp initiate_google_oauth do
    MenuHelpers.display_info("Starting Google OAuth flow...")

    case Gemini.device_authorization_flow() do
      {:ok,
       %{auth_url: auth_url, state: state, code_verifier: code_verifier, polling_fn: polling_fn}} ->
        flow_data = %{
          provider: :google,
          auth_url: auth_url,
          state: state,
          code_verifier: code_verifier,
          polling_fn: polling_fn
        }

        display_browser_instructions(flow_data)
        {:ok, flow_data}

      {:error, reason} ->
        {:error, "Failed to start OAuth flow: #{inspect(reason)}"}
    end
  end

  defp initiate_openai_oauth do
    MenuHelpers.display_info("Starting OpenAI OAuth flow...")

    case OpenAI.initiate_oauth_flow() do
      {:ok, %{auth_url: auth_url, state: state, code_verifier: code_verifier}} ->
        flow_data = %{
          provider: :openai,
          auth_url: auth_url,
          state: state,
          code_verifier: code_verifier
        }

        display_browser_instructions(flow_data)
        {:ok, flow_data}

      {:error, reason} ->
        {:error, "Failed to start OAuth flow: #{inspect(reason)}"}
    end
  end

  defp display_browser_instructions(flow_data) do
    provider_name = get_provider_name(flow_data.provider)

    IO.puts([IO.ANSI.bright(), "Browser Authorization Required", IO.ANSI.reset()])
    IO.puts("")

    IO.puts([IO.ANSI.bright(), "1. Open this URL in your browser:", IO.ANSI.reset()])

    IO.puts([
      "   ",
      IO.ANSI.bright(),
      IO.ANSI.cyan(),
      flow_data.auth_url,
      IO.ANSI.reset()
    ])

    IO.puts("")

    IO.puts([IO.ANSI.bright(), "2. Sign in with your #{provider_name} account", IO.ANSI.reset()])
    IO.puts("")

    IO.puts([IO.ANSI.bright(), "3. Authorize The Maestro TUI", IO.ANSI.reset()])
    IO.puts("")

    if Map.has_key?(flow_data, :polling_fn) do
      display_device_code_instructions(flow_data)
    else
      display_callback_instructions()
    end
  end

  defp display_device_code_instructions(flow_data) do
    case flow_data do
      %{device_code: device_code} ->
        IO.puts([IO.ANSI.bright(), "4. Enter this device code when prompted:", IO.ANSI.reset()])

        IO.puts([
          "   ",
          IO.ANSI.bright(),
          IO.ANSI.yellow(),
          device_code,
          IO.ANSI.reset()
        ])

        IO.puts("")

      _ ->
        IO.puts([IO.ANSI.bright(), "4. Follow the authorization prompts", IO.ANSI.reset()])
        IO.puts("")
    end

    IO.puts([IO.ANSI.faint(), "Waiting for authorization...", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "Press Ctrl+C to cancel", IO.ANSI.reset()])
    IO.puts("")
  end

  defp display_callback_instructions do
    IO.puts([
      IO.ANSI.bright(),
      "4. You'll be redirected back to this application",
      IO.ANSI.reset()
    ])

    IO.puts("")
    IO.puts([IO.ANSI.faint(), "Waiting for authorization...", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "Press Ctrl+C to cancel", IO.ANSI.reset()])
    IO.puts("")
  end

  defp handle_oauth_completion(provider, flow_data) do
    case provider do
      :google ->
        handle_google_oauth_completion(flow_data)

      _ ->
        handle_standard_oauth_completion(provider, flow_data)
    end
  end

  defp handle_google_oauth_completion(
         %{polling_fn: polling_fn, code_verifier: code_verifier} = _flow_data
       ) do
    display_authorization_spinner()

    case polling_fn.() do
      "" ->
        {:error, "No authorization code provided"}

      auth_code ->
        case Gemini.complete_device_authorization(auth_code, code_verifier) do
          {:ok, auth_info} ->
            MenuHelpers.display_success("Google OAuth authorization successful!")
            :timer.sleep(1000)

            auth_context = %{
              type: :oauth,
              provider: :google,
              credentials: %{
                access_token: auth_info.access_token,
                user_email: auth_info[:user_email] || "google_user"
              },
              config: %{}
            }

            {:ok, auth_context}

          {:error, reason} ->
            {:error, "Failed to complete Google OAuth: #{inspect(reason)}"}
        end
    end
  end

  defp handle_standard_oauth_completion(provider, flow_data) do
    # Start embedded server to handle OAuth callback
    case start_oauth_server() do
      {:ok, callback_url} ->
        MenuHelpers.display_info("OAuth callback server started at #{callback_url}")
        poll_for_oauth_completion(provider, flow_data)

      {:error, reason} ->
        {:error, "Failed to start OAuth callback server: #{inspect(reason)}"}
    end
  end

  defp poll_for_oauth_completion(provider, flow_data, timeout \\ 300_000) do
    start_time = :erlang.system_time(:millisecond)

    poll_oauth_status(provider, flow_data, start_time, timeout)
  end

  defp poll_oauth_status(provider, flow_data, start_time, timeout) do
    current_time = :erlang.system_time(:millisecond)
    elapsed = current_time - start_time

    if elapsed > timeout do
      {:error, "OAuth authentication timed out"}
    else
      case check_oauth_completion(provider, flow_data) do
        {:ok, auth_context} ->
          MenuHelpers.display_success("OAuth authentication successful!")
          :timer.sleep(1000)
          {:ok, auth_context}

        {:error, :pending} ->
          :timer.sleep(2000)
          poll_oauth_status(provider, flow_data, start_time, timeout)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp check_oauth_completion(provider, flow_data) do
    case get_oauth_result() do
      {:ok, auth_data} ->
        complete_provider_oauth(provider, flow_data, auth_data)

      {:error, :pending} ->
        {:error, :pending}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp complete_provider_oauth(provider, flow_data, auth_data) do
    case provider do
      :anthropic ->
        complete_anthropic_oauth(flow_data, auth_data)

      :openai ->
        complete_openai_oauth(flow_data, auth_data)

      _ ->
        {:error, "Unsupported provider for OAuth completion"}
    end
  end

  defp complete_anthropic_oauth(flow_data, auth_data) do
    case Anthropic.complete_oauth_flow(flow_data.code_verifier, auth_data.code, auth_data.state) do
      {:ok, auth_info} ->
        auth_context = %{
          type: :oauth,
          provider: :anthropic,
          credentials: %{
            access_token: auth_info.access_token,
            user_email: auth_info[:user_email] || "anthropic_user"
          },
          config: %{}
        }

        {:ok, auth_context}

      {:error, reason} ->
        {:error, "Failed to complete Anthropic OAuth: #{inspect(reason)}"}
    end
  end

  defp complete_openai_oauth(flow_data, auth_data) do
    case OpenAI.complete_oauth_flow(flow_data.code_verifier, auth_data.code, auth_data.state) do
      {:ok, auth_info} ->
        auth_context = %{
          type: :oauth,
          provider: :openai,
          credentials: %{
            access_token: auth_info.access_token,
            user_email: auth_info[:user_email] || "openai_user"
          },
          config: %{}
        }

        {:ok, auth_context}

      {:error, reason} ->
        {:error, "Failed to complete OpenAI OAuth: #{inspect(reason)}"}
    end
  end

  defp display_authorization_spinner do
    spinner_chars = ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]

    # Show spinner for a few seconds while polling
    Stream.cycle(spinner_chars)
    |> Stream.take(20)
    |> Stream.each(fn char ->
      IO.write(["\r", IO.ANSI.cyan(), char, " Waiting for authorization...", IO.ANSI.reset()])
      :timer.sleep(200)
    end)
    |> Stream.run()

    IO.write(["\r", String.duplicate(" ", 50), "\r"])
  end

  defp get_provider_name(:anthropic), do: "Claude (Anthropic)"
  defp get_provider_name(:google), do: "Gemini (Google)"
  defp get_provider_name(:openai), do: "ChatGPT (OpenAI)"
  defp get_provider_name(provider), do: String.capitalize(to_string(provider))
end
