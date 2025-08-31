defmodule TheMaestro.Streaming.FunctionCall do
  @moduledoc """
  Typed struct for standardized function/tool calls emitted by provider handlers.
  """

  @enforce_keys [:id, :function]
  defstruct id: nil,
            type: "function",
            function: nil

  @typedoc "Function call payload"
  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          function: TheMaestro.Streaming.Function.t()
        }
end
defmodule TheMaestro.Streaming.Function do
  @moduledoc """
  Typed struct for function details (name + JSON arguments).
  """

  @enforce_keys [:name, :arguments]
  defstruct name: nil,
            arguments: ""

  @typedoc "Function details"
  @type t :: %__MODULE__{
          name: String.t(),
          arguments: String.t()
        }
end
