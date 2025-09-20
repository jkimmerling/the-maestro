defmodule TheMaestro.MCP.RegistryCache do
  @moduledoc false

  alias TheMaestro.Cache.RedisClient, as: RedisClient

  @ttl_ms 300_000
  @prefix "the_maestro:mcp_registry"

  def get(session_id, mcps_hash) when is_binary(session_id) do
    key = cache_key(session_id)

    case RedisClient.command(TheMaestro.Redis, ["GET", key]) do
      {:ok, nil} ->
        :miss

      {:ok, json} ->
        with {:ok, %{"hash" => ^mcps_hash, "decls" => decls, "at_ms" => at}} <-
               Jason.decode(json),
             true <- fresh?(at) do
          {:ok, decls}
        else
          _ -> :stale
        end

      _ ->
        :miss
    end
  end

  def put(session_id, mcps_hash, decls) when is_binary(session_id) do
    key = cache_key(session_id)
    payload = Jason.encode!(%{"hash" => mcps_hash, "decls" => decls, "at_ms" => now_ms()})
    ttl_sec = div(@ttl_ms, 1000)
    _ = RedisClient.command(TheMaestro.Redis, ["SETEX", key, Integer.to_string(ttl_sec), payload])
    :ok
  end

  def invalidate(session_id) when is_binary(session_id) do
    key = cache_key(session_id)
    _ = RedisClient.command(TheMaestro.Redis, ["DEL", key])
    :ok
  end

  defp cache_key(session_id), do: @prefix <> ":" <> session_id

  defp fresh?(at_ms) when is_integer(at_ms), do: now_ms() - at_ms < @ttl_ms
  defp fresh?(_), do: false

  defp now_ms, do: System.monotonic_time(:millisecond)
end
