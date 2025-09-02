defmodule TheMaestro.OAuthState do
  @moduledoc """
  In-memory store for OAuth transient state → session context.

  Stores mapping of `state` => %{provider, session_name, pkce_params} so that the
  callback server can complete token exchange with the same PKCE used to generate
  the OAuth URL.
  """

  use Agent

  @type t :: %{
          optional(String.t()) => %{
            provider: atom(),
            session_name: String.t(),
            pkce_params: map()
          }
        }

  @name __MODULE__

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: @name)
  end

  @spec put(String.t(), %{provider: atom(), session_name: String.t(), pkce_params: map()}) :: :ok
  def put(state, value) when is_binary(state) and is_map(value) do
    Agent.update(@name, &Map.put(&1, state, value))
  end

  @spec get(String.t()) :: map() | nil
  def get(state) when is_binary(state) do
    Agent.get(@name, &Map.get(&1, state))
  end

  @spec take(String.t()) :: map() | nil
  def take(state) when is_binary(state) do
    Agent.get_and_update(@name, fn m -> {Map.get(m, state), Map.delete(m, state)} end)
  end

  @spec delete(String.t()) :: :ok
  def delete(state) when is_binary(state) do
    Agent.update(@name, &Map.delete(&1, state))
  end
end
