defmodule TheMaestro.Prompts.SystemInstructions.Modules.ContextAwareness do
  @moduledoc """
  Environmental context awareness module for system instructions.
  """

  @doc """
  Generates environmental context information based on the given context.
  """
  def generate(context) do
    current_date = Map.get(context, :current_date, "Unknown")
    operating_system = Map.get(context, :operating_system, "Unknown")
    working_directory = Map.get(context, :working_directory, "Unknown")
    available_tools = Map.get(context, :available_tools, [])
    connected_mcp_servers = Map.get(context, :connected_mcp_servers, [])
    sandbox_enabled = Map.get(context, :sandbox_enabled, false)
    project_type = Map.get(context, :project_type) || detect_project_type(working_directory)
    project_structure = Map.get(context, :project_structure, [])

    base_context = """
    # Current Environment

    - **Date:** #{current_date}
    - **Operating System:** #{operating_system}
    - **Working Directory:** #{working_directory}
    - **Project Type:** #{project_type}
    - **Available Tools:** #{length(available_tools)} tools
    - **MCP Servers:** #{format_mcp_servers(connected_mcp_servers)} connected
    - **Sandbox Mode:** #{if(sandbox_enabled, do: "Enabled", else: "Disabled")}
    """

    project_section =
      if Enum.empty?(project_structure) do
        ""
      else
        """

        ## Project Structure

        #{generate_directory_listing(project_structure)}
        """
      end

    base_context <> project_section
  end

  defp detect_project_type(working_directory) do
    cond do
      String.contains?(working_directory, "node_modules") or
          String.ends_with?(working_directory, ".js") ->
        "Node.js"

      String.contains?(working_directory, "mix.exs") or
          String.contains?(working_directory, "_build") ->
        "Elixir"

      String.contains?(working_directory, "requirements.txt") or
          String.contains?(working_directory, ".py") ->
        "Python"

      String.contains?(working_directory, "Cargo.toml") ->
        "Rust"

      String.contains?(working_directory, "go.mod") ->
        "Go"

      String.contains?(working_directory, "package.json") ->
        "JavaScript/TypeScript"

      true ->
        "Unknown"
    end
  end

  defp format_mcp_servers(servers) when is_list(servers) do
    case length(servers) do
      0 -> "No servers"
      count -> "#{Enum.join(servers, ", ")} (#{count})"
    end
  end

  defp format_mcp_servers(_), do: "Unknown"

  defp generate_directory_listing(structure) when is_list(structure) do
    structure
    # Limit to prevent overwhelming output
    |> Enum.take(20)
    |> Enum.map(&format_directory_item/1)
    |> Enum.join("\n")
    |> case do
      "" -> "Project structure information not available"
      listing -> listing
    end
  end

  defp generate_directory_listing(_), do: "Project structure information not available"

  defp format_directory_item(item) when is_binary(item) do
    cond do
      String.ends_with?(item, "/") -> "📁 #{item}"
      String.contains?(item, ".") -> "📄 #{item}"
      true -> "📂 #{item}"
    end
  end

  defp format_directory_item(item), do: "❓ #{inspect(item)}"
end
