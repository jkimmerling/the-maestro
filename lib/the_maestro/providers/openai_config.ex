defmodule TheMaestro.Providers.OpenAIConfig do
  @moduledoc """
  Configuration structure for OpenAI API authentication.

  Provides structured access to OpenAI API configuration values
  with validation and default values for Bearer token authentication.
  """

  defstruct [
    :api_key,
    :organization_id,
    :beta_version,
    :user_agent,
    :accept,
    :client_version,
    :base_url
  ]

  @type t :: %__MODULE__{
          api_key: String.t(),
          organization_id: String.t(),
          beta_version: String.t(),
          user_agent: String.t(),
          accept: String.t(),
          client_version: String.t(),
          base_url: String.t()
        }

  @doc """
  Loads OpenAI configuration from application config.

  ## Returns

    * `{:ok, %OpenAIConfig{}}` - Configuration loaded successfully
    * `{:error, :missing_api_key}` - API key not provided or empty
    * `{:error, :missing_org_id}` - Organization ID not provided or empty
    
  ## Examples

      iex> TheMaestro.Providers.OpenAIConfig.load()
      {:ok, %TheMaestro.Providers.OpenAIConfig{api_key: "sk-...", ...}}
      
      # When OPENAI_API_KEY environment variable is not set
      iex> TheMaestro.Providers.OpenAIConfig.load()
      {:error, :missing_api_key}

      # When OPENAI_ORG_ID environment variable is not set  
      iex> TheMaestro.Providers.OpenAIConfig.load()
      {:error, :missing_org_id}
  """
  @spec load() :: {:ok, t()} | {:error, :missing_api_key | :missing_org_id}
  def load do
    config = Application.get_env(:the_maestro, :openai, [])

    with {:ok, api_key} <- validate_api_key(config),
         {:ok, organization_id} <- validate_organization_id(config) do
      {:ok,
       %__MODULE__{
         api_key: api_key,
         organization_id: organization_id,
         beta_version: Keyword.get(config, :beta_version, "assistants v2"),
         user_agent: Keyword.get(config, :user_agent, "llxprt/1.0"),
         accept: "application/json",
         client_version: Keyword.get(config, :client_version, "1.0.0"),
         base_url: Keyword.get(config, :base_url, "https://api.openai.com")
       }}
    end
  end

  # Private helper to validate API key
  @spec validate_api_key(Keyword.t()) :: {:ok, String.t()} | {:error, :missing_api_key}
  defp validate_api_key(config) do
    case Keyword.get(config, :api_key) do
      nil -> {:error, :missing_api_key}
      "" -> {:error, :missing_api_key}
      api_key when is_binary(api_key) -> {:ok, api_key}
    end
  end

  # Private helper to validate organization ID
  @spec validate_organization_id(Keyword.t()) ::
          {:ok, String.t()} | {:error, :missing_org_id}
  defp validate_organization_id(config) do
    case Keyword.get(config, :organization_id) do
      nil -> {:error, :missing_org_id}
      "" -> {:error, :missing_org_id}
      org_id when is_binary(org_id) -> {:ok, org_id}
    end
  end
end
