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
    Logger.info("MCP Warmup: starting…")
    servers = MCP.list_servers()

    Enum.each(servers, fn server ->
      with :miss <- ToolsCache.get(server.id, ttl_ms(server)),
           {:ok, %{tools: tools}} <- Client.discover_server(server) do
        _ = ToolsCache.put(server.id, tools, ttl_ms(server))
      else
        {:ok, _} -> :ok
        _ -> :ok
      end
    end)

    Logger.info("MCP Warmup: done (#{length(servers)} server(s))")
  rescue
    e -> Logger.error("MCP Warmup failed: #{inspect(e)}")
  end

  defp ttl_ms(%{metadata: %{} = md}), do: (md["tool_cache_ttl_minutes"] || 60) * 60_000
  defp ttl_ms(_), do: 60 * 60_000
end
