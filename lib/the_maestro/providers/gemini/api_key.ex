defmodule TheMaestro.Providers.Gemini.APIKey do
  @moduledoc """
  Gemini API Key provider stub for Story 0.2/0.5.
  """
  @behaviour TheMaestro.Providers.Behaviours.Auth
  require Logger
  @impl true
  def create_session(_opts), do: {:error, :not_implemented}
  @impl true
  def delete_session(_session_id), do: :ok
  @impl true
  def refresh_tokens(_session_id), do: {:error, :not_applicable}
end
