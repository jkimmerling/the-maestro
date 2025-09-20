defmodule TheMaestro.MCP.ToolsCache do
  @moduledoc """
  Redis-backed cache for MCP server tools lists.

  - Keyed by `server_id` (UUID)
  - Stores: %{tools: list, at_ms: integer}
  - Default TTL: 3_600_000 ms (1 hour)

  TTL can be customized per server via the MCP Hub by setting
  `metadata["tool_cache_ttl_minutes"]` on the server. Callers should pass
  the desired ttl_ms to `get/2` so we can evaluate freshness accordingly.
  """

  @default_ttl_ms 3_600_000
  @prefix "the_maestro:mcp_tools"

  @doc """
  Get cached tools for `server_id`. Returns {:ok, tools} | :stale | :miss.
  Freshness is evaluated against `ttl_ms` (falls back to 1h if nil).
  """
  def get(server_id, ttl_ms \\ nil) when is_binary(server_id) do
    key = cache_key(server_id)
    ttl = ttl_ms || @default_ttl_ms

    case Redix.command(TheMaestro.Redis, ["GET", key]) do
      {:ok, nil} -> :miss
      {:ok, json} ->
        with {:ok, %{"tools" => tools, "at_ms" => at}} <- Jason.decode(json),
             true <- is_list(tools),
             true <- fresh?(at, ttl) do
          {:ok, tools}
        else
          _ -> :stale
        end
      _ -> :miss
    end
  end

  @doc """
  Get cached tools for `server_id` with freshness info.
  Returns {:ok, tools, :fresh | :stale} | :miss.
  This always returns the data if it exists, regardless of staleness.
  """
  def get_with_freshness(server_id, ttl_ms \\ nil) when is_binary(server_id) do
    key = cache_key(server_id)
    ttl = ttl_ms || @default_ttl_ms

    case Redix.command(TheMaestro.Redis, ["GET", key]) do
      {:ok, nil} -> :miss
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"tools" => tools, "at_ms" => at}} when is_list(tools) ->
            freshness = if fresh?(at, ttl), do: :fresh, else: :stale
            {:ok, tools, freshness}
          _ ->
            :miss
        end
      _ -> :miss
    end
  end

  @doc """
  Put tools list for `server_id` with the given TTL in ms.
  """
  def put(server_id, tools, ttl_ms \\ nil) when is_binary(server_id) and is_list(tools) do
    key = cache_key(server_id)
    payload = Jason.encode!(%{"tools" => tools, "at_ms" => now_ms()})
    ttl_sec = max(div(ttl_ms || @default_ttl_ms, 1000), 1)
    _ = Redix.command(TheMaestro.Redis, ["SETEX", key, Integer.to_string(ttl_sec), payload])
    :ok
  end

  @doc """
  Invalidate cache for `server_id`.
  """
  def invalidate(server_id) when is_binary(server_id) do
    key = cache_key(server_id)
    _ = Redix.command(TheMaestro.Redis, ["DEL", key])
    :ok
  end

  defp cache_key(server_id), do: @prefix <> ":" <> server_id

  defp fresh?(at_ms, ttl_ms) when is_integer(at_ms) and is_integer(ttl_ms) and ttl_ms > 0 do
    now_ms() - at_ms < ttl_ms
  end

  defp now_ms, do: System.system_time(:millisecond)
end
