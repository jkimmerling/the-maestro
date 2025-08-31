defmodule TheMaestro.Providers.Behaviours.Models do
  @moduledoc """
  Behaviour for provider model listing and information retrieval.

  Defines the callbacks required for discovering available models and
  retrieving detailed model information.
  """

  alias TheMaestro.Types

  @type session_id :: Types.session_id()
  @type model_id :: Types.model_id()

  @doc """
  List all available models for the authenticated session.

  ## Parameters

  - `session_id` - Session identifier from authentication

  ## Returns

  - `{:ok, models}` - List of available models
  - `{:error, term()}` - Error details
  """
  @callback list_models(session_id) :: {:ok, [Types.model()]} | {:error, term()}

  @doc """
  Get detailed information about a specific model.

  ## Parameters

  - `session_id` - Session identifier from authentication
  - `model_id` - Model identifier to query

  ## Returns

  - `{:ok, model_info}` - Detailed model information
  - `{:error, term()}` - Error details
  """
  @callback get_model_info(session_id, model_id :: String.t()) ::
              {:ok, model_info :: map()} | {:error, term()}
end
