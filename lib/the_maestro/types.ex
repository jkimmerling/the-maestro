defmodule TheMaestro.Types do
  @moduledoc """
  Shared domain type aliases used across providers and interfaces.

  Centralizing aliases helps ensure consistent typespecs across modules.
  """

  @typedoc "Supported provider identifiers"
  @type provider :: :openai | :anthropic | :gemini

  @typedoc "Supported authentication types"
  @type auth_type :: :oauth | :api_key

  @typedoc "Opaque session identifier"
  @type session_id :: String.t()

  @typedoc "Model identifier"
  @type model_id :: String.t()

  @typedoc "Model information structure"
  @type model :: %{
          id: String.t(),
          name: String.t(),
          capabilities: [String.t()]
        }

  @typedoc "Provider capability descriptor"
  @type provider_capabilities :: %{
          auth_types: [auth_type()],
          features: [atom()]
        }
end
