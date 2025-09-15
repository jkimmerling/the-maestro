defmodule TheMaestro.MCP.RegistryCache do
  @moduledoc false

  @table :mcp_registry_cache
  @ttl_ms 300_000

  def get(session_id, mcps_hash) do
    ensure_table()

    case :ets.lookup(@table, session_id) do
      [{^session_id, %{hash: ^mcps_hash, decls: decls, at_ms: at}}] ->
        if fresh?(at), do: {:ok, decls}, else: :stale

      _ ->
        :miss
    end
  end

  def put(session_id, mcps_hash, decls) do
    ensure_table()
    :ets.insert(@table, {session_id, %{hash: mcps_hash, decls: decls, at_ms: now_ms()}})
    :ok
  end

  def invalidate(session_id) do
    ensure_table()
    :ets.delete(@table, session_id)
    :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
      _ -> :ok
    end
  end

  defp fresh?(at_ms) when is_integer(at_ms), do: now_ms() - at_ms < @ttl_ms
  defp fresh?(_), do: false

  defp now_ms, do: System.monotonic_time(:millisecond)
end
