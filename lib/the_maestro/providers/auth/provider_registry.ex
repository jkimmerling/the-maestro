defmodule TheMaestro.Providers.Auth.ProviderRegistry do
  @moduledoc """
  Registry for authentication providers and their capabilities.

  This module manages the registration and discovery of authentication providers,
  keeping track of which providers support which authentication methods.
  """

  alias TheMaestro.Providers.Auth.ProviderAuth

  # Provider module mapping
  @providers %{
    anthropic: TheMaestro.Providers.Auth.AnthropicAuth,
    google: TheMaestro.Providers.Auth.GoogleAuth,
    openai: TheMaestro.Providers.Auth.OpenAIAuth
  }

  @doc """
  Lists all registered providers.

  ## Returns
    List of provider atoms
  """
  @spec list_providers() :: [ProviderAuth.provider()]
  def list_providers do
    Map.keys(@providers)
  end

  @doc """
  Gets the implementation module for a provider.

  ## Parameters
    - `provider`: The provider identifier

  ## Returns
    - `{:ok, module}`: Provider module found
    - `{:error, :not_found}`: Provider not registered
  """
  @spec get_provider_module(ProviderAuth.provider()) :: {:ok, module()} | {:error, :not_found}
  def get_provider_module(provider) do
    case Map.get(@providers, provider) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  @doc """
  Gets the available authentication methods for a provider.

  ## Parameters
    - `provider`: The provider identifier

  ## Returns
    List of available authentication methods
  """
  @spec get_provider_methods(ProviderAuth.provider()) :: [ProviderAuth.auth_method()]
  def get_provider_methods(provider) do
    case get_provider_module(provider) do
      {:ok, module} -> module.get_available_methods(provider)
      {:error, :not_found} -> []
    end
  end

  @doc """
  Checks if a provider supports a specific authentication method.

  ## Parameters
    - `provider`: The provider identifier
    - `method`: The authentication method

  ## Returns
    Boolean indicating support
  """
  @spec supports_method?(ProviderAuth.provider(), ProviderAuth.auth_method()) :: boolean()
  def supports_method?(provider, method) do
    method in get_provider_methods(provider)
  end

  @doc """
  Validates that a provider exists and supports the requested method.

  ## Parameters
    - `provider`: The provider identifier
    - `method`: The authentication method

  ## Returns
    - `:ok`: Provider and method are valid
    - `{:error, reason}`: Invalid provider or method
  """
  @spec validate_provider_method(ProviderAuth.provider(), ProviderAuth.auth_method()) ::
          :ok | {:error, term()}
  def validate_provider_method(provider, method) do
    cond do
      provider not in list_providers() ->
        {:error, :invalid_provider}

      not supports_method?(provider, method) ->
        {:error, :unsupported_method}

      true ->
        :ok
    end
  end
end
