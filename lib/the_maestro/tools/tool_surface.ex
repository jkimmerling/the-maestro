defmodule TheMaestro.Tools.ToolSurface do
  @moduledoc """
  UI-agnostic tool surface: built-ins + MCP per provider/session,
  allowlist awareness, and provider-specific declaration builders.
  """

  alias TheMaestro.Conversations
  alias TheMaestro.MCP.Registry, as: MCPRegistry
  alias TheMaestro.Tools.ProviderToolManifest, as: Manifest

  @type provider :: :openai | :gemini | :anthropic

  @doc "Inventory list (builtins ∪ MCP) for a provider/session (names+descriptions)."
  @spec list(String.t() | nil, provider()) :: [map()]
  def list(session_id, provider) when provider in [:openai, :gemini, :anthropic] do
    builtins = Manifest.list_builtin(provider) |> Enum.map(fn %{name: n, description: d} -> %{name: n, description: d, source: :builtin} end)
    mcps = list_mcp_inventory(session_id, provider)

    names = MapSet.new(Enum.map(mcps, & &1.name))
    filtered_builtins = Enum.reject(builtins, fn %{name: n} -> MapSet.member?(names, n) end)
    mcps ++ filtered_builtins
  end

  @doc "Built-in inventory only."
  def list_builtins(provider), do: Manifest.list_builtin(provider)

  @doc "Return allowed tool names for provider from session or :absent."
  @spec allowed(String.t() | nil, provider()) :: {:present, [String.t()]} | :absent
  def allowed(nil, _provider), do: :absent
  def allowed(session_id, provider) when is_binary(session_id) do
    prov_key = Atom.to_string(provider)
    case Conversations.get_session!(session_id) do
      %Conversations.Session{tools: %{"allowed" => %{} = allowed}} ->
        case Map.fetch(allowed, prov_key) do
          {:ok, list} when is_list(list) -> {:present, Enum.map(list, &to_string/1)}
          _ -> :absent
        end
      _ -> :absent
    end
  rescue
    _ -> :absent
  end

  @doc "Provider-specific tool declaration payload (builtins ∪ MCP), allowlist applied."
  @spec resolve_for_provider_decl(provider(), String.t()) :: [map()]
  def resolve_for_provider_decl(provider, session_id) when provider in [:openai, :gemini, :anthropic] do
    allow = allowed(session_id, provider)

    builtins = provider_decl_builtins(provider)
    mcp = provider_decl_mcp(session_id, provider)

    decls = merge_prefer_mcp(builtins, mcp)
    maybe_filter_provider_decls(decls, allow)
  end

  # ===== Internals =====
  defp provider_decl_builtins(:openai), do: Manifest.provider_decl_builtins(:openai)
  defp provider_decl_builtins(:gemini), do: Manifest.provider_decl_builtins(:gemini)
  defp provider_decl_builtins(:anthropic) do
    # Defer to provider (Anthropic Streaming defines tool set). We keep inventory unified.
    []
  end

  defp provider_decl_mcp(session_id, :openai) do
    MCPRegistry.to_openai_decls(session_id)
  end

  defp provider_decl_mcp(session_id, :gemini) do
    MCPRegistry.to_gemini_decls(session_id)
  end

  defp provider_decl_mcp(session_id, :anthropic) do
    MCPRegistry.to_anthropic_decls(session_id)
  end

  defp list_mcp_inventory(nil, _), do: []
  defp list_mcp_inventory(session_id, :openai) do
    MCPRegistry.to_openai_decls(session_id)
    |> Enum.flat_map(fn m -> case m do %{"name" => n} -> [%{name: n, description: m["description"], source: :mcp}] ; _ -> [] end end)
  end
  defp list_mcp_inventory(session_id, :gemini) do
    MCPRegistry.to_gemini_decls(session_id)
    |> Enum.flat_map(fn m -> case m do %{"name" => n} -> [%{name: n, description: m["description"], source: :mcp}] ; _ -> [] end end)
  end
  defp list_mcp_inventory(session_id, :anthropic) do
    MCPRegistry.to_anthropic_decls(session_id)
    |> Enum.flat_map(fn m -> case m do %{"name" => n} -> [%{name: n, description: m["description"], source: :mcp}] ; _ -> [] end end)
  end

  defp merge_prefer_mcp(builtins, mcp) when is_list(builtins) and is_list(mcp) do
    names = MapSet.new(Enum.map(mcp, &(&1["name"])) )
    builtins_filtered = Enum.reject(builtins, fn d -> MapSet.member?(names, d["name"]) end)
    mcp ++ builtins_filtered
  end

  defp maybe_filter_provider_decls(list, :absent), do: list
  defp maybe_filter_provider_decls(list, {:present, allowed}) do
    allowed_set = MapSet.new(allowed)
    Enum.filter(list, fn %{"name" => n} -> MapSet.member?(allowed_set, n) end)
  end
end
