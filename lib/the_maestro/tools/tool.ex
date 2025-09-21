defmodule TheMaestro.Tools.Tool do
  @moduledoc """
  Behaviour for executable tools in the unified runtime.

  Implementations must return Codex-compatible payloads:
  {:ok, json_string} on success or {:error, reason} on failure.
  """

  @callback run(args :: map(), opts :: keyword()) :: {:ok, String.t()} | {:error, String.t()}

  @callback meta() :: %{
              optional(:name) => String.t(),
              optional(:description) => String.t(),
              optional(:confirm) => boolean(),
              optional(:args_schema) => map()
            }
end
