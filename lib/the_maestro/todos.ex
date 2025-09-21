defmodule TheMaestro.Todos do
  @moduledoc """
  Redis-backed todo storage keyed by session and thread.

  Key format: the_maestro:todos:<session_id>[:<thread_id>]
  Values: JSON array of %{content, activeForm, status}
  """

  alias TheMaestro.Cache.RedisClient, as: RedisClient

  @prefix "the_maestro:todos"

  @spec list(String.t(), String.t() | nil) :: [map()]
  def list(session_id, thread_id \\ nil) when is_binary(session_id) do
    key = key(session_id, thread_id)

    case RedisClient.command(TheMaestro.Redis, ["GET", key]) do
      {:ok, nil} -> []
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, list} when is_list(list) -> list
          _ -> []
        end

      _ -> []
    end
  end

  @spec put(String.t(), String.t() | nil, [map()]) :: :ok
  def put(session_id, thread_id \\ nil, todos) when is_binary(session_id) and is_list(todos) do
    key = key(session_id, thread_id)
    payload = Jason.encode!(todos)
    _ = RedisClient.command(TheMaestro.Redis, ["SET", key, payload])
    :ok
  end

  @spec clear(String.t(), String.t() | nil) :: :ok
  def clear(session_id, thread_id \\ nil) when is_binary(session_id) do
    key = key(session_id, thread_id)
    _ = RedisClient.command(TheMaestro.Redis, ["DEL", key])
    :ok
  end

  @spec clear_all(String.t()) :: :ok
  def clear_all(session_id) when is_binary(session_id) do
    prefix = Enum.join([@prefix, session_id], ":")
    {:ok, ["0", keys]} = RedisClient.command(TheMaestro.Redis, ["SCAN", "0", "MATCH", prefix <> "*", "COUNT", "1000"])
    keys = List.wrap(keys)
    case keys do
      [] -> :ok
      ks -> _ = RedisClient.command(TheMaestro.Redis, ["DEL" | ks])
    end
    :ok
  end

  defp key(session_id, nil), do: Enum.join([@prefix, session_id], ":")
  defp key(session_id, thread_id), do: Enum.join([@prefix, session_id, thread_id], ":")
end
