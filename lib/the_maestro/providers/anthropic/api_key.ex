defmodule TheMaestro.Providers.Anthropic.APIKey do
  @moduledoc """
  Anthropic API Key provider stub for Story 0.2/0.4.
  """
  @behaviour TheMaestro.Providers.Behaviours.Auth
  require Logger
  alias TheMaestro.Types
  @impl true
  @spec create_session(Types.request_opts()) :: {:ok, Types.session_id()} | {:error, term()}
  def create_session(_opts), do: {:error, :not_implemented}
  @impl true
  @spec delete_session(Types.session_id()) :: :ok | {:error, term()}
  def delete_session(_session_id), do: :ok
  @impl true
  @spec refresh_tokens(Types.session_id()) :: {:ok, map()} | {:error, term()}
  def refresh_tokens(_session_id), do: {:error, :not_applicable}
end
