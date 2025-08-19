defmodule TheMaestro.Prompts.Enhancement.ContextGatherer do
  @moduledoc """
  Multi-source context collection system that gathers relevant environmental,
  project, and situational context for prompt enhancement.
  """

  alias TheMaestro.Prompts.Enhancement.Structs.{
    ContextAnalysis,
    IntentResult,
    EnvironmentalContext,
    ProjectStructureContext,
    CodeAnalysisContext
  }

  require Logger

  @context_sources [
    :environmental,          # OS, date, directory, etc.
    :project_structure,      # Files, directories, project type
    :session_history,        # Previous interactions, context
    :tool_availability,      # Available tools and capabilities
    :mcp_integration,        # Connected MCP servers and tools
    :user_preferences,       # User settings and preferences
    :code_analysis,          # Existing code patterns, dependencies
    :documentation,          # Available documentation and examples
    :security_context,       # Permissions, trust levels, sandboxing
    :performance_context     # System resources, constraints
  ]

  @doc """
  Gathers comprehensive context from multiple sources based on analysis and intent.

  ## Parameters

  - `analysis` - ContextAnalysis struct with prompt analysis results
  - `intent` - IntentResult struct with detected user intent
  - `user_context` - User and environmental context map

  ## Returns

  A map of gathered context organized by source type.
  """
  @spec gather_context(ContextAnalysis.t(), IntentResult.t(), map()) :: map()
  def gather_context(%ContextAnalysis{} = analysis, %IntentResult{} = intent, user_context) do
    context_requirements = determine_context_requirements(analysis, intent)
    
    @context_sources
    |> Enum.filter(&required_for_prompt?(&1, context_requirements))
    |> Enum.map(&gather_source_context(&1, user_context, analysis, intent))
    |> Enum.reduce(%{}, &merge_context_data/2)
  end

  @doc """
  Gathers environmental context information.
  """
  @spec gather_environmental_context(map()) :: EnvironmentalContext.t()
  def gather_environmental_context(user_context) do
    %EnvironmentalContext{
      timestamp: get_context_timestamp(user_context),
      timezone: get_user_timezone(user_context),
      operating_system: detect_operating_system(user_context),
      working_directory: get_current_working_directory(user_context),
      directory_contents: get_directory_listing(user_context, [limit: 200]),
      system_resources: get_system_resource_info(user_context),
      network_status: check_network_connectivity(user_context),
      shell_environment: get_relevant_env_vars(user_context),
      git_status: get_git_repository_status(user_context),
      project_type: detect_project_type(user_context)
    }
  end

  @doc """
  Gathers project structure context information.
  """
  @spec gather_project_structure_context(String.t(), map()) :: ProjectStructureContext.t()
  def gather_project_structure_context(_working_directory, user_context) do
    %ProjectStructureContext{
      project_type: detect_project_type(user_context),
      language_detection: detect_programming_languages(user_context),
      framework_detection: detect_frameworks_and_libraries(user_context),
      configuration_files: find_configuration_files(user_context),
      dependency_files: find_dependency_files(user_context),
      build_systems: detect_build_systems(user_context),
      test_frameworks: detect_test_frameworks(user_context),
      documentation_files: find_documentation_files(user_context),
      entry_points: find_application_entry_points(user_context),
      directory_structure: build_directory_tree(user_context, depth: 3),
      file_patterns: analyze_file_patterns(user_context),
      recent_changes: get_recent_file_changes(user_context)
    }
  end

  @doc """
  Gathers code analysis context for relevant files.
  """
  @spec gather_code_analysis_context(String.t(), map(), ContextAnalysis.t()) :: CodeAnalysisContext.t()
  def gather_code_analysis_context(prompt, user_context, analysis) do
    relevant_files = identify_relevant_files(prompt, user_context, analysis)
    
    %CodeAnalysisContext{
      relevant_files: relevant_files,
      code_patterns: analyze_code_patterns(relevant_files, user_context),
      dependencies: extract_dependencies(relevant_files, user_context),
      imports_and_exports: analyze_imports_exports(relevant_files, user_context),
      function_signatures: extract_function_signatures(relevant_files, user_context),
      class_definitions: extract_class_definitions(relevant_files, user_context),
      configuration_values: extract_configuration_values(relevant_files, user_context),
      test_coverage: analyze_test_coverage(relevant_files, user_context),
      documentation_coverage: analyze_documentation_coverage(relevant_files, user_context),
      code_quality_metrics: calculate_code_quality_metrics(relevant_files, user_context),
      architectural_patterns: identify_architectural_patterns(relevant_files, user_context),
      potential_issues: identify_potential_issues(relevant_files, user_context)
    }
  end

  # Private implementation functions

  defp determine_context_requirements(analysis, intent) do
    base_requirements = intent.context_requirements
    
    # Add requirements based on analysis
    analysis_requirements = case analysis.prompt_type do
      :software_engineering -> [:project_structure, :code_analysis, :dependencies]
      :file_operations -> [:current_directory, :file_permissions, :directory_structure]
      :system_operations -> [:operating_system, :available_commands, :permissions]
      :information_seeking -> [:knowledge_base, :documentation, :examples]
      _ -> []
    end
    
    # Add domain-specific requirements
    domain_requirements = analysis.domain_indicators
    |> Enum.flat_map(fn domain ->
      case domain do
        :software_development -> [:project_structure, :code_analysis]
        :web_development -> [:project_structure, :dependencies, :configuration]
        :devops -> [:system_resources, :deployment_context]
        :database -> [:configuration, :schema_analysis]
        _ -> []
      end
    end)
    
    (base_requirements ++ analysis_requirements ++ domain_requirements)
    |> Enum.uniq()
  end

  defp required_for_prompt?(source, requirements) do
    source_requirements = %{
      environmental: [:current_directory, :operating_system],
      project_structure: [:project_structure, :directory_structure],
      code_analysis: [:code_analysis, :existing_code],
      tool_availability: [:available_commands, :permissions],
      documentation: [:documentation, :knowledge_base, :examples],
      security_context: [:permissions, :security_analysis],
      performance_context: [:system_resources]
    }
    
    required = Map.get(source_requirements, source, [])
    Enum.any?(required, &(&1 in requirements))
  end

  defp gather_source_context(source, user_context, analysis, _intent) do
    try do
      case source do
        :environmental ->
          {source, gather_environmental_context(user_context)}
          
        :project_structure ->
          working_dir = get_current_working_directory(user_context)
          {source, gather_project_structure_context(working_dir, user_context)}
          
        :code_analysis ->
          prompt = Map.get(analysis, :original_prompt, "")
          {source, gather_code_analysis_context(prompt, user_context, analysis)}
          
        :tool_availability ->
          {source, gather_tool_availability_context(user_context)}
          
        :mcp_integration ->
          {source, gather_mcp_integration_context(user_context)}
          
        :session_history ->
          {source, gather_session_history_context(user_context)}
          
        :user_preferences ->
          {source, gather_user_preferences_context(user_context)}
          
        :documentation ->
          {source, gather_documentation_context(user_context, analysis)}
          
        :security_context ->
          {source, gather_security_context(user_context)}
          
        :performance_context ->
          {source, gather_performance_context(user_context)}
          
        _ ->
          Logger.warning("Unknown context source: #{source}")
          {source, %{}}
      end
    rescue
      error ->
        Logger.error("Error gathering context from #{source}: #{inspect(error)}")
        {source, %{error: error, timestamp: DateTime.utc_now()}}
    end
  end

  defp merge_context_data({source, data}, acc) do
    Map.put(acc, source, data)
  end


  # Context gathering helper functions

  defp get_context_timestamp(user_context) do
    case get_in(user_context, [:environment, :current_date]) do
      nil -> DateTime.utc_now()
      date_string when is_binary(date_string) ->
        case Date.from_iso8601(date_string) do
          {:ok, date} -> DateTime.new!(date, ~T[12:00:00], "Etc/UTC")
          _ -> DateTime.utc_now()
        end
      %DateTime{} = dt -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp get_user_timezone(user_context) do
    get_in(user_context, [:environment, :timezone]) || Map.get(user_context, :timezone, "UTC")
  end

  defp detect_operating_system(user_context) do
    Map.get(user_context, :operating_system) ||
    Map.get(user_context, :environment, %{}) |> Map.get(:operating_system, "Unknown")
  end

  defp get_current_working_directory(user_context) do
    Map.get(user_context, :working_directory, File.cwd!() || "/tmp")
  end

  defp get_directory_listing(user_context, opts) do
    limit = Keyword.get(opts, :limit, 100)
    working_dir = get_current_working_directory(user_context)
    
    case File.ls(working_dir) do
      {:ok, files} -> Enum.take(files, limit)
      {:error, _} -> []
    end
  end

  defp get_system_resource_info(user_context) do
    %{
      memory: Map.get(user_context, :system_memory, "Unknown"),
      cpu_count: Map.get(user_context, :cpu_count, System.schedulers_online()),
      load_average: Map.get(user_context, :load_average, "Unknown"),
      disk_space: Map.get(user_context, :disk_space, "Unknown")
    }
  end

  defp check_network_connectivity(user_context) do
    Map.get(user_context, :network_status, :connected)
  end

  defp get_relevant_env_vars(user_context) do
    env_vars = Map.get(user_context, :environment_variables, %{})
    
    # Filter to only relevant environment variables
    relevant_keys = [
      "PATH", "HOME", "USER", "SHELL", "PWD", "TERM",
      "NODE_ENV", "RAILS_ENV", "MIX_ENV", "PYTHON_ENV"
    ]
    
    Map.take(env_vars, relevant_keys)
  end

  defp get_git_repository_status(user_context) do
    working_dir = get_current_working_directory(user_context)
    git_dir = Path.join(working_dir, ".git")
    
    if File.exists?(git_dir) do
      %{
        is_git_repo: true,
        branch: get_git_branch(user_context),
        has_uncommitted_changes: get_git_status_info(user_context),
        last_commit: get_last_commit_info(user_context)
      }
    else
      nil
    end
  end

  defp detect_project_type(user_context) do
    project_context = Map.get(user_context, :project_context, %{})
    Map.get(project_context, :project_type, detect_project_type_from_files(user_context))
  end

  defp detect_project_type_from_files(user_context) do
    working_dir = get_current_working_directory(user_context)
    
    cond do
      File.exists?(Path.join(working_dir, "mix.exs")) -> "elixir_phoenix"
      File.exists?(Path.join(working_dir, "package.json")) -> "node_js"
      File.exists?(Path.join(working_dir, "Cargo.toml")) -> "rust"
      File.exists?(Path.join(working_dir, "go.mod")) -> "go"
      File.exists?(Path.join(working_dir, "requirements.txt")) -> "python"
      File.exists?(Path.join(working_dir, "Gemfile")) -> "ruby"
      true -> "unknown"
    end
  end

  # Stub implementations for complex operations
  # These would be more sophisticated in a real implementation

  defp detect_programming_languages(user_context) do
    project_type = detect_project_type(user_context)
    
    case project_type do
      "elixir_phoenix" -> ["elixir"]
      "node_js" -> ["javascript", "typescript"]
      "rust" -> ["rust"]
      "go" -> ["go"]
      "python" -> ["python"]
      "ruby" -> ["ruby"]
      _ -> []
    end
  end

  defp detect_frameworks_and_libraries(user_context) do
    project_type = detect_project_type(user_context)
    
    case project_type do
      "elixir_phoenix" -> ["phoenix", "ecto"]
      "node_js" -> ["express", "react", "vue"]
      _ -> []
    end
  end

  defp find_configuration_files(user_context) do
    working_dir = get_current_working_directory(user_context)
    
    config_patterns = [
      "config.*", "*.config.*", ".env*", "docker-compose.*",
      "mix.exs", "package.json", "Cargo.toml", "go.mod"
    ]
    
    config_patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(working_dir, pattern))
    end)
    |> Enum.map(&Path.basename/1)
  end

  defp find_dependency_files(user_context) do
    working_dir = get_current_working_directory(user_context)
    
    dependency_files = [
      "mix.lock", "package-lock.json", "yarn.lock", "Cargo.lock",
      "go.sum", "requirements.txt", "Pipfile.lock", "Gemfile.lock"
    ]
    
    dependency_files
    |> Enum.filter(fn file ->
      File.exists?(Path.join(working_dir, file))
    end)
  end

  # Additional stub implementations
  defp detect_build_systems(_user_context), do: []
  defp detect_test_frameworks(_user_context), do: []
  defp find_documentation_files(_user_context), do: []
  defp find_application_entry_points(_user_context), do: []
  defp build_directory_tree(_user_context, _opts), do: %{}
  defp analyze_file_patterns(_user_context), do: %{}
  defp get_recent_file_changes(_user_context), do: []
  defp identify_relevant_files(_prompt, _user_context, _analysis), do: []
  defp analyze_code_patterns(_files, _user_context), do: %{}
  defp extract_dependencies(_files, _user_context), do: []
  defp analyze_imports_exports(_files, _user_context), do: %{}
  defp extract_function_signatures(_files, _user_context), do: []
  defp extract_class_definitions(_files, _user_context), do: []
  defp extract_configuration_values(_files, _user_context), do: %{}
  defp analyze_test_coverage(_files, _user_context), do: %{}
  defp analyze_documentation_coverage(_files, _user_context), do: %{}
  defp calculate_code_quality_metrics(_files, _user_context), do: %{}
  defp identify_architectural_patterns(_files, _user_context), do: []
  defp identify_potential_issues(_files, _user_context), do: []
  defp gather_tool_availability_context(_user_context), do: %{}
  defp gather_mcp_integration_context(_user_context), do: %{}
  defp gather_session_history_context(_user_context), do: %{}
  defp gather_user_preferences_context(_user_context), do: %{}
  defp gather_documentation_context(_user_context, _analysis), do: %{}
  defp gather_security_context(_user_context), do: %{}
  defp gather_performance_context(_user_context), do: %{}
  defp get_git_branch(_user_context), do: "main"
  defp get_git_status_info(_user_context), do: false
  defp get_last_commit_info(_user_context), do: %{}
end