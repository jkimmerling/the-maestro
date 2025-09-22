defmodule TheMaestro.Tools.ToolExecOutput do
  @moduledoc """
  Structured execution output for internal flows and provider wrappers.

  This struct is not sent to providers directly; providers still receive
  a JSON string payload compatible with Codex. This struct gives internal
  code a richer container for logging and persistence.
  """

  @enforce_keys [:tool_name, :payload]
  defstruct tool_name: nil,
            payload: nil,
            metadata: %{},
            confirmation: nil

  @type t :: %__MODULE__{
          tool_name: String.t(),
          payload: String.t(),
          metadata: map(),
          confirmation: map() | nil
        }
end
