defmodule TheMaestro.Domain.TurnFrame do
  @moduledoc "Value object for a single timeline frame within a turn."

  @enforce_keys [:id, :idx, :at_ms, :role, :kind, :payload]
  defstruct id: nil,
            idx: 0,
            at_ms: 0,
            role: "assistant",
            kind: "assistant_text",
            payload: %{},
            thought?: false,
            collapsed?: true

  @type t :: %__MODULE__{
          id: String.t(),
          idx: non_neg_integer(),
          at_ms: non_neg_integer(),
          role: String.t(),
          kind: String.t(),
          payload: map(),
          thought?: boolean(),
          collapsed?: boolean()
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(%{} = m), do: {:ok, build(m)}

  @spec new!(map()) :: t()
  def new!(%{} = m), do: build(m)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = f) do
    %{
      "id" => f.id,
      "idx" => f.idx,
      "at_ms" => f.at_ms,
      "role" => f.role,
      "kind" => f.kind,
      "payload" => f.payload,
      "thought?" => f.thought?,
      "collapsed?" => f.collapsed?
    }
  end

  defp coerce_int(v, _default) when is_integer(v), do: v
  defp coerce_int(v, _default) when is_float(v), do: trunc(v)

  defp coerce_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} when i >= 0 -> i
      _ -> default
    end
  end

  defp coerce_int(_v, default), do: default

  defp build(m) do
    %__MODULE__{
      id: to_string(get_id(m)),
      idx: get_idx(m),
      at_ms: get_at_ms(m),
      role: to_string(get_role(m)),
      kind: to_string(get_kind(m)),
      payload: get_payload(m),
      thought?: get_thought(m),
      collapsed?: get_collapsed(m)
    }
  end

  defp get_id(m), do: Map.get(m, :id) || Map.get(m, "id") || Ecto.UUID.generate()
  defp get_idx(m), do: coerce_int(Map.get(m, :idx) || Map.get(m, "idx") || 0, 0)

  defp get_at_ms(m),
    do:
      coerce_int(
        Map.get(m, :at_ms) || Map.get(m, "at_ms") || System.monotonic_time(:millisecond),
        System.monotonic_time(:millisecond)
      )

  defp get_role(m), do: Map.get(m, :role) || Map.get(m, "role") || "assistant"
  defp get_kind(m), do: Map.get(m, :kind) || Map.get(m, "kind") || "assistant_text"
  defp get_payload(m), do: Map.get(m, :payload) || Map.get(m, "payload") || %{}
  defp get_thought(m), do: Map.get(m, :thought?) || Map.get(m, "thought?") || false
  defp get_collapsed(m), do: Map.get(m, :collapsed?) || Map.get(m, "collapsed?") || true
end
