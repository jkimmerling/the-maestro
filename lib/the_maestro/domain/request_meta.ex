defmodule TheMaestro.Domain.RequestMeta do
  @moduledoc """
  Canonical request metadata captured for a turn.
  """

  alias TheMaestro.Domain.{ProviderMeta, Usage}

  @enforce_keys [:provider_meta]
  defstruct provider_meta: nil, usage: nil

  @type t :: %__MODULE__{provider_meta: ProviderMeta.t(), usage: Usage.t() | nil}

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(m) when is_map(m) do
    with {:ok, pm} <- build_provider_meta(m),
         {:ok, u} <- build_usage(m) do
      {:ok, %__MODULE__{provider_meta: pm, usage: u}}
    else
      {:error, _} = err -> err
    end
  end

  @spec new!(map()) :: t()
  def new!(m) do
    case new(m) do
      {:ok, meta} -> meta
      {:error, reason} -> raise ArgumentError, "invalid RequestMeta: #{inspect(reason)}"
    end
  end

  defp build_provider_meta(m) do
    pmap =
      m
      |> Map.take([:provider, :auth_type, :auth_name, :model_id, :session_uuid])
      |> Map.merge(%{
        provider: m[:provider] || m["provider"],
        auth_type: m[:auth_type] || m["auth_type"],
        auth_name: m[:auth_name] || m["auth_name"],
        model_id: m[:model_id] || m["model_id"],
        session_uuid: m[:session_uuid] || m["session_uuid"]
      })

    case ProviderMeta.new(pmap) do
      {:ok, pm} -> {:ok, pm}
      {:error, reason} -> {:error, {:provider_meta, reason}}
    end
  end

  defp build_usage(m) do
    case Map.get(m, :usage) || Map.get(m, "usage") do
      nil -> {:ok, nil}
      %{} = u -> Usage.new(u)
      other -> {:error, {:invalid_usage, other}}
    end
  end
end
