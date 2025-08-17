defmodule TheMaestro.MCP.ToolAdapter do
  @moduledoc """
  Adapter to integrate MCP tools with the existing agent tooling system.

  This module bridges MCP tools with the existing TheMaestro.Tooling.Tool behaviour,
  allowing MCP tools to be used seamlessly alongside built-in tools within the
  agent system.

  ## Features

  - Automatic conversion of MCP tool definitions to agent tool format
  - Parameter marshalling between agent and MCP formats
  - Result processing and content handling
  - Error handling and graceful fallback
  - Tool discovery and registration management

  ## Usage

      # Register all tools from MCP servers
      ToolAdapter.register_mcp_tools()

      # Execute an MCP tool through the adapter
      {:ok, result} = ToolAdapter.execute_mcp_tool("read_file", %{"path" => "/test.txt"})
  """

  require Logger

  alias TheMaestro.MCP.Tools.{Registry, Executor, ContentHandler}
  alias TheMaestro.MCP.ConnectionManager

  @behaviour TheMaestro.Tooling.Tool

  @doc """
  Register all MCP tools with the agent tooling system.

  Discovers tools from all connected MCP servers and creates tool adapters
  for each one, making them available to the agent.

  ## Returns

  - `:ok` on successful registration
  - `{:error, reason}` on failure
  """
  @spec register_mcp_tools() :: :ok | {:error, term()}
  def register_mcp_tools do
    try do
      # Get all tools from the registry
      all_tools = Registry.get_all_tools(Registry)
      
      Logger.info("Registering #{length(all_tools)} MCP tools with agent system")
      
      # Register each tool as an adapter
      Enum.each(all_tools, &register_tool_adapter/1)
      
      :ok
    rescue
      error ->
        Logger.error("Failed to register MCP tools: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Execute an MCP tool through the adapter system.

  Provides a unified interface for executing MCP tools that handles
  all the complexity of MCP communication, parameter marshalling,
  and result processing.

  ## Parameters

  - `tool_name` - Name of the MCP tool to execute
  - `parameters` - Parameters to pass to the tool
  - `options` - Execution options (optional)

  ## Options

  - `:server_id` - Specific server to use (optional, auto-detected)
  - `:timeout` - Execution timeout in milliseconds
  - `:agent_type` - Agent type for content optimization

  ## Returns

  - `{:ok, result}` on successful execution
  - `{:error, reason}` on failure
  """
  @spec execute_mcp_tool(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def execute_mcp_tool(tool_name, parameters, options \\ %{}) do
    with {:ok, tool_route} <- Registry.find_tool(Registry, tool_name),
         {:ok, execution_result} <- execute_tool_via_mcp(tool_route, parameters, options),
         {:ok, agent_result} <- format_result_for_agent(execution_result, options) do
      {:ok, agent_result}
    else
      {:error, :not_found} ->
        {:error, "MCP tool '#{tool_name}' not found"}
      
      {:error, reason} ->
        Logger.warning("MCP tool execution failed", 
          tool: tool_name, 
          reason: inspect(reason)
        )
        {:error, reason}
    end
  end

  @doc """
  Create a tool adapter for a specific MCP tool.

  Generates a module that implements the Tool behaviour for the given
  MCP tool, allowing it to be used seamlessly with the agent system.

  ## Parameters

  - `tool_metadata` - Tool metadata from the MCP registry

  ## Returns

  Tool adapter module
  """
  @spec create_tool_adapter(map()) :: module()
  def create_tool_adapter(tool_metadata) do
    tool_name = tool_metadata.tool_name
    server_id = tool_metadata.server_id
    
    # Create a dynamic module for this specific tool
    module_name = Module.concat([TheMaestro.MCP.ToolAdapters, camelize(tool_name)])
    
    contents = quote do
      use TheMaestro.Tooling.Tool
      
      @tool_name unquote(tool_name)
      @server_id unquote(server_id)
      @tool_metadata unquote(Macro.escape(tool_metadata))
      
      @impl true
      def definition do
        # Convert MCP tool definition to agent tool format
        TheMaestro.MCP.ToolAdapter.convert_mcp_definition(@tool_metadata)
      end
      
      @impl true
      def execute(arguments) do
        TheMaestro.MCP.ToolAdapter.execute_mcp_tool(@tool_name, arguments)
      end
    end
    
    Module.create(module_name, contents, Macro.Env.location(__ENV__))
    module_name
  end

  @doc """
  Convert MCP tool definition to agent tool format.

  Transforms MCP tool schema into the format expected by the existing
  agent tooling system.

  ## Parameters

  - `tool_metadata` - MCP tool metadata

  ## Returns

  Tool definition map compatible with agent system
  """
  @spec convert_mcp_definition(map()) :: map()
  def convert_mcp_definition(tool_metadata) do
    tool = tool_metadata.tool
    
    %{
      "name" => tool.name,
      "description" => tool.description,
      "parameters" => convert_mcp_parameters(tool.parameters)
    }
  end

  @doc """
  Get all available MCP tools in agent-compatible format.

  Returns a list of all MCP tools converted to the format expected
  by the agent system for tool discovery and selection.

  ## Returns

  List of tool definitions
  """
  @spec get_available_mcp_tools() :: [map()]
  def get_available_mcp_tools do
    Registry.get_all_tools(Registry)
    |> Enum.map(&convert_mcp_definition/1)
  end

  @doc """
  Check if a tool is an MCP tool.

  Determines whether a given tool name corresponds to an MCP tool
  or a built-in tool.

  ## Parameters

  - `tool_name` - Name of the tool to check

  ## Returns

  `true` if it's an MCP tool, `false` otherwise
  """
  @spec is_mcp_tool?(String.t()) :: boolean()
  def is_mcp_tool?(tool_name) do
    case Registry.find_tool(Registry, tool_name) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end

  ## TheMaestro.Tooling.Tool Implementation
  
  @impl true
  def definition do
    %{
      "name" => "mcp_tool_adapter",
      "description" => "Adapter for executing MCP tools through the agent system",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "tool_name" => %{
            "type" => "string",
            "description" => "Name of the MCP tool to execute"
          },
          "parameters" => %{
            "type" => "object",
            "description" => "Parameters to pass to the MCP tool"
          }
        },
        "required" => ["tool_name", "parameters"]
      }
    }
  end

  @impl true
  def execute(%{"tool_name" => tool_name, "parameters" => parameters}) do
    case execute_mcp_tool(tool_name, parameters) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(args) do
    {:error, "Invalid arguments for MCP tool adapter: #{inspect(args)}"}
  end

  ## Private Helper Functions

  defp execute_tool_via_mcp(tool_route, parameters, options) do
    context = %{
      server_id: tool_route.server_id,
      connection_manager: ConnectionManager,
      timeout: Map.get(options, :timeout, 30_000)
    }
    
    Executor.execute(tool_route.tool.name, parameters, context)
  end

  defp format_result_for_agent(execution_result, options) do
    agent_type = Map.get(options, :agent_type, :multimodal)
    
    # Process content for agent consumption
    optimized_content = ContentHandler.optimize_content_for_agent(
      execution_result.content,
      %{agent_type: agent_type}
    )
    
    # Format result for agent system
    agent_result = %{
      "success" => true,
      "content" => optimized_content,
      "text_content" => execution_result.text_content,
      "metadata" => %{
        "server_id" => execution_result.server_id,
        "tool_name" => execution_result.tool_name,
        "execution_time_ms" => execution_result.execution_time_ms,
        "has_images" => execution_result.has_images,
        "has_resources" => execution_result.has_resources,
        "has_binary" => execution_result.has_binary
      }
    }
    
    {:ok, agent_result}
  end

  defp register_tool_adapter(tool_metadata) do
    try do
      _adapter_module = create_tool_adapter(tool_metadata)
      Logger.debug("Created adapter for MCP tool: #{tool_metadata.tool_name}")
    rescue
      error ->
        Logger.warning("Failed to create adapter for tool #{tool_metadata.tool_name}: #{inspect(error)}")
    end
  end

  defp convert_mcp_parameters(mcp_parameters) when is_list(mcp_parameters) do
    properties = 
      mcp_parameters
      |> Enum.map(&convert_parameter_definition/1)
      |> Enum.into(%{})
    
    required = 
      mcp_parameters
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.name)
    
    %{
      "type" => "object",
      "properties" => properties,
      "required" => required
    }
  end

  defp convert_mcp_parameters(_), do: %{
    "type" => "object",
    "properties" => %{},
    "required" => []
  }

  defp convert_parameter_definition(param) do
    type_string = atom_to_string_type(param.type)
    
    definition = %{
      "type" => type_string,
      "description" => param.description
    }
    
    {param.name, definition}
  end

  defp atom_to_string_type(:string), do: "string"
  defp atom_to_string_type(:number), do: "number"
  defp atom_to_string_type(:integer), do: "integer"
  defp atom_to_string_type(:boolean), do: "boolean"
  defp atom_to_string_type(:array), do: "array"
  defp atom_to_string_type(:object), do: "object"
  defp atom_to_string_type(_), do: "string"

  defp camelize(string) do
    string
    |> String.split(~r/[_\-]/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end
end