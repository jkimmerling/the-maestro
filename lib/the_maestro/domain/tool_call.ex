defmodule TheMaestro.Domain.ToolCall do
  @moduledoc """
  Canonical representation of a tool (function) call emitted by a provider.
  """

  @enforce_keys [:id, :name, :arguments]
  defstruct id: nil, name: nil, arguments: ""

  @type t :: %__MODULE__{id: String.t(), name: String.t(), arguments: String.t()}

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(m) when is_map(m) do
    id = Map.get(m, :id) || Map.get(m, "id")
    name = Map.get(m, :name) || Map.get(m, "name")
    args = Map.get(m, :arguments) || Map.get(m, "arguments") || ""

    with true <- is_binary(id) or {:error, :missing_id},
         true <- is_binary(name) or {:error, :missing_name},
         true <- is_binary(args) or {:error, :invalid_arguments} do
      {:ok, %__MODULE__{id: id, name: name, arguments: args}}
    else
      {:error, _} = err -> err
    end
  end

  @spec new!(map()) :: t()
  def new!(m) do
    case new(m) do
      {:ok, t} -> t
      {:error, reason} -> raise ArgumentError, "invalid ToolCall: #{inspect(reason)}"
    end
  end
end
