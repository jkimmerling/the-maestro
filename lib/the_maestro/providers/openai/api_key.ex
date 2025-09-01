defmodule TheMaestro.Providers.OpenAI.APIKey do
  @moduledoc """
  OpenAI API Key provider stub.

  Note: Scaffold for Story 0.2 (Req migration) and 0.3 implementation.
  """
  @behaviour TheMaestro.Providers.Behaviours.Auth
  require Logger
  alias TheMaestro.Types
  @impl true
  @spec create_session(Types.request_opts()) :: {:ok, Types.session_id()} | {:error, term()}
  def create_session(_opts) do
    Logger.debug("OpenAI.APIKey.create_session/1 stub called")
    {:error, :not_implemented}
  end

  @impl true
  @spec delete_session(Types.session_id()) :: :ok | {:error, term()}
  def delete_session(_session_id) do
    Logger.debug("OpenAI.APIKey.delete_session/1 stub called")
    :ok
  end

  @impl true
  @spec refresh_tokens(Types.session_id()) :: {:ok, map()} | {:error, term()}
  def refresh_tokens(_session_id) do
    Logger.debug("OpenAI.APIKey.refresh_tokens/1 stub called")
    {:error, :not_applicable}
  end
end
