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

  @impl true
  def get_model_info(_session_id, _model_id) do
    Logger.debug("Gemini.Models.get_model_info/2 stub called")
    {:error, :not_implemented}
  end
end
