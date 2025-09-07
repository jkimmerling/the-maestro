defmodule TheMaestro.Types do
  @moduledoc """
  Shared domain type aliases used across providers and interfaces.

  Centralizing aliases helps ensure consistent typespecs across modules.
  """

  @typedoc "Supported provider identifiers"
  @type provider :: atom()

  @typedoc "Supported authentication types"
  @type auth_type :: :oauth | :api_key

  @typedoc "Opaque session identifier"
  @type session_id :: String.t()

  @typedoc "Model identifier"
  @type model_id :: String.t()

  @typedoc "Model information structure"
  @type model :: TheMaestro.Models.Model.t()

  @typedoc "Provider capability descriptor"
  @type provider_capabilities :: %{
          auth_types: [auth_type()],
          features: [atom()]
        }

  @typedoc "Opaque provider credentials map (API keys, OAuth tokens, etc.)"
  @type credentials :: map()

  @typedoc "Standard request options passed to HTTP helpers"
  @type request_opts :: keyword()
end
