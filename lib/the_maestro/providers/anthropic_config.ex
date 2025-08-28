defmodule TheMaestro.Providers.AnthropicConfig do
  @moduledoc """
  Configuration structure for Anthropic API authentication.

  Provides structured access to Anthropic API configuration values
  with validation and default values matching llxprt reference.
  """

  defstruct [
    :api_key,
    :version,
    :beta,
    :user_agent,
    :accept,
    :client_version,
    :base_url
  ]

  @type t :: %__MODULE__{
          api_key: String.t(),
          version: String.t(),
          beta: String.t(),
          user_agent: String.t(),
          accept: String.t(),
          client_version: String.t(),
          base_url: String.t()
        }

  @doc """
  Loads Anthropic configuration from application config.

  ## Returns

    * `{:ok, %AnthropicConfig{}}` - Configuration loaded successfully
    * `{:error, :missing_api_key}` - API key not provided or empty
    
  ## Examples

      iex> TheMaestro.Providers.AnthropicConfig.load()
      {:ok, %TheMaestro.Providers.AnthropicConfig{api_key: "sk-...", ...}}
      
      # When ANTHROPIC_API_KEY environment variable is not set
      iex> TheMaestro.Providers.AnthropicConfig.load()
      {:error, :missing_api_key}
  """
  @spec load() :: {:ok, t()} | {:error, :missing_api_key}
  def load do
    config = Application.get_env(:the_maestro, :anthropic, [])

    case Keyword.get(config, :api_key) do
      nil ->
        {:error, :missing_api_key}

      "" ->
        {:error, :missing_api_key}

      api_key ->
        {:ok,
         %__MODULE__{
           api_key: api_key,
           version: Keyword.get(config, :version, "2023-06-01"),
           beta: Keyword.get(config, :beta, "messages-2023-12-15"),
           user_agent: Keyword.get(config, :user_agent, "llxprt/1.0"),
           accept: "application/json",
           client_version: Keyword.get(config, :client_version, "1.0.0"),
           base_url: Keyword.get(config, :base_url, "https://api.anthropic.com")
         }}
    end
  end
end
