defmodule TheMaestro.Prompts.SystemInstructions.Modules.CapabilityDescription do
  @moduledoc """
  Agent capability description module for system instructions.
  """

  @doc """
  Generates capability description based on the current agent state.
  """
  def generate(agent_state) do
    current_provider = Map.get(agent_state, :current_provider, :unknown)
    current_model = Map.get(agent_state, :current_model, "unknown")
    file_access_level = Map.get(agent_state, :file_access_level, :none)
    command_execution_level = Map.get(agent_state, :command_execution_level, :none)
    available_mcp_tools = Map.get(agent_state, :available_mcp_tools, [])
    auth_status = Map.get(agent_state, :auth_status, :unknown)
    limitations = Map.get(agent_state, :limitations, [])

    """
    ## Your Current Capabilities

    ### Core Functions
    - Software engineering task assistance
    - Code analysis and modification
    - File system operations (#{format_access_level(file_access_level)})
    - Command execution (#{format_execution_level(command_execution_level)})
    
    ### Available Integrations
    - **LLM Provider:** #{current_provider}
    - **Model:** #{current_model}
    - **MCP Tools:** #{format_mcp_tools(available_mcp_tools)}
    - **Authentication:** #{format_auth_status(auth_status)}
    
    ### Current Limitations
    #{format_limitations(limitations)}
    """
  end

  defp format_access_level(:full), do: "full file system access"
  defp format_access_level(:read_only), do: "read-only file access"
  defp format_access_level(:restricted), do: "restricted file access"
  defp format_access_level(:none), do: "no file access"
  defp format_access_level(_), do: "unknown access level"

  defp format_execution_level(:full), do: "full command execution"
  defp format_execution_level(:restricted), do: "restricted command execution"
  defp format_execution_level(:sandboxed), do: "sandboxed command execution"
  defp format_execution_level(:none), do: "no command execution"
  defp format_execution_level(_), do: "unknown execution level"

  defp format_mcp_tools([]), do: "No MCP tools available"
  defp format_mcp_tools(tools) when is_list(tools) do
    tools
    |> Enum.map(&to_string/1)
    |> Enum.join(", ")
  end
  defp format_mcp_tools(_), do: "Unknown MCP tools"

  defp format_auth_status(:authenticated), do: "Authenticated and ready"
  defp format_auth_status(:unauthenticated), do: "Not authenticated"
  defp format_auth_status(:pending), do: "Authentication pending"
  defp format_auth_status(_), do: "Unknown authentication status"

  defp format_limitations([]), do: "No significant limitations identified"
  defp format_limitations(limitations) when is_list(limitations) do
    limitations
    |> Enum.map(&("- " <> &1))
    |> Enum.join("\n")
  end
  defp format_limitations(_), do: "Limitation information not available"
end