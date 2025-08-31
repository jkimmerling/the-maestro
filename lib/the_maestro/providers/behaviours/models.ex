defmodule TheMaestro.Providers.Behaviours.Models do
  @moduledoc """
  Behaviour for provider model listing and related operations.
  """

  alias TheMaestro.Types

  @type session_id :: Types.session_id()
  @type model_id :: Types.model_id()

  @callback list_models(session_id) :: {:ok, [model_id]} | {:error, term()}
end
