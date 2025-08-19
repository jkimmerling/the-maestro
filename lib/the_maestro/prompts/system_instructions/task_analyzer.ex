defmodule TheMaestro.Prompts.SystemInstructions.TaskAnalyzer do
  @moduledoc """
  Analyzes task context to determine task characteristics and requirements.
  """

  alias TheMaestro.Prompts.SystemInstructions.TaskContext

  @doc """
  Analyzes the given context to extract task characteristics.
  """
  def analyze_task_context(context) do
    %TaskContext{
      primary_task_type: determine_primary_task_type(context),
      complexity_level: assess_complexity_level(context),
      required_capabilities: identify_required_capabilities(context),
      time_sensitivity: assess_time_sensitivity(context),
      risk_level: assess_risk_level(context),
      collaboration_mode: determine_collaboration_mode(context)
    }
  end

  @doc """
  Determines the primary task type based on context clues.
  """
  def determine_primary_task_type(context) do
    user_request = Map.get(context, :user_request, "")
    task_type = Map.get(context, :task_type)

    cond do
      task_type -> task_type
      contains_keywords?(user_request, debugging_keywords()) -> :debugging
      contains_keywords?(user_request, documentation_keywords()) -> :documentation
      contains_keywords?(user_request, new_application_keywords()) -> :new_application
      contains_keywords?(user_request, software_engineering_keywords()) -> :software_engineering
      true -> :generic
    end
  end

  @doc """
  Assesses the complexity level of the task.
  """
  def assess_complexity_level(context) do
    user_request = Map.get(context, :user_request, "")
    available_tools = Map.get(context, :available_tools, [])
    project_files = Map.get(context, :project_files, [])
    estimated_scope = Map.get(context, :estimated_scope)
    architectural_changes = Map.get(context, :architectural_changes, false)

    cond do
      architectural_changes or contains_keywords?(user_request, high_complexity_keywords()) -> :high
      estimated_scope == :system_wide or length(project_files) > 10 -> :high
      contains_keywords?(user_request, simple_task_keywords()) or estimated_scope == :single_file -> :low
      estimated_scope == :multi_file or length(available_tools) > 2 -> :moderate
      contains_keywords?(user_request, ["new React app", "Create a new"]) -> :high
      true -> :moderate
    end
  end

  @doc """
  Identifies required capabilities based on the task context.
  """
  def identify_required_capabilities(context) do
    user_request = Map.get(context, :user_request, "")
    available_tools = Map.get(context, :available_tools, [])
    capabilities = []

    capabilities = if has_file_tools?(available_tools) do
      [:file_operations | capabilities]
    else
      capabilities
    end

    capabilities = if has_command_tools?(available_tools) do
      [:command_execution | capabilities]
    else
      capabilities
    end

    capabilities = if contains_keywords?(user_request, ["test", "testing", "spec", "verify"]) do
      [:testing | capabilities]
    else
      capabilities
    end

    capabilities = if contains_security_keywords?(context) do
      [:security_analysis | capabilities]
    else
      capabilities
    end

    capabilities = if contains_performance_keywords?(context) do
      [:performance_analysis | capabilities]
    else
      capabilities
    end

    capabilities
  end

  @doc """
  Assesses time sensitivity of the task.
  """
  def assess_time_sensitivity(context) do
    user_request = Map.get(context, :user_request, "")
    urgency_keywords = Map.get(context, :urgency_keywords, [])
    flexible_keywords = Map.get(context, :flexible_keywords, [])

    cond do
      contains_keywords?(user_request, ["urgent", "critical", "immediate", "asap"]) or 
      length(urgency_keywords) > 0 -> :urgent
      contains_keywords?(user_request, ["when you have time", "eventually", "nice to have"]) or
      length(flexible_keywords) > 0 -> :flexible
      true -> :normal
    end
  end

  @doc """
  Assesses the risk level of the task.
  """
  def assess_risk_level(context) do
    primary_task_type = Map.get(context, :primary_task_type, :generic)
    security_sensitive = Map.get(context, :security_sensitive, false)
    affects_production = Map.get(context, :affects_production, false)
    has_tests = Map.get(context, :has_tests, false)
    urgency_level = Map.get(context, :urgency_level, :normal)
    user_request = Map.get(context, :user_request, "")

    cond do
      security_sensitive and affects_production and urgency_level == :urgent -> :critical
      security_sensitive and affects_production -> :high
      primary_task_type == :debugging and affects_production -> :high
      contains_keywords?(user_request, ["authentication", "security", "vulnerability"]) -> :high
      primary_task_type == :software_engineering and not has_tests -> :medium
      primary_task_type == :documentation -> :low
      true -> :medium
    end
  end

  @doc """
  Determines the collaboration mode needed for the task.
  """
  def determine_collaboration_mode(context) do
    user_request = Map.get(context, :user_request, "")
    task_clarity = Map.get(context, :task_clarity, :medium)
    requires_clarification = Map.get(context, :requires_clarification, false)
    educational_intent = Map.get(context, :educational_intent, false)
    learning_indicators = Map.get(context, :learning_indicators, [])

    cond do
      educational_intent or length(learning_indicators) > 0 or
      contains_keywords?(user_request, ["show me", "how to", "explain", "teach"]) -> :guided
      requires_clarification or task_clarity == :low or
      contains_keywords?(user_request, ["better", "improve", "enhance"]) -> :collaborative
      task_clarity == :high -> :autonomous
      true -> :autonomous
    end
  end

  @doc """
  Extracts various context clues from the input.
  """
  def extract_context_clues(context) do
    user_request = Map.get(context, :user_request, "")
    project_files = Map.get(context, :project_files, [])

    %{
      mentioned_files: extract_file_references(user_request, project_files),
      programming_languages: detect_programming_languages(user_request, project_files),
      technologies: detect_technologies(user_request, project_files),
      task_indicators: extract_task_indicators(user_request),
      priority_indicators: extract_priority_indicators(user_request),
      environment_indicators: extract_environment_indicators(user_request),
      severity_indicators: extract_severity_indicators(user_request),
      domain_areas: detect_domain_areas(user_request, project_files)
    }
  end

  # Private helper functions

  defp software_engineering_keywords do
    ["implement", "feature", "refactor", "optimize", "test", 
     "add", "remove", "update", "modify", "enhance", "improve", "code", "function",
     "authentication system", "payment system"]
  end

  defp new_application_keywords do
    ["create a new", "build a", "develop a new", "from scratch", "bootstrap", "initialize",
     "new project", "new application", "new app", "new microservice", "scaffold"]
  end

  defp debugging_keywords do
    ["debug", "troubleshoot", "investigate", "failing", "broken", "not working", "crash",
     "fix the bug", "debug the", "investigate the", "why the tests"]
  end

  defp documentation_keywords do
    ["document", "readme", "guide", "manual", "wiki", "docs", "documentation",
     "comment", "explain", "describe"]
  end

  defp high_complexity_keywords do
    ["architecture", "system", "migrate", "redesign", "overhaul",
     "complex", "comprehensive", "entire", "complete", "refactor the database"]
  end

  defp simple_task_keywords do
    ["typo", "fix typo", "simple", "quick", "small", "minor", "comment"]
  end

  defp contains_keywords?(text, keywords) do
    text_lower = String.downcase(text)
    Enum.any?(keywords, fn keyword -> String.contains?(text_lower, String.downcase(keyword)) end)
  end

  defp has_file_tools?(tools) do
    Enum.any?(tools, fn
      %{name: name} -> String.contains?(to_string(name), "file")
      name when is_atom(name) -> String.contains?(to_string(name), "file")
      _ -> false
    end)
  end

  defp has_command_tools?(tools) do
    Enum.any?(tools, fn
      %{name: name} -> String.contains?(to_string(name), "command") or String.contains?(to_string(name), "execute")
      name when is_atom(name) -> String.contains?(to_string(name), "command") or String.contains?(to_string(name), "execute")
      _ -> false
    end)
  end

  defp contains_security_keywords?(context) do
    user_request = Map.get(context, :user_request, "")
    security_keywords = ["security", "authentication", "authorization", "password", "token",
                        "vulnerability", "secure", "encrypt", "decrypt", "auth"]
    contains_keywords?(user_request, security_keywords)
  end

  defp contains_performance_keywords?(context) do
    user_request = Map.get(context, :user_request, "")
    performance_keywords = ["performance", "optimize", "slow", "fast", "speed", "bottleneck",
                           "efficient", "cache", "memory", "cpu"]
    contains_keywords?(user_request, performance_keywords)
  end

  defp extract_file_references(user_request, project_files) do
    # Extract file paths mentioned in the request
    file_pattern = ~r/[\w\-\.\/]+\.\w+/
    
    mentioned = Regex.scan(file_pattern, user_request)
    |> Enum.map(fn [file] -> file end)
    
    # Also include project files that are directly mentioned
    direct_mentions = Enum.filter(project_files, fn file ->
      String.contains?(user_request, file)
    end)
    
    Enum.uniq(mentioned ++ direct_mentions)
  end

  defp detect_programming_languages(user_request, project_files) do
    languages = []
    
    # From file extensions
    extensions = project_files
    |> Enum.map(&Path.extname/1)
    |> Enum.map(&String.trim_leading(&1, "."))
    
    languages = languages ++ 
      case Enum.member?(extensions, "ex") or Enum.member?(extensions, "exs") do
        true -> [:elixir]
        false -> []
      end
    
    languages = languages ++
      case Enum.member?(extensions, "tsx") or Enum.member?(extensions, "jsx") do
        true -> [:typescript, :react]
        false -> []
      end
    
    # From user request mentions
    languages = languages ++
      cond do
        contains_keywords?(user_request, ["react", "jsx", "tsx"]) -> [:react, :typescript]
        contains_keywords?(user_request, ["elixir", "phoenix"]) -> [:elixir]
        contains_keywords?(user_request, ["python", "py"]) -> [:python]
        contains_keywords?(user_request, ["javascript", "js"]) -> [:javascript]
        true -> []
      end
    
    Enum.uniq(languages)
  end

  defp detect_technologies(user_request, project_files) do
    technologies = []
    
    # From file patterns
    technologies = technologies ++
      cond do
        Enum.any?(project_files, &String.contains?(&1, "package.json")) -> [:npm, :node]
        Enum.any?(project_files, &String.contains?(&1, "mix.exs")) -> [:elixir, :mix]
        true -> []
      end
    
    # From user request
    technologies = technologies ++
      cond do
        contains_keywords?(user_request, ["react", "component"]) -> [:react]
        contains_keywords?(user_request, ["api", "endpoint"]) -> [:api]
        contains_keywords?(user_request, ["database", "db"]) -> [:database]
        true -> []
      end
    
    Enum.uniq(technologies)
  end

  defp extract_task_indicators(user_request) do
    indicators = []
    
    indicators = indicators ++
      cond do
        contains_keywords?(user_request, ["fix", "bug"]) -> [:bug_fix]
        contains_keywords?(user_request, ["add", "new", "create"]) -> [:feature_addition]
        contains_keywords?(user_request, ["refactor", "improve"]) -> [:refactoring]
        contains_keywords?(user_request, ["test", "testing"]) -> [:testing]
        true -> []
      end
    
    indicators
  end

  defp extract_priority_indicators(user_request) do
    cond do
      contains_keywords?(user_request, ["urgent", "critical", "immediately"]) -> [:urgent]
      contains_keywords?(user_request, ["high priority", "important"]) -> [:high]
      contains_keywords?(user_request, ["low priority", "nice to have"]) -> [:low]
      true -> [:normal]
    end
  end

  defp extract_environment_indicators(user_request) do
    cond do
      contains_keywords?(user_request, ["production", "prod", "live"]) -> [:production]
      contains_keywords?(user_request, ["development", "dev", "local"]) -> [:development]
      contains_keywords?(user_request, ["testing", "test", "staging"]) -> [:testing]
      true -> [:unknown]
    end
  end

  defp extract_severity_indicators(user_request) do
    cond do
      contains_keywords?(user_request, ["critical", "severe", "breaking"]) -> [:critical]
      contains_keywords?(user_request, ["major", "important"]) -> [:major]
      contains_keywords?(user_request, ["minor", "small"]) -> [:minor]
      true -> [:normal]
    end
  end

  defp detect_domain_areas(user_request, project_files) do
    areas = []
    
    areas = areas ++
      cond do
        contains_keywords?(user_request, ["ui", "component", "frontend", "interface"]) -> [:frontend]
        contains_keywords?(user_request, ["api", "backend", "server", "database"]) -> [:backend]
        contains_keywords?(user_request, ["deploy", "infrastructure", "ci/cd"]) -> [:devops]
        contains_keywords?(user_request, ["security", "auth", "vulnerability"]) -> [:security]
        true -> []
      end
    
    # From project structure
    areas = areas ++
      cond do
        Enum.any?(project_files, &String.contains?(&1, "components")) -> [:frontend]
        Enum.any?(project_files, &String.contains?(&1, "controllers")) -> [:backend]
        Enum.any?(project_files, &String.contains?(&1, "test")) -> [:testing]
        true -> []
      end
    
    Enum.uniq(areas)
  end
end