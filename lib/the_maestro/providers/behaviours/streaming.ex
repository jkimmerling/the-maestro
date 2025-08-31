defmodule TheMaestro.Providers.Behaviours.Streaming do
  @moduledoc """
  Behaviour for provider chat/completions streaming operations.

  Defines the callbacks required for streaming chat completions including
  event parsing and state management.
  """

  alias TheMaestro.Types

  @typedoc "Chat messages list (provider-agnostic)"
  @type messages :: [map()]
  @type session_id :: Types.session_id()

  @doc """
  Stream chat completion with real-time response.

  ## Parameters

  - `session_id` - Session identifier from authentication
  - `messages` - List of message maps
  - `opts` - Additional options (model, temperature, etc.)

  ## Returns

  - `{:ok, stream}` - Enumerable stream of events
  - `{:error, term()}` - Error details
  """
  @callback stream_chat(session_id, messages, keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  @doc """
  Parse streaming event and update state.

  ## Parameters

  - `event` - Raw event map from stream
  - `state` - Current parser state

  ## Returns

  - `{messages, new_state}` - Parsed messages and updated state
  """
  @callback parse_stream_event(event :: map(), state :: map()) ::
              {messages :: [map()], new_state :: map()}
end
