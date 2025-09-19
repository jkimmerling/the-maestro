defmodule TheMaestro.MCP.Registry do
  @moduledoc """
  Minimal session-scoped MCP registry used to materialize provider-specific
  tool declarations. This focuses on Gemini for now to ensure our request
  shapes match the working telemetry flow.

  Source of truth is the Session record. We read from either:
  - `session.tools["mcp_registry"]` structured snapshot (if present), or
  - `session.mcps["tools"]` simple list of tools: [%{"name" => ..., "parameters" => ..., "description" => ...}]

  Names are sanitized per provider constraints when materializing declarations.
  """

  alias TheMaestro.Conversations
  alias TheMaestro.MCP
  alias TheMaestro.MCP.Client, as: MCPClient
  alias TheMaestro.MCP.RegistryCache

  @type tool_decl :: %{
          required(String.t()) => any()
        }

  @spec to_gemini_decls(String.t()) :: [tool_decl]
  def to_gemini_decls(session_id) when is_binary(session_id) do
    case Conversations.get_session!(session_id) do
      %Conversations.Session{} = session ->
        session = Conversations.preload_session_mcp(session)
        connectors = MCP.session_connector_map(session)
        mcps_hash = connectors_signature(session, connectors)

        case RegistryCache.get(session_id, mcps_hash) do
          {:ok, decls} ->
            decls

          _ ->
            decls = collect_gemini_decls(session, session_id, connectors)
            _ = RegistryCache.put(session_id, mcps_hash, decls)
            decls
        end

      _ ->
        []
    end
  rescue
    _ -> []
  end

  @doc """
  Materialize MCP tools for Anthropic Messages API.

  Returns a list of maps like:
    %{"name" => name, "description" => desc, "input_schema" => json_schema}
  """
  @spec to_anthropic_decls(String.t()) :: [tool_decl]
  def to_anthropic_decls(session_id) when is_binary(session_id) do
    case Conversations.get_session!(session_id) do
      %Conversations.Session{} = session ->
        session = Conversations.preload_session_mcp(session)
        connectors = MCP.session_connector_map(session)
        mcps_hash = connectors_signature(session, connectors)

        case RegistryCache.get("anth:" <> session_id, mcps_hash) do
          {:ok, decls} ->
            decls

          _ ->
            decls =
              session
              |> collect_anthropic_decls(session_id, connectors)
              |> uniq_by_name()

            _ = RegistryCache.put("anth:" <> session_id, mcps_hash, decls)
            decls
        end

      _ ->
        []
    end
  rescue
    _ -> []
  end

  @doc """
  Materialize MCP tools for OpenAI Responses API.

  Returns a list of maps like:
    %{ "type" => "function", "name" => name, "description" => desc, "parameters" => json_schema }
  """
  @spec to_openai_decls(String.t()) :: [tool_decl]
  def to_openai_decls(session_id) when is_binary(session_id) do
    case Conversations.get_session!(session_id) do
      %Conversations.Session{} = session ->
        session = Conversations.preload_session_mcp(session)
        connectors = MCP.session_connector_map(session)
        mcps_hash = connectors_signature(session, connectors)

        case RegistryCache.get("oai:" <> session_id, mcps_hash) do
          {:ok, decls} ->
            decls

          _ ->
            decls =
              session
              |> collect_openai_decls(session_id, connectors)
              |> nudge_openai_tool_descriptions()

            _ = RegistryCache.put("oai:" <> session_id, mcps_hash, decls)
            decls
        end

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp collect_gemini_decls(%Conversations.Session{} = s, session_id, connectors) do
    from_registry =
      s.tools
      |> safe_get(["mcp_registry", "tools"], [])
      |> Enum.flat_map(&map_registry_tool_to_gemini/1)

    from_simple =
      connectors
      |> safe_get(["tools"], [])
      |> Enum.flat_map(&map_simple_tool_to_gemini/1)

    from_dynamic = collect_dynamic_decls(connectors, session_id, :gemini)

    (from_registry ++ from_simple ++ from_dynamic) |> uniq_by_name()
  end

  defp collect_openai_decls(%Conversations.Session{} = s, session_id, connectors) do
    from_registry =
      s.tools
      |> safe_get(["mcp_registry", "tools"], [])
      |> Enum.flat_map(&map_registry_tool_to_openai/1)

    from_simple =
      connectors
      |> safe_get(["tools"], [])
      |> Enum.flat_map(&map_simple_tool_to_openai/1)

    from_dynamic = collect_dynamic_decls(connectors, session_id, :openai)

    (from_registry ++ from_simple ++ from_dynamic) |> uniq_by_name()
  end

  defp collect_anthropic_decls(%Conversations.Session{} = s, session_id, connectors) do
    from_registry =
      s.tools
      |> safe_get(["mcp_registry", "tools"], [])
      |> Enum.flat_map(&map_registry_tool_to_anthropic/1)

    from_simple =
      connectors
      |> safe_get(["tools"], [])
      |> Enum.flat_map(&map_simple_tool_to_anthropic/1)

    from_dynamic = collect_dynamic_decls(connectors, session_id, :anthropic)

    from_registry ++ from_simple ++ from_dynamic
  end

  defp collect_dynamic_decls(connectors, session_id, provider) do
    connectors
    |> Map.drop(["tools"])
    |> Enum.flat_map(fn {server_key, cfg} ->
      map_server_dynamic(server_key, cfg, session_id, provider)
    end)
  end

  defp connectors_signature(session, connectors) do
    join_sig =
      session.session_mcp_servers
      |> List.wrap()
      |> Enum.map(fn binding -> {binding.mcp_server_id, binding.alias, binding.updated_at} end)
      |> Enum.sort()

    :erlang.phash2({connectors, join_sig})
  end

  defp map_server_dynamic(server_key, cfg, session_id, provider) do
    if is_map(cfg) do
      tools = list_server_tools(session_id, server_key)

      case provider do
        :gemini -> tools |> Enum.flat_map(&map_hermes_tool_to_gemini/1)
        :openai -> tools |> Enum.flat_map(&map_hermes_tool_to_openai/1)
        :anthropic -> tools |> Enum.flat_map(&map_hermes_tool_to_anthropic/1)
      end
    else
      []
    end
  end

  defp list_server_tools(session_id, server_key) do
    case MCPClient.discover(session_id, server_key) do
      {:ok, %{tools: tools}} when is_list(tools) -> tools
      _ -> []
    end
  end

  defp discovered_exposed_tools(%Conversations.Session{} = s, session_id) do
    s
    |> Conversations.preload_session_mcp()
    |> MCP.session_connector_map()
    |> Map.drop(["tools"])
    |> Enum.flat_map(&exposed_tools_for_server(session_id, &1))
  end

  defp exposed_tools_for_server(session_id, {server_key, cfg}) when is_map(cfg) do
    list_server_tools(session_id, server_key)
    |> Enum.map(fn %{"name" => n} ->
      %{server: to_string(server_key), name: n, exposed: sanitize_gemini_name(n)}
    end)
  end

  defp exposed_tools_for_server(_session_id, _), do: []

  # -- OpenAI mapping helpers --
  defp map_registry_tool_to_openai(%{} = t) do
    name =
      get_in(t, ["provider_exposed_name", "openai"]) ||
        t["canonical_name"] || t["mcp_tool_name"] || t["name"]

    with true <- is_binary(name),
         params when is_map(params) <- Map.get(t, "parameters", %{}) do
      [
        %{
          "type" => "function",
          "name" => sanitize_gemini_name(name),
          "description" => Map.get(t, "description"),
          "parameters" => normalize_json_schema(params),
          "strict" => false
        }
      ]
    else
      _ -> []
    end
  end

  # -- Anthropic mapping helpers --
  defp map_registry_tool_to_anthropic(%{} = t) do
    name =
      get_in(t, ["provider_exposed_name", "anthropic"]) ||
        t["canonical_name"] || t["mcp_tool_name"] || t["name"]

    with true <- is_binary(name),
         params when is_map(params) <- Map.get(t, "parameters", %{}) do
      [
        %{
          "name" => sanitize_anthropic_name(name),
          "description" => Map.get(t, "description"),
          "input_schema" => normalize_json_schema(params)
        }
      ]
    else
      _ -> []
    end
  end

  defp map_simple_tool_to_anthropic(%{} = t) do
    name = t["name"] || t[:name]
    params = t["parameters"] || t[:parameters] || %{}
    desc = t["description"] || t[:description]

    if is_binary(name) and is_map(params) do
      [
        %{
          "name" => sanitize_anthropic_name(name),
          "description" => desc,
          "input_schema" => normalize_json_schema(params)
        }
      ]
    else
      []
    end
  end

  defp map_hermes_tool_to_anthropic(%{"name" => name} = t) do
    params = t["inputSchema"] || %{}

    [
      %{
        "name" => sanitize_anthropic_name(name),
        "description" => t["description"] || t["title"],
        "input_schema" => normalize_json_schema(params)
      }
    ]
  rescue
    _ -> []
  end

  defp map_simple_tool_to_openai(%{} = t) do
    name = t["name"] || t[:name]
    params = t["parameters"] || t[:parameters] || %{}
    desc = t["description"] || t[:description]

    if is_binary(name) and is_map(params) do
      [
        %{
          "type" => "function",
          "name" => sanitize_gemini_name(name),
          "description" => desc,
          "parameters" => normalize_json_schema(params),
          "strict" => false
        }
      ]
    else
      []
    end
  end

  defp map_hermes_tool_to_openai(%{"name" => name} = t) do
    params = t["inputSchema"] || %{}

    [
      %{
        "type" => "function",
        "name" => sanitize_gemini_name(name),
        "description" => t["description"] || t["title"],
        "parameters" => normalize_json_schema(params),
        "strict" => false
      }
    ]
  rescue
    _ -> []
  end

  # Map a structured registry tool (with provider_exposed_name map) into a Gemini declaration
  defp map_registry_tool_to_gemini(%{} = t) do
    name =
      get_in(t, ["provider_exposed_name", "gemini"]) ||
        t["canonical_name"] || t["mcp_tool_name"] || t["name"]

    with true <- is_binary(name),
         params when is_map(params) <- Map.get(t, "parameters", %{}) do
      [
        %{
          "name" => sanitize_gemini_name(name),
          "description" => Map.get(t, "description"),
          "parameters" => normalize_json_schema(params)
        }
      ]
    else
      _ -> []
    end
  end

  # Map a very simple tool spec under session.mcps["tools"]
  defp map_simple_tool_to_gemini(%{} = t) do
    name = t["name"] || t[:name]
    params = t["parameters"] || t[:parameters] || %{}
    desc = t["description"] || t[:description]

    if is_binary(name) and is_map(params) do
      [
        %{
          "name" => sanitize_gemini_name(name),
          "description" => desc,
          "parameters" => normalize_json_schema(params)
        }
      ]
    else
      []
    end
  end

  # Map tool from Hermes tools/list → Gemini declaration
  defp map_hermes_tool_to_gemini(%{"name" => name} = t) do
    params = t["inputSchema"] || %{}

    [
      %{
        "name" => sanitize_gemini_name(name),
        "description" => t["description"] || t["title"],
        "parameters" => normalize_json_schema(params)
      }
    ]
  rescue
    _ -> []
  end

  @doc """
  Resolve a provider-exposed tool name (Gemini) to an MCP server + tool name.
  Returns {:ok, %{server: server_key, mcp_tool_name: name}} | :error
  """
  @spec resolve(String.t(), String.t()) ::
          {:ok, %{server: String.t(), mcp_tool_name: String.t()}} | :error
  def resolve(session_id, provider_exposed_name) do
    case Conversations.get_session!(session_id) do
      %Conversations.Session{} = s -> do_resolve_exposed(s, session_id, provider_exposed_name)
      _ -> :error
    end
  end

  defp do_resolve_exposed(%Conversations.Session{} = s, session_id, provider_exposed_name) do
    s
    |> discovered_exposed_tools(session_id)
    |> Enum.find(fn t -> t.exposed == provider_exposed_name end)
    |> case do
      %{server: server_key, name: original} ->
        {:ok, %{server: server_key, mcp_tool_name: original}}

      _ ->
        :error
    end
  end

  @doc """
  Bump tools revision for a session by invalidating the registry cache.
  Call this after saving session.mcps in LiveView.
  """
  @spec bump_revision(String.t()) :: :ok
  def bump_revision(session_id) when is_binary(session_id) do
    RegistryCache.invalidate(session_id)
    :ok
  end

  defp uniq_by_name(list) do
    {out, _seen} =
      Enum.reduce(list, {%{}, %{}}, fn %{"name" => name} = d, {acc, seen} ->
        if Map.has_key?(seen, name),
          do: {acc, seen},
          else: {Map.put(acc, name, d), Map.put(seen, name, true)}
      end)

    out |> Map.values()
  end

  # Slightly steer OpenAI tool selection without changing the base prompt.
  # We only add a short, directive hint to the Context7 tools when both are present.
  defp nudge_openai_tool_descriptions(decls) when is_list(decls) do
    names = Enum.map(decls, & &1["name"]) |> MapSet.new()

    if MapSet.member?(names, "resolve-library-id") and MapSet.member?(names, "get-library-docs") do
      Enum.map(decls, &update_openai_desc/1)
    else
      decls
    end
  end

  # Update descriptions for Context7 tools when both are present
  defp update_openai_desc(%{"name" => "resolve-library-id"} = d) do
    desc =
      (d["description"] || "") <>
        " After resolving a library, call get-library-docs with the returned context7CompatibleLibraryID and the user's topic before answering."

    Map.put(d, "description", desc)
  end

  defp update_openai_desc(%{"name" => "get-library-docs"} = d) do
    desc =
      (d["description"] || "") <>
        " Fetch authoritative docs for the resolved library id and a specific topic; prefer using it before composing explanations."

    Map.put(d, "description", desc)
  end

  defp update_openai_desc(d), do: d

  # no non-list callers

  # Keep a conservative schema: ensure type/object with properties; coerce unknowns to string
  defp normalize_json_schema(%{"type" => "object"} = m) do
    # Validate properties, coerce invalids to string, and drop unsupported top-level keys
    props =
      m
      |> Map.get("properties", %{})
      |> Enum.into(%{}, fn {k, v} ->
        if is_map(v) do
          {k, normalize_property(v)}
        else
          {k, %{"type" => "string"}}
        end
      end)

    required = (m["required"] || []) |> Enum.filter(&is_binary/1)

    %{
      "type" => "object",
      "properties" => props,
      "required" => required
    }
  end

  defp normalize_json_schema(%{} = m) do
    # Fallback: produce a minimal valid Gemini-compatible schema
    props_map =
      (m["properties"] || %{})
      |> Enum.into(%{}, fn {k, v} ->
        if is_map(v), do: {k, normalize_property(v)}, else: {k, %{"type" => "string"}}
      end)

    req = (m["required"] || []) |> Enum.filter(&is_binary/1)

    %{"type" => "object", "properties" => props_map, "required" => req}
  end

  defp normalize_json_schema(_), do: %{"type" => "object", "properties" => %{}, "required" => []}

  defp normalize_property(%{"type" => t} = p) when is_binary(t) do
    case t do
      "string" -> p
      "number" -> p
      "integer" -> p
      "boolean" -> p
      "array" -> p
      "object" -> p
      _ -> %{"type" => "string"}
    end
  end

  defp normalize_property(%{}), do: %{"type" => "string"}

  # Gemini-compatible function name: [A-Za-z0-9_.-], ≤63 chars
  defp sanitize_gemini_name(name) when is_binary(name) do
    sanitized =
      name
      |> String.replace(~r/[^A-Za-z0-9_.-]/u, "_")

    if String.length(sanitized) <= 63 do
      sanitized
    else
      ellipsize_middle(sanitized, 63)
    end
  end

  # Anthropic tool name sanitizer: keep it simple/safe
  defp sanitize_anthropic_name(name) when is_binary(name) do
    sanitized = name |> String.replace(~r/[^A-Za-z0-9_.-]/u, "_")
    if String.length(sanitized) <= 63, do: sanitized, else: ellipsize_middle(sanitized, 63)
  end

  defp ellipsize_middle(s, max) when is_integer(max) and max > 3 do
    len = String.length(s)

    if len <= max do
      s
    else
      left = div(max - 3, 2)
      right = max - 3 - left
      String.slice(s, 0, left) <> "..." <> String.slice(s, len - right, right)
    end
  end

  defp safe_get(m, path, default) when is_map(m) and is_list(path) do
    get_in(m, Enum.map(path, &Access.key(&1, %{})))
    |> case do
      %{} = v -> v
      l when is_list(l) -> l
      _ -> default
    end
  end
end
