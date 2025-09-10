defmodule TheMaestro.Domain.Usage do
  @moduledoc """
  Canonical token usage across providers.
  """

  @enforce_keys [:prompt_tokens, :completion_tokens, :total_tokens]
  defstruct prompt_tokens: 0, completion_tokens: 0, total_tokens: 0

  @type t :: %__MODULE__{
          prompt_tokens: non_neg_integer(),
          completion_tokens: non_neg_integer(),
          total_tokens: non_neg_integer()
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(m) when is_map(m) do
    p = get_int(m, [:prompt_tokens, "prompt_tokens"], 0)
    c = get_int(m, [:completion_tokens, "completion_tokens"], 0)
    t = get_int(m, [:total_tokens, "total_tokens"], p + c)
    {:ok, %__MODULE__{prompt_tokens: p, completion_tokens: c, total_tokens: t}}
  end

  @spec new!(map()) :: t()
  def new!(m) do
    {:ok, u} = new(m)
    u
  end

  defp get_int(m, keys, default) do
    keys
    |> Enum.find_value(fn k -> Map.get(m, k) end)
    |> case do
      nil -> default
      v when is_integer(v) and v >= 0 -> v
      v when is_binary(v) ->
        case Integer.parse(v) do
          {i, _} when i >= 0 -> i
          _ -> default
        end

      _ -> default
    end
  end
end
