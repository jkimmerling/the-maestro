defmodule TheMaestro.TUI.ProviderSelection do
  @moduledoc """
  Provider selection interface for TUI.

  This module handles the provider selection menu, allowing users to choose
  between Claude (Anthropic), Gemini (Google), and ChatGPT (OpenAI).
  """

  alias TheMaestro.TUI.MenuHelpers
  alias TheMaestro.Providers.Auth.ProviderRegistry

  # Provider information for display
  @provider_info %{
    anthropic: %{
      name: "Claude (Anthropic)",
      description: "Advanced reasoning and analysis capabilities",
      auth_methods: [:api_key, :oauth],
      capabilities: "Text, Code, Analysis"
    },
    google: %{
      name: "Gemini (Google)",
      description: "Multimodal AI with strong integration",
      auth_methods: [:api_key, :oauth, :service_account],
      capabilities: "Text, Code, Images, Analysis"
    },
    openai: %{
      name: "ChatGPT (OpenAI)",
      description: "Versatile conversational AI",
      auth_methods: [:api_key, :oauth],
      capabilities: "Text, Code, Images"
    }
  }

  @doc """
  Displays the provider selection menu and handles user choice.

  ## Returns
    - `{:ok, provider_atom}`: User selected a provider
    - `{:error, :quit}`: User chose to quit
    - `{:error, :cancelled}`: User cancelled selection
  """
  @spec select_provider() :: {:ok, atom()} | {:error, atom()}
  def select_provider do
    providers = get_available_providers()
    display_provider_menu(providers)
    handle_provider_selection(providers)
  end

  @doc """
  Gets information about a specific provider.

  ## Parameters
    - `provider`: The provider atom (:anthropic, :google, :openai)

  ## Returns
    Provider information map or nil if not found
  """
  @spec get_provider_info(atom()) :: map() | nil
  def get_provider_info(provider) do
    Map.get(@provider_info, provider)
  end

  @doc """
  Lists all available providers with their capabilities.

  ## Returns
    List of provider atoms
  """
  @spec get_available_providers() :: [atom()]
  def get_available_providers do
    ProviderRegistry.list_providers()
  end

  @doc """
  Shows detailed information about a provider.

  ## Parameters
    - `provider`: The provider atom

  ## Returns
    :ok
  """
  @spec show_provider_details(atom()) :: :ok
  def show_provider_details(provider) do
    case get_provider_info(provider) do
      nil ->
        MenuHelpers.display_error("Provider information not found")

      info ->
        MenuHelpers.clear_screen()
        MenuHelpers.display_title("PROVIDER DETAILS")

        IO.puts([IO.ANSI.bright(), IO.ANSI.cyan(), info.name, IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), info.description, IO.ANSI.reset()])
        IO.puts("")

        IO.puts([IO.ANSI.bright(), "Capabilities:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  #{info.capabilities}", IO.ANSI.reset()])
        IO.puts("")

        IO.puts([IO.ANSI.bright(), "Authentication Methods:", IO.ANSI.reset()])

        info.auth_methods
        |> Enum.each(fn method ->
          method_name = format_auth_method(method)
          IO.puts([IO.ANSI.faint(), "  • #{method_name}", IO.ANSI.reset()])
        end)

        IO.puts("")
    end

    :ok
  end

  # Private helper functions

  defp display_provider_menu(providers) do
    options = Enum.map(providers, fn provider ->
      info = get_provider_info(provider)
      info.name
    end)

    additional_info =
      providers
      |> Enum.with_index(1)
      |> Enum.reduce(%{}, fn {provider, index}, acc ->
        info = get_provider_info(provider)
        Map.put(acc, index, info.description)
      end)
      |> Map.put(length(providers) + 1, "Return to main menu")

    all_options = options ++ ["Back to main menu"]

    MenuHelpers.display_menu("SELECT YOUR LLM PROVIDER", all_options, additional_info)
  end

  defp handle_provider_selection(providers) do
    max_choice = length(providers) + 1
    prompt = "Enter your choice (1-#{max_choice}): "

    case MenuHelpers.get_menu_choice(prompt, 1..max_choice) do
      {:ok, choice} when choice <= length(providers) ->
        provider = Enum.at(providers, choice - 1)
        handle_provider_choice(provider)

      {:ok, _back_choice} ->
        {:error, :cancelled}

      {:error, :invalid_choice} ->
        MenuHelpers.display_error("Invalid choice. Please select a number between 1 and #{max_choice}.")
        :timer.sleep(2000)
        select_provider()

      {:error, :quit} ->
        {:error, :quit}
    end
  end

  defp handle_provider_choice(provider) do
    # Show provider details before confirmation
    show_provider_details(provider)

    MenuHelpers.display_info("You selected: #{get_provider_info(provider).name}")
    IO.puts("")
    IO.puts([IO.ANSI.bright(), "Options:", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "1. Continue with this provider", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "2. Back to provider selection", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "3. Exit", IO.ANSI.reset()])
    IO.puts("")

    case MenuHelpers.get_menu_choice("Enter your choice (1-3): ", 1..3) do
      {:ok, 1} ->
        {:ok, provider}

      {:ok, 2} ->
        select_provider()

      {:ok, 3} ->
        {:error, :quit}

      {:error, :invalid_choice} ->
        MenuHelpers.display_error("Invalid choice. Please select 1, 2, or 3.")
        :timer.sleep(2000)
        handle_provider_choice(provider)

      {:error, :quit} ->
        {:error, :quit}
    end
  end

  defp format_auth_method(:api_key), do: "API Key"
  defp format_auth_method(:oauth), do: "OAuth (Browser-based)"
  defp format_auth_method(:service_account), do: "Service Account"
  defp format_auth_method(method), do: String.capitalize(to_string(method))
end