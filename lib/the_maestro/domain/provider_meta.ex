defmodule TheMaestro.Domain.ProviderMeta do
  @moduledoc """
  Canonical provider/session metadata used across streaming and persistence.

  Construct via `new/1` or `new!/1` to normalize provider/auth values and
  enforce invariants once at the boundary.
  """

  @enforce_keys [:provider, :auth_type, :auth_name]
  defstruct provider: :openai,
            auth_type: :api_key,
            auth_name: "",
            model_id: nil,
            session_uuid: nil

  @type provider :: :openai | :anthropic | :gemini | atom()
  @type auth_type :: :oauth | :api_key
  @type t :: %__MODULE__{
          provider: provider(),
          auth_type: auth_type(),
          auth_name: String.t(),
          model_id: String.t() | nil,
          session_uuid: String.t() | nil
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(params) when is_map(params) do
    with {:ok, provider} <- normalize_provider(Map.get(params, :provider) || Map.get(params, "provider")),
         {:ok, auth_type} <- normalize_auth_type(Map.get(params, :auth_type) || Map.get(params, "auth_type")),
         {:ok, auth_name} <- normalize_auth_name(Map.get(params, :auth_name) || Map.get(params, "auth_name")) do
      {:ok,
       %__MODULE__{
         provider: provider,
         auth_type: auth_type,
         auth_name: auth_name,
         model_id: Map.get(params, :model_id) || Map.get(params, "model_id"),
         session_uuid: Map.get(params, :session_uuid) || Map.get(params, "session_uuid")
       }}
    else
      {:error, _} = err -> err
    end
  end

  @spec new!(map()) :: t()
  def new!(params) do
    case new(params) do
      {:ok, meta} -> meta
      {:error, reason} -> raise ArgumentError, "invalid ProviderMeta: #{inspect(reason)}"
    end
  end

  @spec normalize_provider(atom() | String.t() | nil) :: {:ok, provider()} | {:error, term()}
  defp normalize_provider(nil), do: {:ok, :openai}
  defp normalize_provider(p) when is_atom(p), do: {:ok, p}

  defp normalize_provider(p) when is_binary(p) do
    allowed = TheMaestro.Provider.list_providers()
    allowed_str = Enum.map(allowed, &Atom.to_string/1)
    if p in allowed_str, do: {:ok, String.to_existing_atom(p)}, else: {:ok, :openai}
  end

  @spec normalize_auth_type(auth_type() | String.t() | nil) :: {:ok, auth_type()} | {:error, term()}
  defp normalize_auth_type(:oauth), do: {:ok, :oauth}
  defp normalize_auth_type(:api_key), do: {:ok, :api_key}
  defp normalize_auth_type("oauth"), do: {:ok, :oauth}
  defp normalize_auth_type("api_key"), do: {:ok, :api_key}
  defp normalize_auth_type(nil), do: {:ok, :api_key}
  defp normalize_auth_type(other), do: {:error, {:invalid_auth_type, other}}

  @spec normalize_auth_name(term()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_auth_name(name) when is_binary(name) and name != "", do: {:ok, name}
  defp normalize_auth_name(name) when is_binary(name), do: {:ok, name}
  defp normalize_auth_name(nil), do: {:ok, "default"}
  defp normalize_auth_name(other), do: {:error, {:invalid_auth_name, other}}
end
