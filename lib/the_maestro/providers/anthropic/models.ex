defmodule TheMaestro.Providers.Anthropic.Models do
  @moduledoc """
  Anthropic models provider stub for Story 0.2/0.4.
  """
  @behaviour TheMaestro.Providers.Behaviours.Models
  require Logger
  @impl true
  def list_models(_session_id) do
    Logger.debug("Anthropic.Models.list_models/1 stub called")
    {:error, :not_implemented}
  end
end
