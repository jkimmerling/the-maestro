defmodule TheMaestro.MCP.Connection do
  @moduledoc """
  Represents and manages the state of an MCP server connection.

  A Connection tracks the transport, connection state, server capabilities,
  available tools, and server information for an MCP server.
  """

  @type connection_state :: :disconnected | :connecting | :connected | :error

  @type t :: %__MODULE__{
          transport: pid() | nil,
          state: connection_state(),
          server_info: map() | nil,
          capabilities: map(),
          tools: list()
        }

  defstruct [
    :transport,
    :state,
    :server_info,
    capabilities: %{},
    tools: []
  ]

  @doc """
  Create a new connection with the given transport and initial state.

  ## Parameters

  * `transport` - PID of the transport process
  * `state` - Initial connection state

  ## Examples

      iex> transport_pid = spawn(fn -> :ok end)
      iex> conn = TheMaestro.MCP.Connection.new(transport_pid, :connecting)
      iex> conn.state
      :connecting
  """
  @spec new(pid(), connection_state()) :: t()
  def new(transport, state) do
    %__MODULE__{
      transport: transport,
      state: state,
      server_info: nil,
      capabilities: %{},
      tools: []
    }
  end

  @doc """
  Update the connection state.

  ## Parameters

  * `connection` - The connection struct
  * `new_state` - The new state to set

  ## Examples

      iex> transport_pid = spawn(fn -> :ok end)
      iex> conn = TheMaestro.MCP.Connection.new(transport_pid, :connecting)
      iex> updated = TheMaestro.MCP.Connection.update_state(conn, :connected)
      iex> updated.state
      :connected
  """
  @spec update_state(t(), connection_state()) :: t()
  def update_state(%__MODULE__{} = connection, new_state) do
    %{connection | state: new_state}
  end

  @doc """
  Set server information for the connection.

  ## Parameters

  * `connection` - The connection struct
  * `server_info` - Map containing server information

  ## Examples

      iex> transport_pid = spawn(fn -> :ok end)
      iex> conn = TheMaestro.MCP.Connection.new(transport_pid, :connecting)
      iex> info = %{name: "test_server", version: "1.0.0"}
      iex> updated = TheMaestro.MCP.Connection.set_server_info(conn, info)
      iex> updated.server_info.name
      "test_server"
  """
  @spec set_server_info(t(), map()) :: t()
  def set_server_info(%__MODULE__{} = connection, server_info) do
    %{connection | server_info: server_info}
  end

  @doc """
  Set server capabilities for the connection.

  ## Parameters

  * `connection` - The connection struct
  * `capabilities` - Map containing server capabilities

  ## Examples

      iex> transport_pid = spawn(fn -> :ok end)
      iex> conn = TheMaestro.MCP.Connection.new(transport_pid, :connecting)
      iex> caps = %{tools: %{listChanged: true}}
      iex> updated = TheMaestro.MCP.Connection.set_capabilities(conn, caps)
      iex> updated.capabilities.tools.listChanged
      true
  """
  @spec set_capabilities(t(), map()) :: t()
  def set_capabilities(%__MODULE__{} = connection, capabilities) do
    %{connection | capabilities: capabilities}
  end

  @doc """
  Add a tool to the connection's tool list.

  Prevents duplicate tools by checking if a tool with the same name already exists.

  ## Parameters

  * `connection` - The connection struct
  * `tool` - Map containing tool information

  ## Examples

      iex> transport_pid = spawn(fn -> :ok end)
      iex> conn = TheMaestro.MCP.Connection.new(transport_pid, :connected)
      iex> tool = %{name: "test_tool", description: "A test tool"}
      iex> updated = TheMaestro.MCP.Connection.add_tool(conn, tool)
      iex> length(updated.tools)
      1
  """
  @spec add_tool(t(), map()) :: t()
  def add_tool(%__MODULE__{} = connection, tool) do
    tool_name = Map.get(tool, :name) || Map.get(tool, "name")

    # Check if tool already exists
    existing_tool =
      Enum.find(connection.tools, fn existing ->
        existing_name = Map.get(existing, :name) || Map.get(existing, "name")
        existing_name == tool_name
      end)

    if existing_tool do
      connection
    else
      %{connection | tools: [tool | connection.tools]}
    end
  end

  @doc """
  Remove a tool from the connection's tool list by name.

  ## Parameters

  * `connection` - The connection struct
  * `tool_name` - Name of the tool to remove

  ## Examples

      iex> transport_pid = spawn(fn -> :ok end)
      iex> conn = TheMaestro.MCP.Connection.new(transport_pid, :connected)
      iex> tool = %{name: "test_tool", description: "A test tool"}
      iex> conn = TheMaestro.MCP.Connection.add_tool(conn, tool)
      iex> updated = TheMaestro.MCP.Connection.remove_tool(conn, "test_tool")
      iex> length(updated.tools)
      0
  """
  @spec remove_tool(t(), String.t()) :: t()
  def remove_tool(%__MODULE__{} = connection, tool_name) do
    tools =
      Enum.reject(connection.tools, fn tool ->
        existing_name = Map.get(tool, :name) || Map.get(tool, "name")
        existing_name == tool_name
      end)

    %{connection | tools: tools}
  end

  @doc """
  Get a tool from the connection by name.

  ## Parameters

  * `connection` - The connection struct
  * `tool_name` - Name of the tool to find

  ## Examples

      iex> transport_pid = spawn(fn -> :ok end)
      iex> conn = TheMaestro.MCP.Connection.new(transport_pid, :connected)
      iex> tool = %{name: "test_tool", description: "A test tool"}
      iex> conn = TheMaestro.MCP.Connection.add_tool(conn, tool)
      iex> {:ok, found} = TheMaestro.MCP.Connection.get_tool(conn, "test_tool")
      iex> found.name
      "test_tool"
  """
  @spec get_tool(t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_tool(%__MODULE__{} = connection, tool_name) do
    case Enum.find(connection.tools, fn tool ->
           existing_name = Map.get(tool, :name) || Map.get(tool, "name")
           existing_name == tool_name
         end) do
      nil -> {:error, :not_found}
      tool -> {:ok, tool}
    end
  end

  @doc """
  Check if the connection is in a connected state.

  ## Parameters

  * `connection` - The connection struct

  ## Examples

      iex> transport_pid = spawn(fn -> :ok end)
      iex> conn = TheMaestro.MCP.Connection.new(transport_pid, :connected)
      iex> TheMaestro.MCP.Connection.connected?(conn)
      true
  """
  @spec connected?(t()) :: boolean()
  def connected?(%__MODULE__{state: :connected}), do: true
  def connected?(%__MODULE__{}), do: false
end
