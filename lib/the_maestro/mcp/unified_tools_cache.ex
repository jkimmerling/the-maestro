defmodule TheMaestro.MCP.UnifiedToolsCache do
  @moduledoc """
  GenServer-based unified cache for all MCP server tools.

  Uses a single Redis key `mcp_tool_list` to store all available MCP tools
  across all servers, organized by provider.

  Automatically refreshes cache every hour and when MCP servers are added/modified.

  Structure: %{
    "openai" => [%{name: "tool", source: :mcp, description: "...", server_label: "Server"}],
    "anthropic" => [...],
    "gemini" => [...]
  }
  """

  use GenServer
  require Logger

  alias TheMaestro.MCP

  @cache_key "mcp_tool_list"
  # 1 hour
  @refresh_interval_ms 3_600_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the unified tool list from cache.
  """
  def get_tools do
    case Redix.command(TheMaestro.Redis, ["GET", @cache_key]) do
      {:ok, nil} ->
        GenServer.call(__MODULE__, :rebuild_cache)

      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"tools" => tools}} when is_map(tools) ->
            {:ok, tools}

          _ ->
            GenServer.call(__MODULE__, :rebuild_cache)
        end

      _ ->
        GenServer.call(__MODULE__, :rebuild_cache)
    end
  end

  @doc """
  Force refresh the cache (called when MCPs are added/modified).
  """
  def refresh_cache do
    GenServer.cast(__MODULE__, :refresh_cache)
  end

  @doc """
  Invalidate the unified cache.
  """
  def invalidate do
    _ = Redix.command(TheMaestro.Redis, ["DEL", @cache_key])
    :ok
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    # Schedule initial cache build
    send(self(), :build_cache)
    # Schedule hourly refresh
    schedule_refresh()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:rebuild_cache, _from, state) do
    result = build_and_store_cache()
    {:reply, result, state}
  end

  @impl true
  def handle_cast(:refresh_cache, state) do
    build_and_store_cache()
    {:noreply, state}
  end

  @impl true
  def handle_info(:build_cache, state) do
    build_and_store_cache()
    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    build_and_store_cache()
    schedule_refresh()
    {:noreply, state}
  end

  # Private functions

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
  end

  defp build_and_store_cache do
    Logger.info("Building unified MCP tools cache")

    tools_by_provider = build_unified_inventory()
    payload = Jason.encode!(%{"tools" => tools_by_provider, "at_ms" => now_ms()})

    case Redix.command(TheMaestro.Redis, ["SET", @cache_key, payload]) do
      {:ok, "OK"} ->
        Logger.info("Unified MCP tools cache updated successfully")
        {:ok, tools_by_provider}

      error ->
        Logger.error("Failed to store unified MCP tools cache: #{inspect(error)}")
        {:error, error}
    end
  end

  defp build_unified_inventory do
    # Get all enabled servers
    enabled_servers = MCP.list_servers(enabled_only?: true)

    # Build inventory for each provider
    providers = [:openai, :anthropic, :gemini]

    for provider <- providers, into: %{} do
      provider_key = Atom.to_string(provider)
      tools = build_tools_for_provider(enabled_servers, provider)
      {provider_key, tools}
    end
  end

  defp build_tools_for_provider(servers, provider) do
    servers
    |> Enum.flat_map(fn server ->
      case discover_server_tools(server) do
        {:ok, tools} ->
          server_label = server.display_name || server.name || "MCP"
          Enum.map(tools, &map_tool_to_inventory(&1, provider, server_label))

        _ ->
          []
      end
    end)
  end

  defp discover_server_tools(server) do
    case MCP.Client.discover_server(server) do
      {:ok, %{tools: tools}} when is_list(tools) ->
        {:ok, tools}

      _ ->
        {:error, :discovery_failed}
    end
  rescue
    _ -> {:error, :discovery_failed}
  end

  defp map_tool_to_inventory(%{"name" => name} = tool, provider, server_label) do
    %{
      name: sanitize_tool_name(name, provider),
      source: :mcp,
      description: tool["description"] || tool["title"],
      server_label: server_label
    }
  rescue
    _ -> nil
  end

  defp map_tool_to_inventory(_, _, _), do: nil

  defp sanitize_tool_name(name, :gemini) when is_binary(name) do
    sanitized = String.replace(name, ~r/[^A-Za-z0-9_.-]/u, "_")
    if String.length(sanitized) <= 63, do: sanitized, else: ellipsize_middle(sanitized, 63)
  end

  defp sanitize_tool_name(name, :anthropic) when is_binary(name) do
    sanitized = String.replace(name, ~r/[^A-Za-z0-9_.-]/u, "_")
    if String.length(sanitized) <= 63, do: sanitized, else: ellipsize_middle(sanitized, 63)
  end

  defp sanitize_tool_name(name, _provider) when is_binary(name), do: name

  defp ellipsize_middle(s, max) when is_integer(max) and max > 3 do
    len = String.length(s)

    if len <= max,
      do: s,
      else:
        String.slice(s, 0, div(max - 3, 2)) <>
          "..." <> String.slice(s, len - (max - 3 - div(max - 3, 2)), max - 3 - div(max - 3, 2))
  end

  defp now_ms, do: System.system_time(:millisecond)
end
