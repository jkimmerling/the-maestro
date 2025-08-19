defmodule TheMaestro.Prompts.SystemInstructions.Modules.ToolIntegration do
  @moduledoc """
  Tool integration instructions module for system instructions.
  """

  @doc """
  Generates tool integration instructions for the given tools.
  """
  def generate(tools) when is_list(tools) do
    if Enum.empty?(tools) do
      generate_no_tools_message()
    else
      generate_tools_instructions(tools)
    end
  end

  defp generate_no_tools_message do
    """
    ## Available Tools

    No tools currently available for this session. You can only provide analysis and recommendations based on your training knowledge.

    ## Tool Usage Guidelines

    - Request tool access if needed for the current task
    - Explain what tools would be helpful for specific operations
    - Provide detailed instructions for manual execution when tools are unavailable
    """
  end

  defp generate_tools_instructions(tools) do
    tool_descriptions = Enum.map(tools, &format_tool_description/1)

    """
    ## Available Tools

    You have access to the following tools for completing tasks:

    #{Enum.join(tool_descriptions, "\n\n")}

    ## Tool Usage Guidelines

    - **Parallelism:** Execute multiple independent tool calls in parallel when feasible
    - **File Paths:** Always use absolute paths when referring to files
    - **Confirmation:** Some tools may require user confirmation based on trust settings
    - **Error Handling:** Handle tool errors gracefully and provide alternatives
    - **Security:** Verify tool parameters for security risks before execution
    - **Efficiency:** Batch related operations when possible to minimize tool calls
    """
  end

  defp format_tool_description(tool) do
    case tool do
      %{name: name, description: description, usage: usage} ->
        "**#{name}**: #{description}\n  Usage: #{usage}"

      %{name: name, description: description} ->
        "**#{name}**: #{description}"

      %{name: name} ->
        "**#{name}**: #{infer_description(name)}"

      name when is_atom(name) ->
        "**#{name}**: #{infer_description(name)}"

      name when is_binary(name) ->
        "**#{name}**: #{infer_description(name)}"

      _ ->
        "**unknown_tool**: Tool description not available"
    end
  end

  defp infer_description(name) do
    name_str = to_string(name)

    cond do
      String.contains?(name_str, "read") and String.contains?(name_str, "file") ->
        "Read file contents from the filesystem"

      String.contains?(name_str, "write") and String.contains?(name_str, "file") ->
        "Write content to files on the filesystem"

      String.contains?(name_str, "execute") or String.contains?(name_str, "command") ->
        "Execute shell commands on the system"

      String.contains?(name_str, "list") or String.contains?(name_str, "directory") ->
        "List directory contents and file information"

      String.contains?(name_str, "search") or String.contains?(name_str, "find") ->
        "Search for files, content, or information"

      String.contains?(name_str, "web") and String.contains?(name_str, "fetch") ->
        "Fetch content from web URLs"

      String.contains?(name_str, "web") and String.contains?(name_str, "search") ->
        "Search the web for information"

      String.contains?(name_str, "memory") or String.contains?(name_str, "save") ->
        "Save information to memory for later retrieval"

      true ->
        "Tool for #{String.replace(name_str, "_", " ")}"
    end
  end
end
