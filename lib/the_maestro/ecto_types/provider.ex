defmodule TheMaestro.EctoTypes.Provider do
  @moduledoc """
  Ecto type that persists provider identifiers as strings while exposing atoms in structs.

  This removes code-time allowlists and avoids DB enum churn while keeping
  the in-app API ergonomic with atoms (e.g., :openai).
  """

  @behaviour Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def embed_as(_format), do: :self

  @impl true
  def equal?(a, b), do: to_string(a) == to_string(b)

  @impl true
  def cast(value) when is_atom(value), do: {:ok, value}
  def cast(value) when is_binary(value), do: {:ok, String.to_atom(value)}
  def cast(_), do: :error

  @impl true
  def dump(value) when is_atom(value), do: {:ok, Atom.to_string(value)}
  def dump(value) when is_binary(value), do: {:ok, value}
  def dump(_), do: :error

  @impl true
  def load(value) when is_binary(value) do
    # Convert to atom for in-app usage. This is safe within the bounded set of providers
    # controlled by the application. For unknown providers, we intentionally create the atom.
    {:ok, String.to_atom(value)}
  end

  def load(_), do: :error
end
