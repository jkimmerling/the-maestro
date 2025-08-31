defmodule TheMaestro.Providers.OpenAI.OAuth do
  @moduledoc """
  OpenAI OAuth provider stub.

  Note: This is a scaffold for Story 0.2 (Req migration) and 0.3 (OpenAI provider).
  Implement real logic using the Req client factory and streaming adapter.
  """
  @behaviour TheMaestro.Providers.Behaviours.Auth
  require Logger
  @impl true
  def create_session(_opts) do
    Logger.debug("OpenAI.OAuth.create_session/1 stub called")
    {:error, :not_implemented}
  end

  @impl true
  def delete_session(_session_id) do
    Logger.debug("OpenAI.OAuth.delete_session/1 stub called")
    :ok
  end

  @impl true
  def refresh_tokens(_session_id) do
    Logger.debug("OpenAI.OAuth.refresh_tokens/1 stub called")
    {:error, :not_implemented}
  end
end
