defmodule TheMaestro.Providers.OpenAI.Models do
  @moduledoc """
  OpenAI models provider stub.

  Uses Req client in Story 0.2; completed in 0.3.
  """
  @behaviour TheMaestro.Providers.Behaviours.Models
  require Logger
  @impl true
  def list_models(_session_id) do
    Logger.debug("OpenAI.Models.list_models/1 stub called")
    {:error, :not_implemented}
  end

  @impl true
  def get_model_info(_session_id, _model_id) do
    Logger.debug("OpenAI.Models.get_model_info/2 stub called")
    {:error, :not_implemented}
  end
end
