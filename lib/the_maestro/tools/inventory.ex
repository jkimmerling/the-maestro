defmodule TheMaestro.Tools.Inventory do
  @moduledoc """
  Centralized inventory of available tools per provider for a given session.

  Exposes a simplified list of tool entries combining built-ins and
  MCP-discovered tools for the session.

  Returned entries have the shape:
    [%{name: binary(), source: :builtin | :mcp, description: binary() | nil}]
  """

  alias TheMaestro.Conversations
  alias TheMaestro.MCP
  alias TheMaestro.MCP.Servers
  alias TheMaestro.MCP.UnifiedToolsCache
  alias TheMaestro.Tools.ToolSurface

  @type provider :: :openai | :anthropic | :gemini
  @type item :: %{name: String.t(), source: :builtin | :mcp, description: String.t() | nil}

  @spec list_for_provider(String.t() | nil, provider()) :: [item()]
  def list_for_provider(session_id, provider) when provider in [:openai, :anthropic, :gemini] do
    ToolSurface.list(session_id, provider)
  end

  @doc """
  Build inventory for a provider using the unified cache.
  Returns all available MCP tools from the unified cache for the specified provider.
  """
  @spec list_for_provider_with_servers([String.t()], provider(), keyword()) :: [item()]
  def list_for_provider_with_servers(server_ids, provider, opts \\ [])
      when provider in [:openai, :anthropic, :gemini] do
    entries = load_servers(server_ids)

    builtins = builtin_inventory(provider)
    mcp = mcp_inventory_for_servers(entries, provider, opts)

    merge_prefer_mcp(builtins, mcp)
  end

  # Return the list of names currently allowed for this session/provider, if present.
  # If no allowed list is persisted for the provider, returns :absent.
  @spec allowed_for_provider(String.t(), provider()) :: {:present, [String.t()]} | :absent
  def allowed_for_provider(session_id, provider) when is_binary(session_id) do
    prov_key = Atom.to_string(provider)

    case Conversations.get_session!(session_id) do
      %Conversations.Session{tools: %{"allowed" => %{} = allowed}} ->
        case Map.fetch(allowed, prov_key) do
          {:ok, list} when is_list(list) -> {:present, Enum.map(list, &to_string/1)}
          _ -> :absent
        end

      _ ->
        :absent
    end
  rescue
    _ -> :absent
  end

  defp load_servers(ids) do
    ids
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.map(&safe_get_server/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn server ->
      label = server_label(server)

      %{
        server: server,
        label: label,
        normalized_label: normalize_label(label)
      }
    end)
  end

  defp safe_get_server(id) do
    MCP.get_server!(id)
  rescue
    _ -> nil
  end

  defp builtin_inventory(provider) do
    provider
    |> ToolSurface.list_builtins()
    |> Enum.map(fn %{name: name, description: desc} ->
      %{name: name, description: desc, source: :builtin}
    end)
  end

  defp mcp_inventory_for_servers([], provider, opts) do
    cached_mcp_tools(%{}, provider, opts)
  end

  defp mcp_inventory_for_servers(entries, provider, opts) do
    labels = Map.new(entries, fn entry -> {entry.normalized_label, entry} end)

    cached = cached_mcp_tools(labels, provider, opts)

    cached_labels =
      cached
      |> Enum.map(&normalize_label(Map.get(&1, :server_label)))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    missing =
      labels
      |> Map.drop(MapSet.to_list(cached_labels))
      |> Enum.map(fn {_key, entry} -> entry end)

    discovered =
      Enum.flat_map(missing, fn entry ->
        discover_server_tools(entry, provider, opts)
      end)

    dedup_by_name(cached ++ discovered)
  end

  defp cached_mcp_tools(labels, provider, opts) do
    provider_key = Atom.to_string(provider)

    fetch_fun = Keyword.get(opts, :cache_fetch_fun, fn -> UnifiedToolsCache.get_tools() end)

    case fetch_fun.() do
      tools_by_provider when is_map(tools_by_provider) ->
        tools_by_provider
        |> Map.get(provider_key, [])
        |> Enum.map(&normalize_inventory_item/1)
        |> Enum.reject(&is_nil/1)
        |> filter_by_labels(labels)

      {:ok, tools_by_provider} ->
        tools_by_provider
        |> Map.get(provider_key, [])
        |> Enum.map(&normalize_inventory_item/1)
        |> Enum.reject(&is_nil/1)
        |> filter_by_labels(labels)

      _ ->
        []
    end
  end

  defp discover_server_tools(%{server: %Servers{} = server, label: label}, provider, opts) do
    discover_fun = Keyword.get(opts, :discover_fun, &MCP.Client.discover_server/1)

    case discover_fun.(server) do
      {:ok, %{tools: tools}} when is_list(tools) ->
        tools
        |> Enum.map(&map_tool_to_inventory(&1, provider, label))
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp normalize_inventory_item(nil), do: nil

  defp normalize_inventory_item(item) when is_map(item) do
    item
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, normalize_key(key), normalize_value(key, value))
    end)
    |> case do
      %{name: name} = map when is_binary(name) -> map
      _ -> nil
    end
  end

  defp normalize_inventory_item(_), do: nil

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key("name"), do: :name
  defp normalize_key("description"), do: :description
  defp normalize_key("source"), do: :source
  defp normalize_key("server_label"), do: :server_label
  defp normalize_key(other) when is_binary(other), do: String.to_atom(other)

  defp normalize_value(key, value) when key in [:source, "source"] do
    case value do
      val when val in [:mcp, "mcp"] -> :mcp
      _ -> value
    end
  end

  defp normalize_value(_key, value), do: value

  defp filter_by_labels(items, labels) when map_size(labels) == 0, do: items

  defp filter_by_labels(items, labels) do
    Enum.flat_map(items, &filter_item_by_label(&1, labels))
  end

  defp filter_item_by_label(%{source: :mcp} = item, labels) do
    item
    |> Map.get(:server_label)
    |> normalize_label()
    |> relabel_item(item, labels)
  end

  defp filter_item_by_label(_item, _labels), do: []

  defp map_tool_to_inventory(%{"name" => name} = tool, provider, label) when is_binary(name) do
    %{
      name: sanitize_tool_name(name, provider),
      description: tool["description"] || tool["title"],
      source: :mcp,
      server_label: label
    }
  rescue
    _ -> nil
  end

  defp map_tool_to_inventory(_, _, _), do: nil

  defp server_label(%Servers{} = server) do
    server.display_name || server.name || "MCP"
  end

  defp normalize_label(label) when is_binary(label) do
    label
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_label(_), do: nil

  defp relabel_item(nil, _item, _labels), do: []

  defp relabel_item(normalized, item, labels) do
    case Map.get(labels, normalized) do
      %{label: label} -> [Map.put(item, :server_label, label)]
      _ -> []
    end
  end

  defp sanitize_tool_name(name, provider) when provider in [:gemini, :anthropic] do
    sanitized = String.replace(name, ~r/[^A-Za-z0-9_.-]/u, "_")

    if String.length(sanitized) <= 63 do
      sanitized
    else
      ellipsize_middle(sanitized, 63)
    end
  end

  defp sanitize_tool_name(name, _provider) when is_binary(name), do: name

  defp ellipsize_middle(value, max) when max > 3 do
    len = String.length(value)

    if len <= max do
      value
    else
      head = String.slice(value, 0, div(max - 3, 2))
      tail = String.slice(value, len - (max - 3 - div(max - 3, 2)), max - 3 - div(max - 3, 2))
      head <> "..." <> tail
    end
  end

  defp merge_prefer_mcp(builtins, mcp) do
    mcp_names = MapSet.new(Enum.map(mcp, & &1.name))

    filtered_builtins =
      builtins
      |> Enum.reject(fn %{name: name} -> MapSet.member?(mcp_names, name) end)

    mcp ++ filtered_builtins
  end

  defp dedup_by_name(items) do
    {ordered, _names} =
      Enum.reduce(items, {[], MapSet.new()}, fn item, {acc, names} ->
        cond do
          item == nil -> {acc, names}
          MapSet.member?(names, item.name) -> {acc, names}
          true -> {[item | acc], MapSet.put(names, item.name)}
        end
      end)

    Enum.reverse(ordered)
  end
end
