defmodule TheMaestro.Tools.Inventory do
  @moduledoc """
  Centralized inventory of available tools per provider for a given session.

  Exposes a simplified list of tool entries combining built-ins and
  MCP-discovered tools for the session.

  Returned entries have the shape:
    [%{name: binary(), source: :builtin | :mcp, description: binary() | nil}]
  """

  alias TheMaestro.Conversations
  alias TheMaestro.MCP.Registry, as: MCPRegistry
  alias TheMaestro.MCP.UnifiedToolsCache

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
  Build inventory for a provider using the unified cache.
  Returns all available MCP tools from the unified cache for the specified provider.
  """
  @spec list_for_provider_with_servers([String.t()], provider()) :: [item()]
  def list_for_provider_with_servers(_server_ids, provider)
      when provider in [:openai, :anthropic, :gemini] do
    builtins = builtins_for(provider)

    # Get tools from unified cache
    mcp_items =
      case UnifiedToolsCache.get_tools() do
        {:ok, tools_by_provider} ->
          provider_key = Atom.to_string(provider)
          Map.get(tools_by_provider, provider_key, [])

        _ ->
          []
      end

    # Prefer MCP on name collision
    names =
      MapSet.new(
        Enum.map(mcp_items, fn
          %{"name" => name} when is_binary(name) -> name
          %{name: name} when is_binary(name) -> name
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
      )

    filtered_builtins = Enum.reject(builtins, fn %{name: n} -> MapSet.member?(names, n) end)

    # Convert tools from cache format (string keys) to inventory format (atom keys)
    normalized_mcp_items = Enum.map(mcp_items, &normalize_tool_format/1) |> Enum.reject(&is_nil/1)
    normalized_mcp_items ++ filtered_builtins
  end

  # Convert tool from unified cache format (string keys) to inventory format (atom keys)
  defp normalize_tool_format(%{"name" => name, "source" => source, "description" => desc} = tool) do
    %{
      name: name,
      source: if(is_binary(source), do: String.to_existing_atom(source), else: source),
      description: desc,
      server_label: tool["server_label"]
    }
  rescue
    _ -> nil
  end

  defp normalize_tool_format(_), do: nil

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
