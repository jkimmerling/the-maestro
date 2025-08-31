defmodule TheMaestro.Providers.Behaviours.Streaming do
  @moduledoc """
  Behaviour for provider chat/completions streaming operations.
  """

  alias TheMaestro.Types

  @typedoc "Chat messages list (provider-agnostic)"
  @type messages :: [map()]
  @type session_id :: Types.session_id()

  @callback stream_chat(session_id, messages, keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}
end
