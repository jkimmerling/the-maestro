defmodule TheMaestro.Providers.Capabilities do
  @moduledoc """
  Provider capability descriptor used by the universal provider interface.
  """

  alias TheMaestro.Types

  @enforce_keys [:provider, :auth_types, :features]
  defstruct provider: nil,
            auth_types: [],
            features: [],
            limits: %{}

  @typedoc "Typed capability struct describing supported auth and features"
  @type t :: %__MODULE__{
          provider: Types.provider(),
          auth_types: [Types.auth_type()],
          features: [atom()],
          limits: map()
        }
end
