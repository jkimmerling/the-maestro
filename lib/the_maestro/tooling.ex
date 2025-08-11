defmodule TheMaestro.Tooling do
  @moduledoc """
  Core tooling system for the AI agent.

  This module provides the central registry and execution engine for tools
  that can be used by the AI agent to extend its capabilities.
  """

  use GenServer

  @typedoc """
  Tool registry entry containing tool metadata and execution function.
  """
  @type tool_entry :: %{
          name: String.t(),
          module: module(),
          definition: map(),
          executor: function()
        }

  @typedoc """
  Arguments passed to tool execution.
  """
  @type tool_arguments :: %{String.t() => term()}

  @typedoc """
  Result from tool execution.
  """
  @type tool_result :: {:ok, map()} | {:error, term()}

  ## Client API

  @doc """
  Starts the tool registry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Starts the registry if not already started.
  Used for testing and ensuring registry availability.
  """
  def __registry__ do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  @doc """
  Registers a tool in the global tool registry.

  ## Parameters
    - `name`: Tool name as a string
    - `module`: Module that defines the tool
    - `definition`: Tool definition map
    - `executor`: Function that executes the tool
  """
  def register_tool(name, module, definition, executor) when is_function(executor, 1) do
    __registry__()

    tool_entry = %{
      name: name,
      module: module,
      definition: definition,
      executor: executor
    }

    GenServer.call(__MODULE__, {:register_tool, name, tool_entry})
  end

  @doc """
  Gets all registered tool definitions for LLM function calling.

  Returns a list of tool definitions that can be sent to LLM providers
  to enable function calling capabilities.
  """
  @spec get_tool_definitions() :: [map()]
  def get_tool_definitions do
    __registry__()
    GenServer.call(__MODULE__, :get_tool_definitions)
  end

  @doc """
  Executes a tool with the given arguments.

  Validates the arguments against the tool's schema and executes it safely.

  ## Parameters
    - `tool_name`: Name of the tool to execute
    - `arguments`: Map of arguments to pass to the tool

  ## Returns
    - `{:ok, result}`: Tool executed successfully
    - `{:error, reason}`: Tool execution failed
  """
  @spec execute_tool(String.t(), tool_arguments()) :: tool_result()
  def execute_tool(tool_name, arguments) when is_map(arguments) do
    __registry__()

    case GenServer.call(__MODULE__, {:get_tool, tool_name}) do
      {:ok, tool_entry} ->
        with :ok <- validate_tool_arguments(tool_entry, arguments),
             {:ok, result} <- safe_execute_tool(tool_entry, arguments) do
          {:ok, result}
        else
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        {:error, "Tool '#{tool_name}' not found"}
    end
  end

  @doc """
  Lists all registered tools with their metadata.
  """
  @spec list_tools() :: %{String.t() => tool_entry()}
  def list_tools do
    __registry__()
    GenServer.call(__MODULE__, :list_tools)
  end

  @doc """
  Checks if a tool is registered.
  """
  @spec tool_exists?(String.t()) :: boolean()
  def tool_exists?(tool_name) do
    __registry__()

    case GenServer.call(__MODULE__, {:get_tool, tool_name}) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end

  ## Server Callbacks

  @impl true
  def init(_args) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register_tool, name, tool_entry}, _from, state) do
    new_state = Map.put(state, name, tool_entry)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_tool_definitions, _from, state) do
    definitions =
      state
      |> Map.values()
      |> Enum.map(& &1.definition)

    {:reply, definitions, state}
  end

  @impl true
  def handle_call({:get_tool, tool_name}, _from, state) do
    case Map.get(state, tool_name) do
      nil -> {:reply, {:error, :not_found}, state}
      tool_entry -> {:reply, {:ok, tool_entry}, state}
    end
  end

  @impl true
  def handle_call(:list_tools, _from, state) do
    tools_list =
      state
      |> Enum.map(fn {name, tool_entry} -> {name, tool_entry.module} end)
      |> Map.new()

    {:reply, tools_list, state}
  end

  ## Private Functions

  defp validate_tool_arguments(tool_entry, arguments) do
    # Use the tool's validate_arguments if available, otherwise basic validation
    if function_exported?(tool_entry.module, :validate_arguments, 1) do
      tool_entry.module.validate_arguments(arguments)
    else
      # Basic validation against the JSON schema
      validate_basic_arguments(tool_entry.definition, arguments)
    end
  end

  defp validate_basic_arguments(definition, arguments) do
    case definition do
      %{"parameters" => %{"required" => required_params}} when is_list(required_params) ->
        missing_required =
          Enum.filter(required_params, fn param ->
            not Map.has_key?(arguments, param)
          end)

        if length(missing_required) > 0 do
          {:error, "Missing required parameters: #{inspect(missing_required)}"}
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp safe_execute_tool(tool_entry, arguments) do
    tool_entry.executor.(arguments)
  rescue
    error ->
      {:error, "Tool execution failed: #{inspect(error)}"}
  catch
    :exit, reason ->
      {:error, "Tool execution exited: #{inspect(reason)}"}

    :throw, value ->
      {:error, "Tool execution threw: #{inspect(value)}"}
  end
end
