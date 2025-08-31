defmodule TheMaestro.Providers.Behaviours.Auth do
  @moduledoc """
  Behaviour for provider authentication operations (OAuth/API Key).

  Provider modules such as `TheMaestro.Providers.OpenAI.OAuth` or
  `TheMaestro.Providers.OpenAI.APIKey` should implement this behaviour.
  """

  alias TheMaestro.Types

  @typedoc "Session identifier"
  @type session_id :: Types.session_id()

  @callback create_session(keyword()) :: {:ok, session_id} | {:error, term()}
  @callback delete_session(session_id) :: :ok | {:error, term()}
  @callback refresh_tokens(session_id) :: {:ok, map()} | {:error, term()}
end
