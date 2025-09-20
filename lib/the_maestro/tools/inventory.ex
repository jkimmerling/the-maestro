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
  alias TheMaestro.MCP.Registry, as: MCPRegistry
  alias TheMaestro.MCP.ToolsCache

  @type provider :: :openai | :anthropic | :gemini
  @type item :: %{name: String.t(), source: :builtin | :mcp, description: String.t() | nil}

  @spec list_for_provider(String.t() | nil, provider()) :: [item()]
  def list_for_provider(session_id, provider) when provider in [:openai, :anthropic, :gemini] do
    builtins = builtins_for(provider)
    mcps = mcp_for(session_id, provider)

    # Prefer MCP on name collision
    names = MapSet.new(Enum.map(mcps, & &1.name))
    filtered_builtins = Enum.reject(builtins, fn %{name: n} -> MapSet.member?(names, n) end)
    mcps ++ filtered_builtins
  end

  @doc """
  Build inventory for a provider using a set of MCP server ids (strings),
  without requiring a persisted session. Uses the MCP ToolsCache; does not
  perform live discovery on cache hit. On cache miss/stale, returns only
  built-ins.
  """
  @spec list_for_provider_with_servers([String.t()], provider()) :: [item()]
  def list_for_provider_with_servers(server_ids, provider)
      when provider in [:openai, :anthropic, :gemini] do
    builtins = builtins_for(provider)

    mcp_items =
      server_ids
      |> Enum.flat_map(fn sid ->
        {label, tools} = server_tools_or_cache(sid)

        tools
        |> Enum.flat_map(&map_hermes_item(&1, provider, label))
      end)

    # Prefer MCP on name collision
    names = MapSet.new(Enum.map(mcp_items, & &1.name))
    filtered_builtins = Enum.reject(builtins, fn %{name: n} -> MapSet.member?(names, n) end)
    mcp_items ++ filtered_builtins
  end

  defp server_tools_or_cache(server_id) do
    server = MCP.get_server!(server_id)
    label = server.display_name || server.name || "MCP"

    ttl_ms =
      case server.metadata do
        %{} = md ->
          (md["tool_cache_ttl_minutes"] || md[:tool_cache_ttl_minutes] || 60)
          |> to_int()
          |> Kernel.*(60_000)

        _ ->
          60 * 60_000
      end

    # Use get_with_freshness to get data even if stale
    tools =
      case ToolsCache.get_with_freshness(server_id, ttl_ms) do
        {:ok, t, :fresh} ->
          t
        {:ok, t, :stale} ->
          # Return stale data and trigger background refresh
          Task.start(fn -> warm_cache_for_server(server_id) end)
          t
        :miss ->
          # No cache at all, trigger background discovery
          Task.start(fn -> warm_cache_for_server(server_id) end)
          []
      end

    {label, tools}
  end

  defp warm_cache_for_server(server_id) do
    server = MCP.get_server!(server_id)

    case MCP.Client.discover_server(server) do
      {:ok, %{tools: tools}} ->
        ttl_ms =
          case server.metadata do
            %{} = md ->
              (md["tool_cache_ttl_minutes"] || md[:tool_cache_ttl_minutes] || 60)
              |> to_int()
              |> Kernel.*(60_000)
            _ ->
              60 * 60_000
          end

        ToolsCache.put(server_id, tools, ttl_ms)
      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      _ -> 60
    end
  end

  defp to_int(_), do: 60

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

  # ----- Internals -----
  defp mcp_for(nil, _provider), do: []

  defp mcp_for(session_id, :openai) when is_binary(session_id) do
    MCPRegistry.to_openai_decls(session_id)
    |> Enum.flat_map(fn m ->
      case m do
        %{"name" => n} -> [%{name: to_string(n), source: :mcp, description: m["description"]}]
        _ -> []
      end
    end)
  end

  defp mcp_for(session_id, :anthropic) when is_binary(session_id) do
    MCPRegistry.to_anthropic_decls(session_id)
    |> Enum.flat_map(fn m ->
      case m do
        %{"name" => n} -> [%{name: to_string(n), source: :mcp, description: m["description"]}]
        _ -> []
      end
    end)
  end

  defp mcp_for(session_id, :gemini) when is_binary(session_id) do
    MCPRegistry.to_gemini_decls(session_id)
    |> Enum.flat_map(fn m ->
      case m do
        %{"name" => n} -> [%{name: to_string(n), source: :mcp, description: m["description"]}]
        _ -> []
      end
    end)
  end

  # ---- Map Hermes tool into inventory item with provider-specific name ----
  defp map_hermes_item(%{"name" => name} = t, :openai, label) do
    [
      %{
        name: sanitize_gemini_name(name),
        source: :mcp,
        description: t["description"] || t["title"],
        server_label: label
      }
    ]
  rescue
    _ -> []
  end

  defp map_hermes_item(%{"name" => name} = t, :anthropic, label) do
    [
      %{
        name: sanitize_anthropic_name(name),
        source: :mcp,
        description: t["description"] || t["title"],
        server_label: label
      }
    ]
  rescue
    _ -> []
  end

  defp map_hermes_item(%{"name" => name} = t, :gemini, label) do
    [
      %{
        name: sanitize_gemini_name(name),
        source: :mcp,
        description: t["description"] || t["title"],
        server_label: label
      }
    ]
  rescue
    _ -> []
  end

  defp map_hermes_item(_other, _provider, _label), do: []

  # Reuse same sanitizers as Registry for consistency (re-implemented here)
  defp sanitize_gemini_name(name) when is_binary(name) do
    sanitized = String.replace(name, ~r/[^A-Za-z0-9_.-]/u, "_")
    if String.length(sanitized) <= 63, do: sanitized, else: ellipsize_middle(sanitized, 63)
  end

  defp sanitize_anthropic_name(name) when is_binary(name) do
    sanitized = String.replace(name, ~r/[^A-Za-z0-9_.-]/u, "_")
    if String.length(sanitized) <= 63, do: sanitized, else: ellipsize_middle(sanitized, 63)
  end

  defp ellipsize_middle(s, max) when is_integer(max) and max > 3 do
    len = String.length(s)

    if len <= max,
      do: s,
      else:
        String.slice(s, 0, div(max - 3, 2)) <>
          "..." <> String.slice(s, len - (max - 3 - div(max - 3, 2)), max - 3 - div(max - 3, 2))
  end

  defp builtins_for(:openai) do
    [
      %{
        name: "shell",
        source: :builtin,
        description: "Runs a shell command and returns its output"
      },
      %{
        name: "apply_patch",
        source: :builtin,
        description: "Use the `apply_patch` tool to edit files."
      }
    ]
  end

  defp builtins_for(:gemini) do
    [
      %{
        name: "run_shell_command",
        source: :builtin,
        description: "Execute a shell command. Use for tasks like listing files."
      },
      %{
        name: "list_directory",
        source: :builtin,
        description: "List files and folders for a given path."
      }
    ]
  end

  defp builtins_for(:anthropic) do
    # Keep names in sync with TheMaestro.Providers.Anthropic.Streaming
    for {n, d} <- [
          {"Task", "Launch a sub-agent for multi-step tasks."},
          {"Bash", "Execute a bash command in a persistent shell."},
          {"Glob", "Fast file pattern matching tool."},
          {"Grep", "Search code using ripgrep."},
          {"ExitPlanMode", "Exit plan mode when ready to code."},
          {"Read", "Read a file."},
          {"Edit", "Edit a file (find/replace)."},
          {"MultiEdit", "Multiple edits to one file."},
          {"Write", "Write a file."},
          {"NotebookEdit", "Replace contents of a notebook cell."},
          {"WebFetch", "Fetch a URL and analyze with a prompt."},
          {"TodoWrite", "Create and manage a structured task list."},
          {"WebSearch", "Search the web for up-to-date information."},
          {"BashOutput", "Retrieve output from a running background bash shell."},
          {"KillBash", "Kill a running background bash shell."}
        ] do
      %{name: n, source: :builtin, description: d}
    end
  end
end
