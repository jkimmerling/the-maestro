defmodule TheMaestro.Tooling do
  @moduledoc """
  Core tooling system for the AI agent with metaprogramming DSL.

  This module provides the central registry and execution engine for tools,
  along with a Domain-Specific Language (DSL) for easily defining new tools
  using the `deftool` macro.

  The tooling system allows the agent to extend its capabilities by executing
  various tools like file operations, shell commands, API calls, etc.

  ## Usage

      defmodule MyApp.Tools.FileOperations do
        use TheMaestro.Tooling

        deftool :read_file do
          description "Reads the contents of a file"
          
          parameter :path, :string, "File path to read", required: true
          
          execute fn %{"path" => path} ->
            case File.read(path) do
              {:ok, content} -> {:ok, %{"content" => content}}
              {:error, reason} -> {:error, "Failed to read file: #{reason}"}
            end
          end
        end
      end

  ## Architecture

  The tooling system consists of:
  - **Tool Registry**: Central registry of all available tools
  - **DSL Macros**: `deftool` macro for declarative tool definition
  - **Execution Engine**: Safe execution with validation and error handling
  - **Security Layer**: Path validation and sandboxing for dangerous operations
  """

  @typedoc """
  Tool registry entry containing tool metadata and execution function.
  """
  @type tool_entry :: %{
          name: String.t(),
          module: module(),
          definition: TheMaestro.Tooling.Tool.definition(),
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

  # Registry for storing tool definitions
  @doc false
  def __registry__ do
    Agent.start_link(fn -> %{} end, name: __MODULE__.Registry)
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
    ensure_registry_started()
    
    tool_entry = %{
      name: name,
      module: module,
      definition: definition,
      executor: executor
    }
    
    Agent.update(__MODULE__.Registry, fn registry ->
      Map.put(registry, name, tool_entry)
    end)
    
    :ok
  end

  @doc """
  Gets all registered tool definitions for LLM function calling.

  Returns a list of tool definitions that can be sent to LLM providers
  to enable function calling capabilities.

  ## Returns
    List of tool definition maps following OpenAI Function Calling format.
  """
  @spec get_tool_definitions() :: [TheMaestro.Tooling.Tool.definition()]
  def get_tool_definitions do
    ensure_registry_started()
    
    Agent.get(__MODULE__.Registry, fn registry ->
      registry
      |> Map.values()
      |> Enum.map(& &1.definition)
    end)
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
    ensure_registry_started()
    
    case get_tool_entry(tool_name) do
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

  ## Returns
    Map of tool names to tool entries.
  """
  @spec list_tools() :: %{String.t() => tool_entry()}
  def list_tools do
    ensure_registry_started()
    Agent.get(__MODULE__.Registry, & &1)
  end

  @doc """
  Checks if a tool is registered.

  ## Parameters
    - `tool_name`: Name of the tool to check

  ## Returns
    Boolean indicating if the tool exists.
  """
  @spec tool_exists?(String.t()) :: boolean()
  def tool_exists?(tool_name) do
    ensure_registry_started()
    
    Agent.get(__MODULE__.Registry, fn registry ->
      Map.has_key?(registry, tool_name)
    end)
  end

  # Private Functions

  defp ensure_registry_started do
    case Process.whereis(__MODULE__.Registry) do
      nil -> 
        {:ok, _pid} = Agent.start_link(fn -> %{} end, name: __MODULE__.Registry)
        :ok
      _pid -> 
        :ok
    end
  end

  defp get_tool_entry(tool_name) do
    Agent.get(__MODULE__.Registry, fn registry ->
      case Map.get(registry, tool_name) do
        nil -> {:error, :not_found}
        tool_entry -> {:ok, tool_entry}
      end
    end)
  end

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
    schema = definition["parameters"]
    required_params = Map.get(schema, "required", [])
    
    missing_required = Enum.filter(required_params, fn param ->
      not Map.has_key?(arguments, param)
    end)
    
    if length(missing_required) > 0 do
      {:error, "Missing required parameters: #{inspect(missing_required)}"}
    else
      :ok
    end
  end

  defp safe_execute_tool(tool_entry, arguments) do
    try do
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

  # DSL Macros

  @doc """
  Macro to use the Tooling DSL in a module.

  This sets up the module for defining tools using the `deftool` macro.
  """
  defmacro __using__(_opts) do
    quote do
      import TheMaestro.Tooling, only: [deftool: 2]
      @before_compile TheMaestro.Tooling
      
      Module.register_attribute(__MODULE__, :_tools, accumulate: true)
    end
  end

  @doc """
  Defines a tool using a declarative DSL.

  This macro provides a clean, declarative way to define tools without
  having to manually implement the Tool behaviour.

  ## Example

      deftool :read_file do
        description "Reads the contents of a file"
        
        parameter :path, :string, "File path to read", required: true
        parameter :encoding, :string, "File encoding (default: utf8)", required: false
        
        execute fn %{"path" => path} = args ->
          encoding = Map.get(args, "encoding", "utf8")
          case File.read(path) do
            {:ok, content} -> {:ok, %{"content" => content, "encoding" => encoding}}
            {:error, reason} -> {:error, "Failed to read file: #{reason}"}
          end
        end
      end
  """
  defmacro deftool(name, do: body) when is_atom(name) do
    quote do
      @_tools {unquote(name), unquote(body)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    tools = Module.get_attribute(env.module, :_tools)
    
    tool_functions = Enum.map(tools, fn {name, body} ->
      generate_tool_function(name, body, env.module)
    end)
    
    registration_function = generate_registration_function(tools, env.module)
    
    quote do
      unquote_splicing(tool_functions)
      unquote(registration_function)
    end
  end

  defp generate_tool_function(name, body, module) do
    # Parse the DSL body to extract definition and executor
    {definition_ast, executor_ast} = parse_tool_body(body)
    
    quote do
      def unquote(:"__tool_#{name}__")() do
        definition = unquote(definition_ast)
        executor = unquote(executor_ast)
        
        TheMaestro.Tooling.register_tool(
          to_string(unquote(name)),
          unquote(module),
          definition,
          executor
        )
      end
    end
  end

  defp generate_registration_function(tools, module) do
    tool_names = Enum.map(tools, fn {name, _} -> name end)
    
    quote do
      def __register_tools__() do
        unquote_splicing(
          Enum.map(tool_names, fn name ->
            quote do: unquote(:"__tool_#{name}__")()
          end)
        )
        :ok
      end
      
      # Auto-register tools when the module is loaded
      __register_tools__()
    end
  end

  defp parse_tool_body(body) do
    # This is a simplified parser for the DSL
    # In a production implementation, you might want a more sophisticated parser
    
    description = extract_description(body)
    parameters = extract_parameters(body)
    executor = extract_executor(body)
    
    definition_ast = quote do
      %{
        "name" => unquote(to_string(extract_tool_name_from_context())),
        "description" => unquote(description),
        "parameters" => %{
          "type" => "object",
          "properties" => unquote(Macro.escape(parameters[:properties] || %{})),
          "required" => unquote(parameters[:required] || [])
        }
      }
    end
    
    {definition_ast, executor}
  end

  defp extract_description({:__block__, _, statements}) do
    Enum.find_value(statements, "", fn
      {:description, _, [desc]} when is_binary(desc) -> desc
      _ -> false
    end)
  end
  defp extract_description({:description, _, [desc]}) when is_binary(desc), do: desc
  defp extract_description(_), do: ""

  defp extract_parameters({:__block__, _, statements}) do
    params = Enum.filter(statements, fn
      {:parameter, _, _} -> true
      _ -> false
    end)
    
    parse_parameters(params)
  end
  defp extract_parameters({:parameter, _, _} = param) do
    parse_parameters([param])
  end
  defp extract_parameters(_), do: %{properties: %{}, required: []}

  defp parse_parameters(params) do
    {properties, required} = 
      Enum.reduce(params, {%{}, []}, fn param, {props, req} ->
        case param do
          {:parameter, _, [name, type, desc]} ->
            prop_name = to_string(name)
            prop_def = %{
              "type" => to_string(type),
              "description" => desc
            }
            {Map.put(props, prop_name, prop_def), req}
            
          {:parameter, _, [name, type, desc, [required: true]]} ->
            prop_name = to_string(name)
            prop_def = %{
              "type" => to_string(type),
              "description" => desc
            }
            {Map.put(props, prop_name, prop_def), [prop_name | req]}
            
          _ ->
            {props, req}
        end
      end)
    
    %{properties: properties, required: Enum.reverse(required)}
  end

  defp extract_executor({:__block__, _, statements}) do
    Enum.find_value(statements, fn
      {:execute, _, [func]} -> func
      _ -> false
    end) || quote(do: fn _ -> {:error, "No executor defined"} end)
  end
  defp extract_executor({:execute, _, [func]}), do: func
  defp extract_executor(_), do: quote(do: fn _ -> {:error, "No executor defined"} end)

  defp extract_tool_name_from_context do
    # This is a placeholder - in a real implementation you'd need to track
    # the current tool name being processed
    "unknown"
  end
end