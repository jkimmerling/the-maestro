defmodule TheMaestro.Domain.CombinedChat do
  @moduledoc """
  Versioned value object for the combined chat payload we persist in ChatEntry.

  Stored as JSONB; this module provides helpers to map to/from the canonical
  shape and reserve room for evolution via `version`.
  """

  @enforce_keys [:version, :messages]
  defstruct version: "v1", messages: [], events: []

  @type t :: %__MODULE__{version: String.t(), messages: [map()], events: [map()]}

  @spec new(keyword() | map()) :: t()
  def new(opts) when is_list(opts), do: struct!(__MODULE__, Enum.into(opts, %{}))
  def new(%{} = map), do: from_map(map)

  @spec from_map(map()) :: t()
  def from_map(%{} = map) do
    %__MODULE__{
      version: Map.get(map, "version") || Map.get(map, :version) || "v1",
      messages: Map.get(map, "messages") || Map.get(map, :messages) || [],
      events: Map.get(map, "events") || Map.get(map, :events) || []
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = cc) do
    %{"version" => cc.version, "messages" => cc.messages, "events" => cc.events}
  end
end
