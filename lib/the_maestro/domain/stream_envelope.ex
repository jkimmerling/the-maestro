defmodule TheMaestro.Domain.StreamEnvelope do
  @moduledoc "Typed wrapper for session stream events."

  alias TheMaestro.Domain.StreamEvent

  @enforce_keys [:session_id, :stream_id, :event]
  defstruct session_id: nil,
            stream_id: nil,
            event: %StreamEvent{type: :content},
            at_ms: nil

  @type t :: %__MODULE__{
          session_id: String.t(),
          stream_id: String.t(),
          event: StreamEvent.t(),
          at_ms: integer() | nil
        }
end
