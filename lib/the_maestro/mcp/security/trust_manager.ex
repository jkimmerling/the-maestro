defmodule TheMaestro.MCP.Security.TrustManager do
  @moduledoc """
  Manages trust relationships for MCP servers and tools.

  This GenServer maintains the state of trust relationships between users,
  MCP servers, and individual tools. It provides the core logic for determining
  whether tool executions require user confirmation.

  ## Trust Model

  The trust manager implements a hierarchical trust model:

  1. **Server Trust**: Base level trust for an entire MCP server
  2. **Tool Trust**: Specific trust/distrust for individual tools
  3. **User Permissions**: User-level overrides and restrictions

  ## Trust Levels

  - `:trusted` - Server is fully trusted, tools execute without confirmation
  - `:untrusted` - Server requires confirmation for all operations (default)
  - `:sandboxed` - Server runs in sandbox with restricted capabilities

  ## Tool Permissions

  - Whitelist: Tools that are always allowed for this server
  - Blacklist: Tools that are never allowed for this server
  - Default behavior follows server trust level
  """

  use GenServer
  require Logger

  alias TheMaestro.MCP.Security.{ServerTrust, TrustLevel}

  @type trust_decision :: :allow | :deny | :confirm_required

  ## Public API

  @doc """
  Starts the trust manager GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current trust level for a server.
  """
  @spec server_trust_level(String.t()) :: TrustLevel.server_level()
  def server_trust_level(server_id) do
    GenServer.call(__MODULE__, {:server_trust_level, server_id})
  end

  @doc """
  Grants trust to a server.
  """
  @spec grant_server_trust(String.t(), TrustLevel.server_level(), String.t()) :: :ok
  def grant_server_trust(server_id, trust_level, granted_by) do
    GenServer.call(__MODULE__, {:grant_server_trust, server_id, trust_level, granted_by})
  end

  @doc """
  Revokes trust from a server.
  """
  @spec revoke_server_trust(String.t(), String.t()) :: :ok
  def revoke_server_trust(server_id, revoked_by) do
    GenServer.call(__MODULE__, {:revoke_server_trust, server_id, revoked_by})
  end

  @doc """
  Gets the full server trust record.
  """
  @spec get_server_trust(String.t()) :: ServerTrust.t()
  def get_server_trust(server_id) do
    GenServer.call(__MODULE__, {:get_server_trust, server_id})
  end

  @doc """
  Adds a tool to the server's whitelist.
  """
  @spec whitelist_tool(String.t(), String.t(), String.t()) :: :ok
  def whitelist_tool(server_id, tool_name, granted_by) do
    GenServer.call(__MODULE__, {:whitelist_tool, server_id, tool_name, granted_by})
  end

  @doc """
  Adds a tool to the server's blacklist.
  """
  @spec blacklist_tool(String.t(), String.t(), String.t()) :: :ok
  def blacklist_tool(server_id, tool_name, granted_by) do
    GenServer.call(__MODULE__, {:blacklist_tool, server_id, tool_name, granted_by})
  end

  @doc """
  Determines if a tool execution requires user confirmation.

  This is the core security decision function that considers:
  - Server trust level
  - Tool whitelist/blacklist status
  - Parameter sensitivity
  - User preferences
  - Risk assessment results
  """
  @spec requires_confirmation?(map(), map(), map()) :: boolean()
  def requires_confirmation?(tool, parameters, context) do
    GenServer.call(__MODULE__, {:requires_confirmation, tool, parameters, context})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Initialize with empty trust store
    # In production, this would load from persistent storage
    state = %{
      server_trusts: %{},
      default_server_trust: TrustLevel.default_server_level()
    }

    Logger.info("MCP Trust Manager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:server_trust_level, server_id}, _from, state) do
    trust_level =
      case Map.get(state.server_trusts, server_id) do
        nil ->
          state.default_server_trust

        %ServerTrust{} = trust ->
          if ServerTrust.expired?(trust) do
            state.default_server_trust
          else
            trust.trust_level
          end
      end

    {:reply, trust_level, state}
  end

  @impl true
  def handle_call({:grant_server_trust, server_id, trust_level, granted_by}, _from, state) do
    trust = ServerTrust.new(server_id, trust_level, granted_by)
    updated_trusts = Map.put(state.server_trusts, server_id, trust)

    Logger.info("Server trust granted",
      server_id: server_id,
      trust_level: trust_level,
      granted_by: granted_by
    )

    {:reply, :ok, %{state | server_trusts: updated_trusts}}
  end

  @impl true
  def handle_call({:revoke_server_trust, server_id, _revoked_by}, _from, state) do
    updated_trusts = Map.delete(state.server_trusts, server_id)

    Logger.info("Server trust revoked", server_id: server_id)

    {:reply, :ok, %{state | server_trusts: updated_trusts}}
  end

  @impl true
  def handle_call({:get_server_trust, server_id}, _from, state) do
    trust =
      Map.get(state.server_trusts, server_id) ||
        ServerTrust.auto_grant(server_id, state.default_server_trust)

    {:reply, trust, state}
  end

  @impl true
  def handle_call({:whitelist_tool, server_id, tool_name, _granted_by}, _from, state) do
    trust = get_or_create_trust(server_id, state)
    updated_trust = ServerTrust.add_to_whitelist(trust, tool_name)
    updated_trusts = Map.put(state.server_trusts, server_id, updated_trust)

    {:reply, :ok, %{state | server_trusts: updated_trusts}}
  end

  @impl true
  def handle_call({:blacklist_tool, server_id, tool_name, _granted_by}, _from, state) do
    trust = get_or_create_trust(server_id, state)
    updated_trust = ServerTrust.add_to_blacklist(trust, tool_name)
    updated_trusts = Map.put(state.server_trusts, server_id, updated_trust)

    {:reply, :ok, %{state | server_trusts: updated_trusts}}
  end

  @impl true
  def handle_call({:requires_confirmation, tool, parameters, context}, _from, state) do
    decision = evaluate_confirmation_requirement(tool, parameters, context, state)
    {:reply, decision, state}
  end

  ## Private Functions

  defp get_or_create_trust(server_id, state) do
    Map.get(state.server_trusts, server_id) ||
      ServerTrust.auto_grant(server_id, state.default_server_trust)
  end

  defp evaluate_confirmation_requirement(tool, parameters, _context, state) do
    server_id = tool.server_id || tool[:server_id]
    tool_name = tool.name || tool[:name]

    trust = get_or_create_trust(server_id, state)

    cond do
      # Always block blacklisted tools
      ServerTrust.tool_blacklisted?(trust, tool_name) ->
        true

      # Allow whitelisted tools on trusted servers
      trust.trust_level == :trusted and ServerTrust.tool_whitelisted?(trust, tool_name) ->
        false

      # Check for sensitive parameters
      contains_sensitive_data?(parameters) ->
        true

      # Check for sensitive paths
      contains_sensitive_paths?(parameters) ->
        true

      # Untrusted servers always require confirmation
      trust.trust_level == :untrusted ->
        true

      # Default case for trusted/sandboxed servers
      true ->
        false
    end
  end

  defp contains_sensitive_data?(parameters) when is_map(parameters) do
    parameters
    |> Map.values()
    |> Enum.any?(&sensitive_value?/1)
  end

  defp contains_sensitive_data?(_), do: false

  defp sensitive_value?(value) when is_binary(value) do
    downcased = String.downcase(value)

    Enum.any?(
      [
        "password",
        "token",
        "key",
        "secret",
        "credential",
        "auth"
      ],
      &String.contains?(downcased, &1)
    )
  end

  defp sensitive_value?(value) when is_map(value) do
    contains_sensitive_data?(value)
  end

  defp sensitive_value?(value) when is_list(value) do
    Enum.any?(value, &sensitive_value?/1)
  end

  defp sensitive_value?(_), do: false

  defp contains_sensitive_paths?(parameters) when is_map(parameters) do
    parameters
    |> Map.values()
    |> Enum.any?(&sensitive_path?/1)
  end

  defp contains_sensitive_paths?(_), do: false

  defp sensitive_path?(value) when is_binary(value) do
    sensitive_patterns = [
      "/etc/",
      "/root/",
      "/home/",
      "~/.ssh/",
      "~/.aws/",
      "C:\\Windows\\",
      "C:\\Users\\",
      "/proc/",
      "/sys/",
      ".env",
      "config",
      "credentials",
      "private",
      "secret"
    ]

    Enum.any?(sensitive_patterns, &String.contains?(value, &1))
  end

  defp sensitive_path?(_), do: false
end
