defmodule TheMaestro.Prompts.Enhancement.ContextAnalyzer do
  @moduledoc """
  Analyzes prompts and context to understand user intent, complexity, and requirements.
  
  This module performs sophisticated analysis of user prompts and context to determine:
  - Prompt type classification
  - User intent detection
  - Entity extraction
  - Complexity assessment
  - Domain identification
  - Urgency level assessment
  """

  alias TheMaestro.Prompts.Enhancement.Structs.{
    EnhancementContext,
    ContextAnalysis
  }

  defp prompt_type_patterns do
    %{
      software_engineering: [
        ~r/(?:fix|debug|refactor|optimize|improve).+(?:code|function|class|module|bug|authentication|error|issue|database|queries|query|performance)/i,
        ~r/(?:add|implement|create).+(?:feature|function|class|component|test|api|endpoint)/i,
        ~r/(?:analyze|review|explain).+(?:code|implementation|architecture|algorithm)/i,
        ~r/(?:unit test|integration test|testing|test coverage)/i,
        ~r/(?:bug|error|exception|crash|fail).+(?:in|with|on).+(?:service|module|component|function)/i,
        ~r/(?:authentication|authorization|security|validation|encryption)/i
      ],
      
      file_operations: [
        ~r/(?:read|write|create|delete|modify|edit).+(?:file|directory|\.json|\.yml|\.xml|\.txt|\.md)/i,
        ~r/(?:list|show|display).+(?:files|directories|contents|folder)/i,
        ~r/(?:find|search|locate).+(?:in|within).+(?:files|directory|folder)/i,
        ~r/(?:copy|move|rename).+(?:file|folder|directory)/i
      ],
      
      system_operations: [
        ~r/(?:run|execute|start|stop).+(?:command|script|process|server|test suite|tests)/i,
        ~r/(?:install|configure|setup).+(?:package|software|system|environment|dependencies)/i,
        ~r/(?:restart|reload|kill).+(?:server|service|process)/i,
        ~r/(?:shell|terminal|command line|bash|zsh|powershell)/i
      ],
      
      information_seeking: [
        ~r/^(?:what|how|why|when|where|which)/i,
        ~r/(?:explain|describe|tell me about|show me).+(?:how|what|concept|idea|pattern|example|programming|implementation)/i,
        ~r/(?:help|assist|guide|tutorial).+(?:with understanding|to learn|me learn)/i,
        ~r/(?:documentation|docs|manual|reference|information about)/i,
        ~r/(?:how do i|how to|how can i).+(?:implement|create|build|setup)/i
      ]
    }
  end

  defp complexity_indicators do
    %{
      high: [
        ~r/(?:architecture|design|system|distributed|microservice)/i,
        ~r/(?:performance|optimization|scaling|load balancing)/i,
        ~r/(?:security|authentication|authorization|encryption)/i,
        ~r/(?:database|query|transaction|migration)/i,
        ~r/(?:api|endpoint|service|integration)/i,
        ~r/(?:testing|test suite|ci\/cd|deployment)/i
      ],
      medium: [
        ~r/(?:function|method|class|module|component)/i,
        ~r/(?:configuration|config|settings|environment)/i,
        ~r/(?:file|data|json|csv|xml)/i,
        ~r/(?:user|interface|ui|form)/i
      ],
      low: [
        ~r/^\w+\s*\??\s*$/,  # Single word questions
        ~r/^(?:hello|hi|thanks|yes|no)\b/i,  # Greetings
        ~r/^.{1,20}$/  # Very short prompts
      ]
    }
  end

  defp urgency_indicators do
    %{
      high: [
        ~r/(?:urgent|emergency|critical|asap|immediately)/i,
        ~r/(?:down|broken|failing|error|crash)/i,
        ~r/(?:production|live|customer|user impact)/i,
        ~r/[!]{2,}/  # Multiple exclamation marks
      ],
      medium: [
        ~r/(?:soon|quick|fast|priority)/i,
        ~r/(?:issue|problem|bug|fix)/i,
        ~r/(?:needed|required|important)/i
      ],
      low: [
        ~r/(?:when you have time|no rush|eventually)/i,
        ~r/(?:could you|would you|maybe|perhaps)/i,
        ~r/(?:review|consider|think about)/i
      ]
    }
  end

  defp domain_indicators do
    %{
      software_development: [
        ~r/(?:code|programming|development|software)/i,
        ~r/(?:function|method|class|object|variable)/i,
        ~r/(?:bug|debug|test|refactor)/i
      ],
      web_development: [
        ~r/(?:html|css|javascript|react|vue|angular|phoenix|rails|django|flask|express)/i,
        ~r/(?:website|webpage|frontend|backend|web app|web application)/i,
        ~r/(?:api|endpoint|http|rest|authentication|oauth)/i
      ],
      devops: [
        ~r/(?:docker|kubernetes|deploy|ci\/cd)/i,
        ~r/(?:server|cloud|aws|azure|gcp)/i,
        ~r/(?:monitoring|logging|metrics)/i
      ],
      database: [
        ~r/(?:sql|database|query|table|schema)/i,
        ~r/(?:postgres|mysql|mongodb|redis)/i,
        ~r/(?:migration|backup|index)/i
      ],
      file_system: [
        ~r/(?:file|directory|folder|path)/i,
        ~r/(?:read|write|create|delete)/i
      ],
      monitoring: [
        ~r/(?:monitor|metrics|performance|health)/i,
        ~r/(?:alert|notification|dashboard)/i
      ],
      deployment: [
        ~r/(?:deploy|release|build|package)/i,
        ~r/(?:production|staging|environment)/i
      ]
    }
  end

  @doc """
  Analyzes the enhancement context to extract prompt characteristics and requirements.

  ## Parameters

  - `context` - EnhancementContext struct containing prompt and user context

  ## Returns

  Updated EnhancementContext with ContextAnalysis added to pipeline_state
  """
  @spec analyze_context(EnhancementContext.t()) :: EnhancementContext.t()
  def analyze_context(%EnhancementContext{} = context) do
    analysis = %ContextAnalysis{
      prompt_type: classify_prompt_type(context.original_prompt),
      user_intent: extract_user_intent(context.original_prompt),
      mentioned_entities: extract_entities(context.original_prompt),
      implicit_requirements: infer_implicit_requirements(context),
      complexity_level: assess_prompt_complexity(context.original_prompt),
      domain_indicators: identify_domain_indicators(context.original_prompt),
      urgency_level: assess_urgency(context),
      collaboration_mode: determine_collaboration_needs(context)
    }
    
    put_in(context.pipeline_state[:context_analysis], analysis)
  end

  @doc """
  Classifies the type of prompt based on pattern matching.
  """
  @spec classify_prompt_type(String.t()) :: atom()
  def classify_prompt_type(prompt) do
    prompt_type_patterns()
    |> Enum.map(fn {type, patterns} ->
      matches = Enum.count(patterns, &Regex.match?(&1, prompt))
      {type, matches}
    end)
    |> Enum.max_by(fn {_type, score} -> score end)
    |> case do
      {type, score} when score > 0 -> type
      _ -> :general
    end
  end

  @doc """
  Extracts the user's intent from the prompt.
  """
  @spec extract_user_intent(String.t()) :: atom()
  def extract_user_intent(prompt) do
    cond do
      # Question-based learning comes first
      Regex.match?(~r/^(?:how do i|how to|how can i)/i, prompt) -> :learning
      Regex.match?(~r/^(?:what|how|why|when|where|which)/i, prompt) -> :information_seeking
      Regex.match?(~r/(?:learn|understand|teach|explain)/i, prompt) -> :learning
      
      # Implementation and action intents
      Regex.match?(~r/(?:fix|debug|resolve)/i, prompt) -> :bug_fix
      Regex.match?(~r/(?:troubleshoot|investigate|analyze)/i, prompt) -> :troubleshooting
      Regex.match?(~r/(?:add|implement|create|build)/i, prompt) -> :feature_implementation
      Regex.match?(~r/(?:refactor|improve|clean)/i, prompt) -> :refactoring
      Regex.match?(~r/(?:optimize|performance|speed)/i, prompt) -> :optimization
      Regex.match?(~r/(?:read|show|display|list)/i, prompt) -> :read_file
      Regex.match?(~r/(?:write|create|save|update)/i, prompt) -> :write_file
      Regex.match?(~r/(?:deploy|release|publish)/i, prompt) -> :deployment
      Regex.match?(~r/(?:test|testing|spec)/i, prompt) -> :testing
      Regex.match?(~r/(?:config|configure|setup)/i, prompt) -> :configuration
      true -> :general
    end
  end

  @doc """
  Extracts entities mentioned in the prompt (files, services, technologies, etc.).
  """
  @spec extract_entities(String.t()) :: [String.t()]
  def extract_entities(prompt) do
    entities = []
    
    # Extract file names and extensions
    entities = entities ++ Regex.scan(~r/\b\w+\.\w+\b/, prompt) |> List.flatten()
    
    # Extract quoted strings (often file names or service names)
    entities = entities ++ Regex.scan(~r/"([^"]+)"/, prompt, capture: :all_but_first) |> List.flatten()
    entities = entities ++ Regex.scan(~r/'([^']+)'/, prompt, capture: :all_but_first) |> List.flatten()
    
    # Extract CamelCase identifiers (likely class/service names)
    entities = entities ++ Regex.scan(~r/\b[A-Z][a-z]+(?:[A-Z][a-z]+)+\b/, prompt) |> List.flatten()
    
    # Extract service and module names (e.g., "user service", "auth module", "payment system")
    service_patterns = [
      ~r/\b(\w+\s+(?:service|module|system|component|api|endpoint|controller|model))\b/i,
      ~r/\b(\w+(?:Service|Module|System|Component|API|Controller|Model))\b/,
      ~r/\b((?:user|auth|payment|order|product|inventory|notification|email|sms)\s+\w+)\b/i
    ]
    
    service_entities = service_patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, prompt, capture: :all_but_first) |> List.flatten()
    end)
    
    entities = entities ++ service_entities
    
    # Extract common tech terms
    tech_terms = [
      "authentication", "auth", "OAuth", "OAuth2", "JWT", "API", "REST", "GraphQL",
      "database", "PostgreSQL", "MySQL", "MongoDB", "Redis", "SQL",
      "Docker", "Kubernetes", "AWS", "Azure", "GCP",
      "React", "Vue", "Angular", "Phoenix", "Django", "Rails",
      "JavaScript", "TypeScript", "Python", "Elixir", "Go", "Rust",
      "config", "configuration", "environment", "production", "staging"
    ]
    
    found_terms = Enum.filter(tech_terms, fn term ->
      String.contains?(String.downcase(prompt), String.downcase(term))
    end)
    
    entities = entities ++ found_terms
    
    # Extract directory paths
    entities = entities ++ Regex.scan(~r/(?:\/[\w.-]+)+/, prompt) |> List.flatten()
    
    # Remove duplicates and empty strings
    entities
    |> Enum.uniq()
    |> Enum.reject(&(&1 == "" or String.length(&1) < 2))
  end

  @doc """
  Infers implicit requirements based on prompt and context analysis.
  """
  @spec infer_implicit_requirements(EnhancementContext.t()) :: [atom()]
  def infer_implicit_requirements(context) do
    requirements = []
    prompt = context.original_prompt
    
    # File system access needed
    requirements = if Regex.match?(~r/(?:file|directory|read|write|create|delete)/i, prompt) do
      [:file_access, :current_directory | requirements]
    else
      requirements
    end
    
    # Code analysis needed
    requirements = if Regex.match?(~r/(?:code|function|class|module|bug|debug)/i, prompt) do
      [:code_analysis, :project_structure, :existing_code | requirements]
    else
      requirements
    end
    
    # System operations needed
    requirements = if Regex.match?(~r/(?:install|run|execute|command|system)/i, prompt) do
      [:system_access, :available_commands, :permissions | requirements]
    else
      requirements
    end
    
    # Documentation needed
    requirements = if Regex.match?(~r/(?:what|how|explain|documentation|help)/i, prompt) do
      [:documentation, :knowledge_base, :examples | requirements]
    else
      requirements
    end
    
    # Project context needed
    requirements = if Regex.match?(~r/(?:build|deploy|test|configure|setup)/i, prompt) do
      [:project_structure, :dependencies, :build_tools | requirements]
    else
      requirements
    end
    
    Enum.uniq(requirements)
  end

  @doc """
  Assesses the complexity level of the prompt.
  """
  @spec assess_prompt_complexity(String.t()) :: atom()
  def assess_prompt_complexity(prompt) do
    # Count words as a basic complexity indicator
    word_count = String.split(prompt) |> length()
    
    # Check for high complexity indicators
    indicators = complexity_indicators()
    high_matches = count_pattern_matches(indicators.high, prompt)
    medium_matches = count_pattern_matches(indicators.medium, prompt)
    low_matches = count_pattern_matches(indicators.low, prompt)
    
    cond do
      high_matches > 0 or word_count > 20 -> :high
      medium_matches > 0 or word_count > 10 -> :medium
      low_matches > 0 or word_count <= 5 -> :low
      true -> :medium
    end
  end

  @doc """
  Identifies domain indicators from the prompt.
  """
  @spec identify_domain_indicators(String.t()) :: [atom()]
  def identify_domain_indicators(prompt) do
    domain_indicators()
    |> Enum.filter(fn {_domain, patterns} ->
      Enum.any?(patterns, &Regex.match?(&1, prompt))
    end)
    |> Enum.map(fn {domain, _patterns} -> domain end)
  end

  @doc """
  Assesses the urgency level based on prompt language and context.
  """
  @spec assess_urgency(EnhancementContext.t()) :: atom()
  def assess_urgency(context) do
    prompt = context.original_prompt
    indicators = urgency_indicators()
    
    high_matches = count_pattern_matches(indicators.high, prompt)
    medium_matches = count_pattern_matches(indicators.medium, prompt)
    low_matches = count_pattern_matches(indicators.low, prompt)
    
    cond do
      high_matches > 0 -> :high
      low_matches > 0 -> :low
      medium_matches > 0 -> :medium
      true -> :medium
    end
  end

  @doc """
  Determines collaboration needs based on context.
  """
  @spec determine_collaboration_needs(EnhancementContext.t()) :: atom()
  def determine_collaboration_needs(context) do
    user_context = context.user_context
    prompt = context.original_prompt
    
    cond do
      # Enterprise indicators
      String.contains?(String.downcase(prompt), "production") or
      String.contains?(String.downcase(prompt), "deployment") or
      Map.get(user_context, :enterprise_mode, false) ->
        :enterprise
      
      # Team indicators
      String.contains?(String.downcase(prompt), "team") or
      String.contains?(String.downcase(prompt), "review") or
      String.contains?(String.downcase(prompt), "collaborate") ->
        :team
      
      true ->
        :individual
    end
  end

  # Private helper functions

  defp count_pattern_matches(patterns, text) do
    Enum.count(patterns, &Regex.match?(&1, text))
  end
end