defmodule TheMaestro.MCP.ToolsCache do
  @moduledoc """
  In-memory cache for MCP server tools lists.

  - Keyed by `server_id` (UUID)
  - Stores: %{tools: list, at_ms: integer, ttl_ms: integer}
  - Default TTL: 3_600_000 ms (1 hour)

  TTL can be customized per server via the MCP Hub by setting
  `metadata["tool_cache_ttl_minutes"]` on the server. Callers should pass
  the desired ttl_ms to `get/2` so we can evaluate freshness accordingly.
  """

  @table :mcp_tools_cache
  @default_ttl_ms 3_600_000

  @doc """
  Get cached tools for `server_id`. Returns {:ok, tools} | :stale | :miss.
  Freshness is evaluated against `ttl_ms` (falls back to 1h if nil).
  """
  def get(server_id, ttl_ms \\ nil) when is_binary(server_id) do
    ensure()
    ttl = ttl_ms || @default_ttl_ms

    case :ets.lookup(@table, server_id) do
      [{^server_id, %{tools: tools, at_ms: at}}] when is_list(tools) ->
        if fresh?(at, ttl), do: {:ok, tools}, else: :stale

      _ ->
        :miss
    end
  end

  @doc """
  Put tools list for `server_id` with the given TTL in ms.
  """
  def put(server_id, tools, ttl_ms \\ nil) when is_binary(server_id) and is_list(tools) do
    ensure()

    :ets.insert(
      @table,
      {server_id, %{tools: tools, at_ms: now_ms(), ttl_ms: ttl_ms || @default_ttl_ms}}
    )

    :ok
  end

  @doc """
  Invalidate cache for `server_id`.
  """
  def invalidate(server_id) when is_binary(server_id) do
    ensure()
    :ets.delete(@table, server_id)
    :ok
  end

  defp ensure do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
      _ -> :ok
    end
  end

  defp fresh?(at_ms, ttl_ms) when is_integer(at_ms) and is_integer(ttl_ms) and ttl_ms > 0 do
    now_ms() - at_ms < ttl_ms
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
