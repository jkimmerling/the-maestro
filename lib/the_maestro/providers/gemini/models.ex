defmodule TheMaestro.Providers.Gemini.Models do
  @moduledoc """
  Gemini models provider stub for Story 0.2/0.5.
  """
  @behaviour TheMaestro.Providers.Behaviours.Models
  require Logger
  @impl true
  def list_models(_session_id) do
    Logger.debug("Gemini.Models.list_models/1 stub called")
    {:error, :not_implemented}
  end
end
