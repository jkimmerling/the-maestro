defmodule TheMaestro.TUI.ModelSelection do
  @moduledoc """
  Model selection interface for TUI after authentication.

  This module handles the dynamic model selection menu, fetching available
  models from the authenticated provider and allowing users to choose.
  """

  alias TheMaestro.TUI.MenuHelpers
  alias TheMaestro.Providers.{Anthropic, Gemini, OpenAI}
  alias TheMaestro.Models.Model

  # Model information for display
  @model_info %{
    # Anthropic models
    "claude-3-5-sonnet-20241022" => %{
      name: "Claude 3.5 Sonnet",
      description: "Most capable model with enhanced reasoning",
      capabilities: "Text, Code, Analysis, Vision",
      context_length: "200K tokens",
      recommended: true
    },
    "claude-3-opus-20240229" => %{
      name: "Claude 3 Opus",
      description: "Highest intelligence and capability",
      capabilities: "Text, Code, Analysis, Vision",
      context_length: "200K tokens"
    },
    "claude-3-haiku-20240307" => %{
      name: "Claude 3 Haiku",
      description: "Fastest and most efficient",
      capabilities: "Text, Code, Analysis, Vision",
      context_length: "200K tokens"
    },

    # Gemini models
    "gemini-1.5-pro" => %{
      name: "Gemini 1.5 Pro",
      description: "Advanced reasoning and multimodal capabilities",
      capabilities: "Text, Code, Images, Audio, Video",
      context_length: "1M tokens",
      recommended: true
    },
    "gemini-1.5-flash" => %{
      name: "Gemini 1.5 Flash",
      description: "Fast and efficient multimodal AI",
      capabilities: "Text, Code, Images, Audio, Video",
      context_length: "1M tokens"
    },
    "gemini-pro" => %{
      name: "Gemini Pro",
      description: "Versatile performance across tasks",
      capabilities: "Text, Code, Images",
      context_length: "32K tokens"
    },

    # OpenAI models
    "gpt-4o" => %{
      name: "GPT-4o",
      description: "Most capable GPT-4 model with vision",
      capabilities: "Text, Code, Images, Audio",
      context_length: "128K tokens",
      recommended: true
    },
    "gpt-4o-mini" => %{
      name: "GPT-4o Mini",
      description: "Faster and more affordable GPT-4",
      capabilities: "Text, Code, Images",
      context_length: "128K tokens"
    },
    "gpt-4-turbo" => %{
      name: "GPT-4 Turbo",
      description: "Advanced GPT-4 with latest knowledge",
      capabilities: "Text, Code, Images",
      context_length: "128K tokens"
    }
  }

  @doc """
  Handles model selection for an authenticated provider.

  ## Parameters
    - `provider`: The provider atom (:anthropic, :google, :openai)
    - `auth_context`: The authentication context from successful auth

  ## Returns
    - `{:ok, {provider, model, auth_context}}`: Model selected successfully
    - `{:error, reason}`: Selection failed or user cancelled
  """
  @spec select_model(atom(), map()) ::
          {:ok, {atom(), String.t(), map()}} | {:error, atom() | String.t()}
  def select_model(provider, auth_context) do
    MenuHelpers.display_loading("Loading available models...")

    case fetch_available_models(provider, auth_context) do
      {:ok, models} when models != [] ->
        display_model_menu(provider, models)
        handle_model_selection(provider, models, auth_context)

      {:ok, []} ->
        MenuHelpers.display_error("No models available for this provider")
        {:error, "No models available"}

      {:error, reason} ->
        MenuHelpers.display_error("Failed to fetch models: #{reason}")
        handle_model_fetch_error(provider, auth_context, reason)
    end
  end

  @doc """
  Gets information about a specific model.

  ## Parameters
    - `model_or_id`: The model identifier string or model map

  ## Returns
    Model information map or nil if not found
  """
  @spec get_model_info(String.t() | Model.t()) :: map() | nil
  def get_model_info(%Model{id: model_id}), do: Map.get(@model_info, model_id)
  def get_model_info(model_id) when is_binary(model_id), do: Map.get(@model_info, model_id)
  def get_model_info(_), do: nil

  @doc """
  Shows detailed information about a model.

  ## Parameters
    - `model_id`: The model identifier
    - `provider`: The provider atom

  ## Returns
    :ok
  """
  @spec show_model_details(String.t(), atom()) :: :ok
  def show_model_details(model_id, provider) do
    case get_model_info(model_id) do
      nil ->
        MenuHelpers.display_error("Model information not found")
        display_basic_model_info(model_id, provider)

      info ->
        MenuHelpers.clear_screen()
        MenuHelpers.display_title("MODEL DETAILS")

        IO.puts([IO.ANSI.bright(), IO.ANSI.cyan(), info.name, IO.ANSI.reset()])

        if info[:recommended] do
          IO.puts([IO.ANSI.bright(), IO.ANSI.green(), "(Recommended)", IO.ANSI.reset()])
        end

        IO.puts("")

        IO.puts([IO.ANSI.faint(), info.description, IO.ANSI.reset()])
        IO.puts("")

        IO.puts([IO.ANSI.bright(), "Capabilities:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  #{info.capabilities}", IO.ANSI.reset()])
        IO.puts("")

        IO.puts([IO.ANSI.bright(), "Context Length:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  #{info.context_length}", IO.ANSI.reset()])
        IO.puts("")

        display_provider_specific_model_info(model_id, provider)
    end

    :ok
  end

  # Private helper functions

  defp fetch_available_models(provider, auth_context) do
    case provider do
      :anthropic ->
        fetch_anthropic_models(auth_context)

      :google ->
        fetch_gemini_models(auth_context)

      :openai ->
        fetch_openai_models(auth_context)

      _ ->
        {:error, "Unsupported provider for model fetching"}
    end
  end

  defp fetch_anthropic_models(auth_context) do
    case Anthropic.list_models(auth_context) do
      {:ok, models} ->
        {:ok, models}

      {:error, _reason} ->
        # Fallback to known models if API call fails
        fallback_models = [
          "claude-3-5-sonnet-20241022",
          "claude-3-opus-20240229",
          "claude-3-haiku-20240307"
        ]

        {:ok, fallback_models}
    end
  rescue
    _ ->
      # Fallback to known models on any error
      fallback_models = [
        "claude-3-5-sonnet-20241022",
        "claude-3-opus-20240229",
        "claude-3-haiku-20240307"
      ]

      {:ok, fallback_models}
  end

  defp fetch_gemini_models(auth_context) do
    case Gemini.list_models(auth_context) do
      {:ok, models} ->
        {:ok, models}

      {:error, _reason} ->
        # Fallback to known models if API call fails
        fallback_models = [
          "gemini-1.5-pro",
          "gemini-1.5-flash",
          "gemini-pro"
        ]

        {:ok, fallback_models}
    end
  rescue
    _ ->
      # Fallback to known models on any error
      fallback_models = [
        "gemini-1.5-pro",
        "gemini-1.5-flash",
        "gemini-pro"
      ]

      {:ok, fallback_models}
  end

  defp fetch_openai_models(auth_context) do
    case OpenAI.list_models(auth_context) do
      {:ok, models} ->
        {:ok, models}

      {:error, _reason} ->
        # Fallback to known models if API call fails
        fallback_models = [
          "gpt-4o",
          "gpt-4o-mini",
          "gpt-4-turbo"
        ]

        {:ok, fallback_models}
    end
  rescue
    _ ->
      # Fallback to known models on any error
      fallback_models = [
        "gpt-4o",
        "gpt-4o-mini",
        "gpt-4-turbo"
      ]

      {:ok, fallback_models}
  end

  defp display_model_menu(provider, models) do
    provider_name = get_provider_name(provider)

    options = Enum.map(models, &format_model_option/1)

    additional_info =
      models
      |> Enum.with_index(1)
      |> Enum.reduce(%{}, fn {model, index}, acc ->
        case get_model_info(model) do
          nil -> 
            # Handle case where model info is not found - extract name from Model struct
            model_display = case model do
              %Model{id: id} -> id
              model_id when is_binary(model_id) -> model_id
              _ -> inspect(model)
            end
            Map.put(acc, index, "Model: #{model_display}")
          info -> Map.put(acc, index, info.description)
        end
      end)
      |> Map.put(length(models) + 1, "Back to authentication method")
      |> Map.put(length(models) + 2, "Back to provider selection")

    all_options = options ++ ["Back to authentication", "Back to provider selection"]

    MenuHelpers.display_menu(
      "AVAILABLE #{String.upcase(provider_name)} MODELS",
      all_options,
      additional_info
    )
  end

  defp handle_model_selection(provider, models, auth_context) do
    max_choice = length(models) + 2
    prompt = "Enter your choice (1-#{max_choice}): "

    case MenuHelpers.get_menu_choice(prompt, 1..max_choice) do
      {:ok, choice} when choice <= length(models) ->
        model = Enum.at(models, choice - 1)
        handle_model_choice(provider, model, auth_context)

      {:ok, back_auth_choice} when back_auth_choice == length(models) + 1 ->
        {:error, :back_to_auth}

      {:ok, _back_provider_choice} ->
        {:error, :back_to_provider}

      {:error, :invalid_choice} ->
        MenuHelpers.display_error(
          "Invalid choice. Please select a number between 1 and #{max_choice}."
        )

        :timer.sleep(2000)
        select_model(provider, auth_context)

      {:error, :quit} ->
        {:error, :quit}
    end
  end

  defp handle_model_choice(provider, model, auth_context) do
    # Show model details before confirmation
    show_model_details(model, provider)

    model_name =
      case get_model_info(model) do
        nil -> 
          # Extract name from Model struct or fallback to string
          case model do
            %Model{name: name} when not is_nil(name) -> name
            %Model{id: id} -> id
            model_id when is_binary(model_id) -> model_id
            _ -> inspect(model)
          end
        info -> info.name
      end

    MenuHelpers.display_info("You selected: #{model_name}")
    IO.puts("")
    IO.puts([IO.ANSI.bright(), "Options:", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "1. Continue with this model", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "2. Back to model selection", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "3. Exit", IO.ANSI.reset()])
    IO.puts("")

    case MenuHelpers.get_menu_choice("Enter your choice (1-3): ", 1..3) do
      {:ok, 1} ->
        {:ok, {provider, model, auth_context}}

      {:ok, 2} ->
        select_model(provider, auth_context)

      {:ok, 3} ->
        {:error, :quit}

      {:error, :invalid_choice} ->
        MenuHelpers.display_error("Invalid choice. Please select 1, 2, or 3.")
        :timer.sleep(2000)
        handle_model_choice(provider, model, auth_context)

      {:error, :quit} ->
        {:error, :quit}
    end
  end

  defp handle_model_fetch_error(provider, auth_context, _reason) do
    IO.puts([IO.ANSI.bright(), "Options:", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "1. Retry loading models", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "2. Use default model", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "3. Back to authentication", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "4. Exit", IO.ANSI.reset()])
    IO.puts("")

    case MenuHelpers.get_menu_choice("Enter your choice (1-4): ", 1..4) do
      {:ok, 1} ->
        select_model(provider, auth_context)

      {:ok, 2} ->
        default_model = get_default_model(provider)
        {:ok, {provider, default_model, auth_context}}

      {:ok, 3} ->
        {:error, :back_to_auth}

      {:ok, 4} ->
        {:error, :quit}

      {:error, :invalid_choice} ->
        MenuHelpers.display_error("Invalid choice. Please select a number between 1 and 4.")
        :timer.sleep(2000)
        handle_model_fetch_error(provider, auth_context, "fetch failed")

      {:error, :quit} ->
        {:error, :quit}
    end
  end

  defp get_default_model(:anthropic), do: "claude-3-5-sonnet-20241022"
  defp get_default_model(:google), do: "gemini-1.5-pro"
  defp get_default_model(:openai), do: "gpt-4o"
  defp get_default_model(_), do: "default"

  defp format_model_option(model) do
    case get_model_info(model) do
      nil ->
        # Handle case where model info is not found - extract name from Model struct
        case model do
          %Model{name: name} when not is_nil(name) -> name
          %Model{id: id} -> id
          model_id when is_binary(model_id) -> model_id
          _ -> inspect(model)
        end

      info ->
        if info[:recommended], do: "#{info.name} (Recommended)", else: info.name
    end
  end

  defp display_basic_model_info(model, provider) do
    provider_name = get_provider_name(provider)
    
    # Extract model ID from Model struct or string
    model_id = case model do
      %Model{id: id} -> id
      model_id when is_binary(model_id) -> model_id
      _ -> inspect(model)
    end
    
    IO.puts([IO.ANSI.bright(), "Model: #{model_id}", IO.ANSI.reset()])
    IO.puts([IO.ANSI.faint(), "Provider: #{provider_name}", IO.ANSI.reset()])
    IO.puts("")
  end

  defp display_provider_specific_model_info(model_id, provider) do
    case provider do
      :anthropic ->
        display_anthropic_model_info(model_id)

      :google ->
        display_gemini_model_info(model_id)

      :openai ->
        display_openai_model_info(model_id)

      _ ->
        :ok
    end
  end

  defp display_anthropic_model_info(model_id) do
    case model_id do
      "claude-3-5-sonnet-20241022" ->
        IO.puts([IO.ANSI.bright(), "Special Features:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Enhanced reasoning and analysis", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Superior code understanding", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Advanced tool use", IO.ANSI.reset()])

      "claude-3-opus-20240229" ->
        IO.puts([IO.ANSI.bright(), "Special Features:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Highest intelligence level", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Complex reasoning tasks", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Creative writing excellence", IO.ANSI.reset()])

      "claude-3-haiku-20240307" ->
        IO.puts([IO.ANSI.bright(), "Special Features:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Fastest response times", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Most cost-effective", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Great for quick tasks", IO.ANSI.reset()])

      _ ->
        :ok
    end

    IO.puts("")
  end

  defp display_gemini_model_info(model_id) do
    case model_id do
      "gemini-1.5-pro" ->
        IO.puts([IO.ANSI.bright(), "Special Features:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • 1 million token context", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Multimodal capabilities", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Advanced reasoning", IO.ANSI.reset()])

      "gemini-1.5-flash" ->
        IO.puts([IO.ANSI.bright(), "Special Features:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Fastest Gemini model", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Efficient multimodal processing", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Good for real-time applications", IO.ANSI.reset()])

      "gemini-pro" ->
        IO.puts([IO.ANSI.bright(), "Special Features:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Balanced performance", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Text and image understanding", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Versatile applications", IO.ANSI.reset()])

      _ ->
        :ok
    end

    IO.puts("")
  end

  defp display_openai_model_info(model_id) do
    case model_id do
      "gpt-4o" ->
        IO.puts([IO.ANSI.bright(), "Special Features:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Most capable GPT-4", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Vision and audio support", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Improved reasoning", IO.ANSI.reset()])

      "gpt-4o-mini" ->
        IO.puts([IO.ANSI.bright(), "Special Features:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Faster than GPT-4o", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • More affordable", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Good performance/cost balance", IO.ANSI.reset()])

      "gpt-4-turbo" ->
        IO.puts([IO.ANSI.bright(), "Special Features:", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Latest knowledge cutoff", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • JSON mode support", IO.ANSI.reset()])
        IO.puts([IO.ANSI.faint(), "  • Function calling", IO.ANSI.reset()])

      _ ->
        :ok
    end

    IO.puts("")
  end

  defp get_provider_name(:anthropic), do: "Claude (Anthropic)"
  defp get_provider_name(:google), do: "Gemini (Google)"
  defp get_provider_name(:openai), do: "ChatGPT (OpenAI)"
  defp get_provider_name(provider), do: String.capitalize(to_string(provider))
end
