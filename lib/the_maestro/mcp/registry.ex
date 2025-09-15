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
  alias TheMaestro.MCP.RegistryCache
  
  @type tool_decl :: %{
          required(String.t()) => any()
        }

  @spec to_gemini_decls(String.t()) :: [tool_decl]
  def to_gemini_decls(session_id) when is_binary(session_id) do
    with %TheMaestro.Conversations.Session{} = s <- Conversations.get_session!(session_id) do
      mcps_hash = :erlang.phash2(s.mcps || %{})

      case RegistryCache.get(session_id, mcps_hash) do
        {:ok, decls} ->
          decls

        _ ->
          # Structured snapshot (if present)
          from_registry =
            s.tools
            |> safe_get(["mcp_registry", "tools"], [])
            |> Enum.flat_map(&map_registry_tool_to_gemini/1)

          # Simple static tools under session.mcps["tools"]
          from_simple =
            s.mcps
            |> safe_get(["tools"], [])
            |> Enum.flat_map(&map_simple_tool_to_gemini/1)

          # Dynamic handshake for each configured server under session.mcps
          from_dynamic =
            s.mcps
            |> Map.drop(["tools"]) # remove simple list key if present
            |> Enum.flat_map(fn {server_key, cfg} ->
              if is_map(cfg) do
                case TheMaestro.MCP.Client.discover(session_id, server_key) do
                  {:ok, %{tools: tools}} ->
                    tools |> Enum.flat_map(&map_hermes_tool_to_gemini/1)
                  _ -> []
                end
              else
                []
              end
            end)

          decls = (from_registry ++ from_simple ++ from_dynamic) |> uniq_by_name()
          _ = RegistryCache.put(session_id, mcps_hash, decls)
          decls
      end
    end
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

    cond do
      is_binary(name) and is_map(params) ->
        [
          %{
            "name" => sanitize_gemini_name(name),
            "description" => desc,
            "parameters" => normalize_json_schema(params)
          }
        ]

      true ->
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
  @spec resolve(String.t(), String.t()) :: {:ok, %{server: String.t(), mcp_tool_name: String.t()}} | :error
  def resolve(session_id, provider_exposed_name) do
    with %TheMaestro.Conversations.Session{} = s <- Conversations.get_session!(session_id) do
      # Invalidate cache is handled by bump_revision/1 on config save
      # Build a map of exposed_name -> {server, original_name}
      discovered =
        s.mcps
        |> Map.drop(["tools"]) # servers only
        |> Enum.flat_map(fn {server_key, cfg} ->
          if is_map(cfg) do
            case TheMaestro.MCP.Client.discover(session_id, server_key) do
              {:ok, %{tools: tools}} ->
                Enum.map(tools, fn %{"name" => n} ->
                  %{server: to_string(server_key), name: n, exposed: sanitize_gemini_name(n)}
                end)

              _ -> []
            end
          else
            []
          end
        end)

      case Enum.find(discovered, fn t -> t.exposed == provider_exposed_name end) do
        %{server: server_key, name: original} -> {:ok, %{server: server_key, mcp_tool_name: original}}
        _ -> :error
      end
    else
      _ -> :error
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
        if Map.has_key?(seen, name), do: {acc, seen}, else: {Map.put(acc, name, d), Map.put(seen, name, true)}
      end)

    out |> Map.values()
  end

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
