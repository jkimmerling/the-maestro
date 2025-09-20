defmodule TheMaestro.MCP.Warmup do
  @moduledoc """
  On-boot warmup for MCP tools cache.

  Discovers tools for all enabled MCP servers and populates TheMaestro.MCP.ToolsCache
  so pickers render instantly after startup.
  """

  require Logger
  alias TheMaestro.MCP
  alias TheMaestro.MCP.Client
  alias TheMaestro.MCP.ToolsCache

  def run do
    # Add a small delay to ensure all services are ready
    Process.sleep(2000)

    Logger.info("MCP Warmup: starting…")

    # Test Redis connection first
    case Redix.command(TheMaestro.Redis, ["PING"]) do
      {:ok, "PONG"} ->
        Logger.info("MCP Warmup: Redis connection OK")
        do_warmup()
      error ->
        Logger.error("MCP Warmup: Redis not ready: #{inspect(error)}")
        :ok
    end
  rescue
    e ->
      Logger.error("MCP Warmup failed: #{inspect(e)}")
      Logger.error("Stacktrace: #{Exception.format_stacktrace()}")
  end

  defp do_warmup do
    servers = MCP.list_servers()
    Logger.info("MCP Warmup: found #{length(servers)} servers")

    results =
      Enum.map(servers, fn server ->
        Logger.info("MCP Warmup: checking server #{server.name} (#{server.id})")

        try do
          case ToolsCache.get_with_freshness(server.id, ttl_ms(server)) do
            {:ok, _tools, :fresh} ->
              Logger.info("MCP Warmup: #{server.name} cache is fresh")
              :fresh

            {:ok, tools, :stale} ->
              # Cache is stale, refresh it
              Logger.info("MCP Warmup: refreshing stale cache for #{server.name}, has #{length(tools)} cached tools")
              case Client.discover_server(server) do
                {:ok, %{tools: new_tools}} ->
                  Logger.info("MCP Warmup: discovered #{length(new_tools)} tools for #{server.name}")
                  ToolsCache.put(server.id, new_tools, ttl_ms(server))
                  :refreshed
                error ->
                  Logger.warning("MCP Warmup: Failed to refresh #{server.name}: #{inspect(error)}")
                  :error
              end

            :miss ->
              # No cache, discover and store
              Logger.info("MCP Warmup: no cache for #{server.name}, discovering...")
              case Client.discover_server(server) do
                {:ok, %{tools: tools}} ->
                  Logger.info("MCP Warmup: discovered #{length(tools)} tools for #{server.name}")
                  ToolsCache.put(server.id, tools, ttl_ms(server))
                  :discovered
                error ->
                  Logger.warning("MCP Warmup: Failed to discover #{server.name}: #{inspect(error)}")
                  :error
              end
          end
        rescue
          e ->
            Logger.error("MCP Warmup: Error processing server #{server.name}: #{inspect(e)}")
            :error
        end
      end)

    # Count results
    fresh = Enum.count(results, &(&1 == :fresh))
    refreshed = Enum.count(results, &(&1 == :refreshed))
    discovered = Enum.count(results, &(&1 == :discovered))
    errors = Enum.count(results, &(&1 == :error))

    Logger.info(
      "MCP Warmup: done (#{length(servers)} servers: " <>
      "#{fresh} fresh, #{refreshed} refreshed, #{discovered} discovered, #{errors} errors)"
    )
  end

  defp ttl_ms(%{metadata: %{} = md}), do: (md["tool_cache_ttl_minutes"] || 60) * 60_000
  defp ttl_ms(_), do: 60 * 60_000
end
