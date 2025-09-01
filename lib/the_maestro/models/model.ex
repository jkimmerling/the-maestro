defmodule TheMaestro.Models.Model do
  @moduledoc """
  Typed struct representing a model returned by provider listings.

  Replaces ad-hoc map representations to satisfy AC-TYPES requirements.
  """

  @enforce_keys [:id]
  defstruct id: "", name: "", capabilities: []

  @typedoc "Model struct"
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          capabilities: [String.t()]
        }
end
