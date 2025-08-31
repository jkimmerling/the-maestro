defmodule TheMaestro.Streaming.Message do
  @moduledoc """
  Typed struct for normalized streaming messages emitted by provider handlers.

  All handlers return this struct to ensure consistent downstream processing.
  """

  @typedoc "Message type discriminator"
  @type message_type :: :content | :function_call | :usage | :error | :done

  @typedoc "Opaque usage stats map normalized across providers"
  @type usage_map :: %{
          optional(:prompt_tokens) => non_neg_integer(),
          optional(:completion_tokens) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer()
        }

  @enforce_keys [:type]
  defstruct type: :content,
            content: nil,
            function_call: nil,
            usage: nil,
            error: nil,
            metadata: %{}

  @typedoc "Typed streaming message struct"
  @type t :: %__MODULE__{
          type: message_type(),
          content: String.t() | nil,
          function_call: list(TheMaestro.Streaming.FunctionCall.t()) | nil,
          usage: usage_map() | nil,
          error: String.t() | nil,
          metadata: map()
        }
end
