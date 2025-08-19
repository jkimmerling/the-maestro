defmodule TheMaestro.Prompts.Enhancement.Integrators.ContextIntegrator do
  @moduledoc """
  Context integration engine that seamlessly weaves contextual information into prompts.

  This module implements sophisticated context integration strategies to enhance
  user prompts with relevant environmental, project, and situational information.
  """

  alias TheMaestro.Prompts.Enhancement.Structs.ContextItem

  @doc """
  Integrates context into the original prompt using multiple integration strategies.

  ## Parameters

  - `original_prompt` - The user's original prompt
  - `scored_context` - List of ContextItem structs sorted by relevance
  - `integration_config` - Configuration for integration behavior

  ## Returns

  A map with integrated context sections:
  - `pre_context` - Context to show before the user prompt
  - `enhanced_prompt` - The original prompt with inline enhancements
  - `post_context` - Additional context after the prompt
  - `metadata` - Integration metadata
  """
  @spec integrate_context_into_prompt(String.t(), [ContextItem.t()], map()) :: map()
  def integrate_context_into_prompt(original_prompt, scored_context, integration_config) do
    context_sections = %{
      pre_context: build_pre_prompt_context(scored_context, integration_config),
      inline_context: build_inline_context(original_prompt, scored_context),
      post_context: build_post_prompt_context(scored_context, integration_config),
      metadata: build_context_metadata(scored_context)
    }

    %{
      pre_context: context_sections.pre_context,
      enhanced_prompt: merge_inline_context(original_prompt, context_sections.inline_context),
      post_context: context_sections.post_context,
      metadata: context_sections.metadata,
      total_tokens: estimate_token_count(context_sections),
      relevance_scores: extract_relevance_scores(scored_context)
    }
  end

  @doc """
  Builds pre-prompt context that sets up the environment before the user's prompt.
  """
  @spec build_pre_prompt_context([ContextItem.t()], map()) :: String.t()
  def build_pre_prompt_context(scored_context, config) do
    environmental_info = extract_context_by_type(scored_context, :environmental)
    project_info = extract_context_by_type(scored_context, :project_structure)
    tool_info = extract_context_by_type(scored_context, :tool_availability)
    mcp_info = extract_context_by_type(scored_context, :mcp_integration)

    max_lines = Map.get(config, :max_context_lines, 30)

    sections = []

    # Add environment section if available
    sections =
      if environmental_info do
        env_section = format_environmental_section(environmental_info)
        [env_section | sections]
      else
        sections
      end

    # Add project section if available
    sections =
      if project_info do
        project_section = format_project_section(project_info, max_lines)
        [project_section | sections]
      else
        sections
      end

    # Add capabilities section if tools or MCP available
    sections =
      if tool_info || mcp_info do
        capabilities_section = format_capabilities_section(tool_info, mcp_info)
        [capabilities_section | sections]
      else
        sections
      end

    if Enum.empty?(sections) do
      ""
    else
      header = "This is The Maestro AI assistant. Context for current interaction:\n\n"
      footer = "\n---\n"

      header <> Enum.join(sections, "\n\n") <> footer
    end
  end

  @doc """
  Builds inline context enhancements for the original prompt.
  """
  @spec build_inline_context(String.t(), [ContextItem.t()]) :: String.t()
  def build_inline_context(original_prompt, scored_context) do
    entity_context = build_entity_context(original_prompt, scored_context)
    reference_context = build_reference_context(original_prompt, scored_context)
    dependency_context = build_dependency_context(original_prompt, scored_context)

    inline_additions =
      [entity_context, reference_context, dependency_context]
      |> Enum.filter(&(&1 != ""))
      |> Enum.join(" ")

    if inline_additions == "" do
      ""
    else
      " (Context: #{inline_additions})"
    end
  end

  @doc """
  Builds post-prompt context for additional information.
  """
  @spec build_post_prompt_context([ContextItem.t()], map()) :: String.t()
  def build_post_prompt_context(scored_context, _config) do
    security_context = extract_context_by_type(scored_context, :security_context)
    performance_context = extract_context_by_type(scored_context, :performance_context)

    sections = []

    sections =
      if security_context do
        security_section = format_security_section(security_context)
        [security_section | sections]
      else
        sections
      end

    sections =
      if performance_context do
        performance_section = format_performance_section(performance_context)
        [performance_section | sections]
      else
        sections
      end

    if Enum.empty?(sections) do
      ""
    else
      "\n\nAdditional Context:\n" <> Enum.join(sections, "\n")
    end
  end

  # Private helper functions

  defp merge_inline_context(original_prompt, inline_context) do
    if inline_context == "" do
      original_prompt
    else
      original_prompt <> inline_context
    end
  end

  defp build_context_metadata(scored_context) do
    %{
      context_items_count: length(scored_context),
      average_relevance: calculate_average_relevance(scored_context),
      context_types: extract_context_types(scored_context),
      integration_timestamp: DateTime.utc_now()
    }
  end

  defp estimate_token_count(context_sections) do
    content =
      [
        Map.get(context_sections, :pre_context, ""),
        Map.get(context_sections, :inline_context, ""),
        Map.get(context_sections, :post_context, "")
      ]
      |> Enum.join(" ")

    # Rough token estimation: ~4 characters per token
    round(String.length(content) / 4)
  end

  defp extract_relevance_scores(scored_context) do
    Enum.map(scored_context, & &1.relevance_score)
  end

  defp extract_context_by_type(scored_context, type) do
    scored_context
    |> Enum.find(fn item -> item.type == type end)
    |> case do
      nil -> nil
      item -> item.value
    end
  end

  defp format_environmental_section(env_info) do
    case env_info do
      %{timestamp: timestamp, operating_system: os, working_directory: wd} ->
        """
        ## Environment
        - Date: #{format_datetime(timestamp)}
        - OS: #{os}
        - Working Directory: #{wd}
        """

      _ ->
        "## Environment\n- Basic environment information available"
    end
  end

  defp format_project_section(project_info, _max_lines) do
    case project_info do
      %{project_type: project_type, language_detection: languages} ->
        lang_str =
          if is_list(languages) and length(languages) > 0 do
            Enum.join(languages, ", ")
          else
            "Unknown"
          end

        """
        ## Project Context
        - Project Type: #{project_type || "Unknown"}
        - Languages: #{lang_str}
        """

      _ ->
        "## Project Context\n- Project information available"
    end
  end

  defp format_capabilities_section(tool_info, mcp_info) do
    sections = []

    sections =
      if tool_info && Map.has_key?(tool_info, :available_tools) do
        tools = Map.get(tool_info, :available_tools, [])
        tool_section = "- Tools: #{format_tool_list(tools)}"
        [tool_section | sections]
      else
        sections
      end

    sections =
      if mcp_info && Map.has_key?(mcp_info, :connected_servers) do
        servers = Map.get(mcp_info, :connected_servers, [])
        mcp_section = "- MCP Servers: #{format_mcp_servers(servers)}"
        [mcp_section | sections]
      else
        sections
      end

    if Enum.empty?(sections) do
      "## Available Capabilities\n- Standard capabilities available"
    else
      "## Available Capabilities\n" <> Enum.join(sections, "\n")
    end
  end

  defp format_security_section(_security_context) do
    "Security considerations apply to this operation."
  end

  defp format_performance_section(_performance_context) do
    "Performance monitoring is active for this session."
  end

  defp build_entity_context(_original_prompt, scored_context) do
    # Find entities in the prompt that have corresponding context
    code_context = extract_context_by_type(scored_context, :code_analysis)

    if code_context && Map.has_key?(code_context, :relevant_files) do
      files = Map.get(code_context, :relevant_files, [])

      if length(files) > 0 do
        "files: #{Enum.join(Enum.take(files, 3), ", ")}"
      else
        ""
      end
    else
      ""
    end
  end

  defp build_reference_context(_original_prompt, _scored_context) do
    # Placeholder for reference context building
    ""
  end

  defp build_dependency_context(_original_prompt, scored_context) do
    project_context = extract_context_by_type(scored_context, :project_structure)

    if project_context && Map.has_key?(project_context, :framework_detection) do
      frameworks = Map.get(project_context, :framework_detection, [])

      if length(frameworks) > 0 do
        "frameworks: #{Enum.join(frameworks, ", ")}"
      else
        ""
      end
    else
      ""
    end
  end

  defp calculate_average_relevance(scored_context) do
    if length(scored_context) > 0 do
      scores = Enum.map(scored_context, & &1.relevance_score)
      Enum.sum(scores) / length(scores)
    else
      0.0
    end
  end

  defp extract_context_types(scored_context) do
    Enum.map(scored_context, & &1.type) |> Enum.uniq()
  end

  defp format_datetime(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end

  defp format_datetime(_), do: "Unknown"

  defp format_tool_list(tools) when is_list(tools) do
    tools
    # Limit to first 5 tools
    |> Enum.take(5)
    |> Enum.join(", ")
  end

  defp format_tool_list(_), do: "Available"

  defp format_mcp_servers(servers) when is_list(servers) do
    servers
    # Limit to first 3 servers
    |> Enum.take(3)
    |> Enum.join(", ")
  end

  defp format_mcp_servers(_), do: "Connected"
end
