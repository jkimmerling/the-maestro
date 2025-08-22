defmodule TheMaestro.Prompts.EngineeringTools.DocumentationGenerator do
  @moduledoc """
  Automatic documentation generator for prompt engineering projects.
  
  Provides automated generation of usage guides, API documentation,
  examples, and best practices for prompts and templates.
  """

  @doc """
  Generates comprehensive documentation for a prompt.
  
  ## Parameters
  - prompt: The prompt text to document
  - options: Documentation options including:
    - :format - Output format (:markdown, :html, :json)
    - :include_examples - Whether to include usage examples
    - :include_metadata - Whether to include technical metadata
    - :style - Documentation style (:concise, :detailed, :tutorial)
  
  ## Returns
  - {:ok, documentation} on success
  - {:error, reason} on failure
  """
  @spec generate_prompt_documentation(String.t(), map()) :: 
    {:ok, String.t()} | {:error, String.t()}
  def generate_prompt_documentation(prompt, options \\ %{}) do
    format = options[:format] || :markdown
    style = options[:style] || :detailed
    
    try do
      documentation = %{
        title: extract_prompt_title(prompt),
        description: generate_description(prompt),
        usage_instructions: generate_usage_instructions(prompt, style),
        parameters: extract_parameters(prompt),
        examples: if(options[:include_examples], do: generate_examples(prompt), else: []),
        metadata: if(options[:include_metadata], do: generate_metadata(prompt), else: %{}),
        best_practices: generate_best_practices(prompt),
        troubleshooting: generate_troubleshooting_guide(prompt),
        generated_at: DateTime.utc_now()
      }
      
      formatted_doc = format_documentation(documentation, format)
      {:ok, formatted_doc}
    rescue
      error -> {:error, "Documentation generation failed: #{inspect(error)}"}
    end
  end

  @doc """
  Creates API documentation for prompt templates.
  """
  @spec generate_template_api_docs(list(map()), map()) :: {:ok, String.t()} | {:error, String.t()}
  def generate_template_api_docs(templates, options \\ %{}) do
    format = options[:format] || :markdown
    
    try do
      api_docs = %{
        title: options[:title] || "Prompt Template API Documentation",
        version: options[:version] || "1.0.0",
        description: options[:description] || "Auto-generated API documentation for prompt templates",
        templates: Enum.map(templates, &document_template/1),
        endpoints: generate_api_endpoints(templates),
        authentication: options[:auth_docs] || %{},
        examples: generate_api_examples(templates),
        generated_at: DateTime.utc_now()
      }
      
      formatted_docs = format_api_documentation(api_docs, format)
      {:ok, formatted_docs}
    rescue
      error -> {:error, "API documentation generation failed: #{inspect(error)}"}
    end
  end

  @doc """
  Generates usage examples for prompts and templates.
  """
  @spec generate_usage_examples(String.t() | list(map()), map()) :: list(map())
  def generate_usage_examples(prompt_or_templates, options \\ %{}) do
    example_count = options[:count] || 3
    complexity_levels = options[:complexity] || [:beginner, :intermediate, :advanced]
    
    case prompt_or_templates do
      prompt when is_binary(prompt) ->
        generate_prompt_examples(prompt, example_count, complexity_levels)
        
      templates when is_list(templates) ->
        Enum.flat_map(templates, fn template ->
          generate_template_examples(template, div(example_count, length(templates)), complexity_levels)
        end)
        
      _ ->
        []
    end
  end

  @doc """
  Creates a comprehensive user guide.
  """
  @spec generate_user_guide(list(map()), map()) :: {:ok, String.t()} | {:error, String.t()}
  def generate_user_guide(prompts_and_templates, options \\ %{}) do
    format = options[:format] || :markdown
    
    try do
      guide = %{
        title: options[:title] || "Prompt Engineering User Guide",
        introduction: generate_introduction(options[:project_context]),
        getting_started: generate_getting_started_section(prompts_and_templates),
        core_concepts: generate_core_concepts_section(),
        prompt_library: document_prompt_library(prompts_and_templates),
        advanced_usage: generate_advanced_usage_section(prompts_and_templates),
        troubleshooting: generate_comprehensive_troubleshooting(),
        faqs: generate_faqs(prompts_and_templates),
        appendices: generate_appendices(prompts_and_templates),
        generated_at: DateTime.utc_now()
      }
      
      formatted_guide = format_user_guide(guide, format)
      {:ok, formatted_guide}
    rescue
      error -> {:error, "User guide generation failed: #{inspect(error)}"}
    end
  end

  @doc """
  Generates best practices documentation.
  """
  @spec generate_best_practices_guide(map()) :: String.t()
  def generate_best_practices_guide(context \\ %{}) do
    domain = context[:domain] || :general
    experience_level = context[:experience_level] || :intermediate
    
    practices = %{
      general_principles: get_general_best_practices(),
      domain_specific: get_domain_specific_practices(domain),
      experience_level: get_experience_level_practices(experience_level),
      common_pitfalls: get_common_pitfalls(),
      optimization_tips: get_optimization_tips(),
      quality_guidelines: get_quality_guidelines()
    }
    
    format_best_practices(practices)
  end

  @doc """
  Creates interactive tutorials for prompt engineering.
  """
  @spec generate_interactive_tutorial(String.t(), map()) :: map()
  def generate_interactive_tutorial(topic, options \\ %{}) do
    difficulty = options[:difficulty] || :beginner
    duration = options[:duration] || 30 # minutes
    
    %{
      tutorial_id: generate_tutorial_id(),
      title: "Interactive Tutorial: #{String.capitalize(topic)}",
      description: "Learn #{topic} through hands-on exercises and examples",
      difficulty: difficulty,
      estimated_duration: duration,
      learning_objectives: generate_learning_objectives(topic, difficulty),
      modules: generate_tutorial_modules(topic, difficulty),
      exercises: generate_interactive_exercises(topic, difficulty),
      assessments: generate_assessments(topic, difficulty),
      resources: generate_additional_resources(topic),
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Exports documentation in multiple formats.
  """
  @spec export_documentation(map(), list(atom())) :: map()
  def export_documentation(documentation, formats \\ [:markdown, :html, :pdf]) do
    exports = %{}
    
    Enum.reduce(formats, exports, fn format, acc ->
      case format_documentation(documentation, format) do
        {:ok, formatted} -> Map.put(acc, format, formatted)
        {:error, _} -> acc
      end
    end)
  end

  # Private helper functions

  defp extract_prompt_title(prompt) do
    # Extract title from first line or generate from content
    first_line = String.split(prompt, "\n") |> List.first() |> String.trim()
    
    if String.length(first_line) < 100 and String.contains?(first_line, ["Task", "Instruction", "Prompt"]) do
      String.replace(first_line, ~r/^#+\s*/, "") # Remove markdown headers
    else
      "Untitled Prompt"
    end
  end

  defp generate_description(prompt) do
    # Generate description based on prompt analysis
    analysis = analyze_prompt_purpose(prompt)
    
    case analysis.primary_purpose do
      :analysis -> "This prompt is designed for analyzing and evaluating content."
      :generation -> "This prompt generates new content based on specified criteria."
      :transformation -> "This prompt transforms input content into a different format or style."
      :question_answering -> "This prompt answers questions based on provided context."
      _ -> "This prompt performs various text processing tasks."
    end
  end

  defp generate_usage_instructions(_prompt, :concise) do
    "1. Provide the required input\n2. Execute the prompt\n3. Review the output"
  end

  defp generate_usage_instructions(prompt, :detailed) do
    parameters = extract_parameters(prompt)
    
    instructions = [
      "## Usage Instructions",
      "",
      "### Prerequisites",
      "- Ensure you have access to the prompt execution environment",
      "- Prepare your input data according to the specified format",
      "",
      "### Step-by-Step Guide",
      "1. **Prepare Input**: Format your input according to the requirements below",
      "2. **Set Parameters**: Configure any optional parameters (see Parameters section)",
      "3. **Execute**: Run the prompt with your prepared input",
      "4. **Validate Output**: Check the response against expected format and quality criteria",
      "",
      "### Parameters"
    ]
    
    parameter_docs = if length(parameters) > 0 do
      Enum.map(parameters, fn param ->
        "- **#{param.name}**: #{param.description} (#{param.type}, #{if param.required, do: "required", else: "optional"})"
      end)
    else
      ["- No configurable parameters detected"]
    end
    
    Enum.join(instructions ++ parameter_docs, "\n")
  end

  defp generate_usage_instructions(_prompt, :tutorial) do
    """
    ## Interactive Tutorial

    This section will walk you through using this prompt step by step.

    ### Learning Objectives
    By the end of this tutorial, you will be able to:
    - Understand the prompt's purpose and capabilities
    - Properly format input for optimal results
    - Interpret and validate the output
    - Troubleshoot common issues

    ### Tutorial Steps
    1. **Understanding the Prompt** - Learn what this prompt does
    2. **Preparing Your Input** - Format your data correctly
    3. **Running the Prompt** - Execute with confidence
    4. **Analyzing Results** - Validate and interpret output
    5. **Advanced Usage** - Tips and tricks for power users
    """
  end

  defp extract_parameters(prompt) do
    # Extract parameter placeholders like {{variable}} or {variable}
    parameter_matches = Regex.scan(~r/\{\{?([^}]+)\}?\}/, prompt)
    
    Enum.map(parameter_matches, fn [_full_match, param_name] ->
      %{
        name: String.trim(param_name),
        type: infer_parameter_type(param_name),
        required: true, # Default assumption
        description: generate_parameter_description(param_name),
        example_values: generate_parameter_examples(param_name)
      }
    end)
    |> Enum.uniq_by(& &1.name)
  end

  defp generate_examples(prompt) do
    [
      %{
        title: "Basic Usage Example",
        description: "A simple example demonstrating basic functionality",
        input: generate_example_input(prompt, :basic),
        expected_output: generate_example_output(prompt, :basic),
        notes: "This example shows the most common use case"
      },
      %{
        title: "Advanced Usage Example",
        description: "A complex example showing advanced features",
        input: generate_example_input(prompt, :advanced),
        expected_output: generate_example_output(prompt, :advanced),
        notes: "This example demonstrates more sophisticated usage patterns"
      }
    ]
  end

  defp generate_metadata(prompt) do
    %{
      estimated_tokens: estimate_token_count(prompt),
      complexity_score: calculate_complexity_score(prompt),
      categories: categorize_prompt(prompt),
      suggested_models: suggest_compatible_models(prompt),
      performance_notes: generate_performance_notes(prompt),
      version: "1.0",
      last_updated: DateTime.utc_now()
    }
  end

  defp generate_best_practices(prompt) do
    analysis = analyze_prompt_characteristics(prompt)
    
    practices = [
      "Always validate input format before processing",
      "Review output for completeness and accuracy",
      "Consider context limitations when providing input"
    ]
    
    # Add specific practices based on prompt analysis
    practices = if analysis.has_parameters do
      ["Ensure all required parameters are provided" | practices]
    else
      practices
    end
    
    practices = if analysis.complexity == :high do
      ["Break complex tasks into smaller steps for better results" | practices]
    else
      practices
    end
    
    practices
  end

  defp generate_troubleshooting_guide(_prompt) do
    common_issues = [
      %{
        issue: "Empty or incomplete output",
        causes: ["Input too brief", "Missing required parameters", "Context unclear"],
        solutions: ["Provide more detailed input", "Check parameter requirements", "Add clarifying context"]
      },
      %{
        issue: "Output format doesn't match expectations",
        causes: ["Ambiguous format instructions", "Conflicting requirements"],
        solutions: ["Clarify format requirements", "Provide explicit examples", "Simplify instructions"]
      },
      %{
        issue: "Inconsistent results",
        causes: ["Input variability", "Prompt ambiguity"],
        solutions: ["Standardize input format", "Add more specific constraints", "Use examples for clarity"]
      }
    ]
    
    %{
      common_issues: common_issues,
      debugging_steps: [
        "Check input format and completeness",
        "Verify all parameters are correctly set",
        "Compare with provided examples",
        "Simplify the request if getting unclear results"
      ],
      when_to_seek_help: [
        "Consistent failures with well-formatted input",
        "Unexpected behavior that doesn't match documentation",
        "Performance issues with standard usage"
      ]
    }
  end

  defp format_documentation(documentation, :markdown) do
    sections = [
      "# #{documentation.title}",
      "",
      "## Description",
      documentation.description,
      "",
      "## Usage Instructions", 
      documentation.usage_instructions,
      "",
      format_parameters_markdown(documentation.parameters),
      format_examples_markdown(documentation.examples),
      format_best_practices_markdown(documentation.best_practices),
      format_troubleshooting_markdown(documentation.troubleshooting),
      "",
      "*Generated at: #{documentation.generated_at}*"
    ]
    
    Enum.join(sections, "\n")
  end

  defp format_documentation(documentation, :html) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>#{documentation.title}</title>
        <meta charset="utf-8">
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; margin: 40px; }
            h1, h2, h3 { color: #333; }
            code { background: #f4f4f4; padding: 2px 4px; border-radius: 3px; }
            pre { background: #f4f4f4; padding: 10px; border-radius: 5px; }
            .example { border-left: 3px solid #007cba; padding-left: 10px; margin: 10px 0; }
        </style>
    </head>
    <body>
        <h1>#{documentation.title}</h1>
        <h2>Description</h2>
        <p>#{documentation.description}</p>
        <h2>Usage Instructions</h2>
        <pre>#{documentation.usage_instructions}</pre>
        #{format_examples_html(documentation.examples)}
        <hr>
        <small>Generated at: #{documentation.generated_at}</small>
    </body>
    </html>
    """
  end

  defp format_documentation(documentation, :json) do
    Jason.encode!(documentation, pretty: true)
  rescue
    _ -> Jason.encode!(Map.put(documentation, :error, "Failed to encode some fields"))
  end

  # Additional helper functions for comprehensive documentation generation

  defp analyze_prompt_purpose(prompt) do
    cond do
      String.contains?(prompt, ["analyze", "evaluate", "assess"]) -> %{primary_purpose: :analysis}
      String.contains?(prompt, ["generate", "create", "write"]) -> %{primary_purpose: :generation}
      String.contains?(prompt, ["transform", "convert", "rewrite"]) -> %{primary_purpose: :transformation}
      String.contains?(prompt, ["answer", "explain", "what", "why", "how"]) -> %{primary_purpose: :question_answering}
      true -> %{primary_purpose: :general}
    end
  end

  defp document_template(template) do
    %{
      id: template[:id] || generate_template_id(),
      name: template[:name] || "Untitled Template",
      description: template[:description] || "No description available",
      parameters: extract_parameters(template[:content] || ""),
      usage_examples: generate_template_examples(template, 2, [:beginner, :intermediate]),
      metadata: generate_template_metadata(template)
    }
  end

  defp generate_api_endpoints(_templates) do
    [
      %{
        endpoint: "/api/prompts/execute",
        method: "POST",
        description: "Execute a prompt with provided parameters",
        parameters: ["prompt_id", "input_data", "options"],
        response_format: "JSON with execution results"
      }
    ]
  end

  defp generate_api_examples(_templates) do
    [
      %{
        title: "Basic API Call",
        request: """
        POST /api/prompts/execute
        Content-Type: application/json
        
        {
          "prompt_id": "example-prompt",
          "input_data": "Sample input text",
          "options": {}
        }
        """,
        response: """
        {
          "status": "success",
          "result": "Generated output",
          "metadata": {
            "execution_time": 1.2,
            "tokens_used": 150
          }
        }
        """
      }
    ]
  end

  # Placeholder implementations for complex functions
  defp infer_parameter_type(param_name) do
    cond do
      String.contains?(param_name, ["count", "number", "amount"]) -> "number"
      String.contains?(param_name, ["list", "items", "array"]) -> "array"
      String.contains?(param_name, ["flag", "enable", "disable"]) -> "boolean"
      true -> "string"
    end
  end

  defp generate_parameter_description(param_name) do
    # Generate intelligent parameter descriptions based on parameter name patterns
    param_lower = String.downcase(param_name)
    
    cond do
      String.contains?(param_lower, ["context", "background", "info"]) ->
        "Contextual information that provides background and relevant details for the task."
        
      String.contains?(param_lower, ["input", "data", "content"]) ->
        "The main input data or content to be processed by this prompt."
        
      String.contains?(param_lower, ["format", "style", "type"]) ->
        "Specifies the desired output format, style, or type for the response."
        
      String.contains?(param_lower, ["language", "lang", "locale"]) ->
        "The target language or locale for the output (e.g., 'en', 'es', 'fr')."
        
      String.contains?(param_lower, ["level", "difficulty", "complexity"]) ->
        "Indicates the complexity level or difficulty of the task (e.g., 'beginner', 'advanced')."
        
      String.contains?(param_lower, ["tone", "mood", "voice"]) ->
        "Sets the tone, mood, or voice for the generated content (e.g., 'formal', 'casual', 'friendly')."
        
      String.contains?(param_lower, ["length", "size", "limit", "count"]) ->
        "Specifies the desired length, size, or count constraints for the output."
        
      String.contains?(param_lower, ["example", "sample", "demo"]) ->
        "Provides example data or samples to guide the generation process."
        
      String.contains?(param_lower, ["requirement", "constraint", "rule"]) ->
        "Defines specific requirements, constraints, or rules to follow during processing."
        
      String.contains?(param_lower, ["target", "audience", "user"]) ->
        "Describes the target audience or user for whom the content is intended."
        
      true ->
        "Parameter that controls #{param_name |> String.replace("_", " ") |> String.downcase()} behavior in the prompt execution."
    end
  end
  defp generate_parameter_examples(param_name) do
    # Generate intelligent examples based on parameter name
    param_lower = String.downcase(param_name)
    
    cond do
      String.contains?(param_lower, ["context", "background", "info"]) ->
        ["Previous conversation history", "User profile information", "Related document excerpts"]
        
      String.contains?(param_lower, ["input", "data", "content"]) ->
        ["User query text", "Document to analyze", "Raw data to process"]
        
      String.contains?(param_lower, ["format", "style", "type"]) ->
        ["json", "markdown", "bullet-points", "paragraph", "table"]
        
      String.contains?(param_lower, ["language", "lang", "locale"]) ->
        ["en", "es", "fr", "de", "ja", "zh"]
        
      String.contains?(param_lower, ["level", "difficulty", "complexity"]) ->
        ["beginner", "intermediate", "advanced", "expert"]
        
      String.contains?(param_lower, ["tone", "mood", "voice"]) ->
        ["professional", "casual", "friendly", "formal", "conversational"]
        
      String.contains?(param_lower, ["length", "size", "limit", "count"]) ->
        ["100", "500", "1000", "2-3 paragraphs", "5 bullet points"]
        
      String.contains?(param_lower, ["example", "sample", "demo"]) ->
        ["Sample case study", "Example scenario", "Reference template"]
        
      String.contains?(param_lower, ["requirement", "constraint", "rule"]) ->
        ["Must include citations", "Avoid technical jargon", "Use active voice"]
        
      String.contains?(param_lower, ["target", "audience", "user"]) ->
        ["general audience", "technical professionals", "students", "executives"]
        
      String.contains?(param_lower, ["name", "title"]) ->
        ["Document Title", "Project Name", "User Full Name"]
        
      String.contains?(param_lower, ["email", "contact"]) ->
        ["user@example.com", "support@company.com"]
        
      String.contains?(param_lower, ["url", "link", "website"]) ->
        ["https://example.com", "https://docs.company.com/api"]
        
      true ->
        ["value1", "value2", "value3"]
    end
  end
  defp generate_example_input(prompt, type) do
    # Generate realistic example input based on prompt content and type
    prompt_lower = String.downcase(prompt)
    
    case type do
      :simple ->
        cond do
          String.contains?(prompt_lower, ["analyze", "review", "assess"]) ->
            "Please analyze this quarterly sales report and identify key trends and insights."
            
          String.contains?(prompt_lower, ["write", "create", "generate"]) ->
            "Create a professional email response to a customer complaint about delayed delivery."
            
          String.contains?(prompt_lower, ["translate", "convert"]) ->
            "Translate the following text from English to Spanish: 'Thank you for your business.'"
            
          String.contains?(prompt_lower, ["summarize", "summary"]) ->
            "A 500-word article about renewable energy trends in 2024 and their impact on global markets."
            
          String.contains?(prompt_lower, ["code", "program", "function"]) ->
            "Write a Python function that calculates the factorial of a number using recursion."
            
          true ->
            "Sample input text for processing"
        end
        
      :complex ->
        cond do
          String.contains?(prompt_lower, ["analyze", "review", "assess"]) ->
            """
            {
              "document": "Q3 2024 Financial Report",
              "data": {
                "revenue": 2450000,
                "expenses": 1890000,
                "growth_rate": 12.3,
                "market_segment": "enterprise"
              },
              "context": "Year-over-year comparison needed"
            }
            """
            
          String.contains?(prompt_lower, ["write", "create", "generate"]) ->
            """
            {
              "task": "blog_post",
              "topic": "AI in Healthcare",
              "audience": "healthcare professionals",
              "length": "800-1000 words",
              "tone": "professional, informative"
            }
            """
            
          true ->
            """
            {
              "input_data": "Complex structured input",
              "parameters": {
                "format": "json",
                "detail_level": "comprehensive"
              }
            }
            """
        end
        
      _ ->
        # Default example input
        "Sample input for #{type} type processing"
    end
  end
  defp generate_example_output(prompt, type) do
    # Generate realistic expected output based on prompt content and type
    prompt_lower = String.downcase(prompt)
    
    case type do
      :simple ->
        cond do
          String.contains?(prompt_lower, ["analyze", "review", "assess"]) ->
            """
            ## Analysis Results
            
            **Key Findings:**
            - Revenue increased by 12.3% compared to Q2 2024
            - Customer acquisition costs decreased by 8%
            - Market expansion in the enterprise segment shows strong growth potential
            
            **Recommendations:**
            - Increase investment in enterprise sales team
            - Focus on customer retention strategies
            - Consider expanding to adjacent market segments
            """
            
          String.contains?(prompt_lower, ["write", "create", "generate"]) ->
            """
            Subject: Resolution of Your Recent Delivery Concern
            
            Dear [Customer Name],
            
            Thank you for bringing your delivery concern to our attention. We sincerely apologize for the delay in your recent order.
            
            We have investigated the issue and taken the following steps to resolve it:
            - Expedited shipping at no cost to you
            - Applied a 15% discount to your next order
            - Updated our logistics processes to prevent similar delays
            
            Your satisfaction is our priority, and we appreciate your patience.
            
            Best regards,
            Customer Service Team
            """
            
          String.contains?(prompt_lower, ["translate", "convert"]) ->
            "Gracias por su negocio."
            
          String.contains?(prompt_lower, ["summarize", "summary"]) ->
            """
            ## Summary: Renewable Energy Trends 2024
            
            **Key Points:**
            - Solar and wind energy adoption accelerated by 25% globally
            - Investment in renewable infrastructure reached $1.2 trillion
            - Major corporations committed to 100% renewable energy by 2030
            - Energy storage technology improvements reduced costs by 15%
            
            **Impact:** These trends indicate a fundamental shift toward sustainable energy sources, with significant implications for global energy markets and climate goals.
            """
            
          String.contains?(prompt_lower, ["code", "program", "function"]) ->
            """
            ```python
            def factorial(n):
                \"\"\"Calculate factorial using recursion.\"\"\"
                if n < 0:
                    raise ValueError("Factorial is not defined for negative numbers")
                elif n == 0 or n == 1:
                    return 1
                else:
                    return n * factorial(n - 1)
            
            # Example usage:
            # result = factorial(5)  # Returns 120
            ```
            """
            
          true ->
            "Processed output based on the input provided"
        end
        
      :complex ->
        cond do
          String.contains?(prompt_lower, ["analyze", "review", "assess"]) ->
            """
            {
              "analysis_summary": {
                "overall_performance": "strong",
                "confidence_score": 0.87,
                "key_metrics": {
                  "profitability": {
                    "value": 0.228,
                    "trend": "increasing",
                    "benchmark_comparison": "above_average"
                  },
                  "growth_rate": {
                    "value": 0.123,
                    "trend": "stable",
                    "projected_6_months": 0.145
                  }
                }
              },
              "recommendations": [
                {
                  "priority": "high",
                  "action": "Expand enterprise sales team",
                  "expected_impact": "15-20% revenue increase",
                  "timeline": "Q1 2025"
                }
              ],
              "risk_factors": [
                {
                  "factor": "Market saturation",
                  "probability": 0.3,
                  "mitigation": "Diversify into adjacent markets"
                }
              ]
            }
            """
            
          String.contains?(prompt_lower, ["write", "create", "generate"]) ->
            """
            {
              "content": {
                "title": "The Future of AI in Healthcare: Transforming Patient Care",
                "sections": [
                  {
                    "heading": "Introduction",
                    "content": "Artificial Intelligence is revolutionizing healthcare delivery..."
                  },
                  {
                    "heading": "Key Applications",
                    "content": "1. Diagnostic imaging and pattern recognition..."
                  }
                ],
                "word_count": 847,
                "reading_time": "3-4 minutes"
              },
              "metadata": {
                "target_audience": "healthcare_professionals",
                "tone_analysis": "professional",
                "key_topics": ["AI", "healthcare", "patient care", "technology"]
              }
            }
            """
            
          true ->
            """
            {
              "result": "Comprehensive processed output",
              "confidence": 0.92,
              "processing_time": "1.2s",
              "metadata": {
                "format": "structured",
                "detail_level": "comprehensive"
              }
            }
            """
        end
        
      _ ->
        "Expected output for #{type} type processing"
    end
  end
  defp estimate_token_count(text), do: div(String.length(text), 4)
  defp calculate_complexity_score(prompt) do
    # Calculate complexity score based on multiple factors
    length_score = calculate_length_complexity(prompt)
    structure_score = calculate_structure_complexity(prompt)
    parameter_score = calculate_parameter_complexity(prompt)
    instruction_score = calculate_instruction_complexity(prompt)
    
    # Weight the different complexity factors
    total_score = (length_score * 0.2) + (structure_score * 0.3) + 
                  (parameter_score * 0.3) + (instruction_score * 0.2)
    
    # Normalize to 0-1 range
    min(max(total_score, 0.0), 1.0)
  end
  
  defp calculate_length_complexity(prompt) do
    # Complexity increases with length, but with diminishing returns
    word_count = prompt |> String.split() |> length()
    
    cond do
      word_count < 20 -> 0.1
      word_count < 50 -> 0.3
      word_count < 100 -> 0.5
      word_count < 200 -> 0.7
      true -> 0.9
    end
  end
  
  defp calculate_structure_complexity(prompt) do
    # Analyze structural complexity indicators
    structure_indicators = [
      {~r/\{\{.*?\}\}/, 0.15},  # Template variables
      {~r/\[.*?\]/, 0.1},       # Brackets/options
      {~r/\d+\./, 0.1},         # Numbered lists
      {~r/\*.*/, 0.05},         # Bullet points
      {~r/```.*?```/s, 0.2},    # Code blocks
      {~r/#+ /, 0.1},           # Markdown headers
      {~r/\|.*?\|/, 0.15}       # Tables
    ]
    
    Enum.reduce(structure_indicators, 0.0, fn {pattern, weight}, acc ->
      matches = Regex.scan(pattern, prompt) |> length()
      acc + (matches * weight)
    end)
  end
  
  defp calculate_parameter_complexity(prompt) do
    # Count and analyze template parameters
    parameters = Regex.scan(~r/\{\{(.*?)\}\}/, prompt)
    param_count = length(parameters)
    
    # Additional complexity for nested or conditional parameters
    nested_params = Enum.count(parameters, fn [_, param] ->
      String.contains?(param, ["if", "unless", "case", "when"])
    end)
    
    base_complexity = min(param_count * 0.1, 0.5)
    nested_complexity = nested_params * 0.2
    
    base_complexity + nested_complexity
  end
  
  defp calculate_instruction_complexity(prompt) do
    # Analyze instruction complexity keywords
    complexity_keywords = [
      # High complexity
      {"analyze", 0.15}, {"evaluate", 0.15}, {"compare", 0.15}, {"synthesize", 0.2},
      {"optimize", 0.15}, {"troubleshoot", 0.15}, {"design", 0.15}, {"architect", 0.2},
      
      # Medium complexity
      {"create", 0.1}, {"generate", 0.1}, {"transform", 0.1}, {"convert", 0.1},
      {"categorize", 0.1}, {"classify", 0.1}, {"organize", 0.1}, {"structure", 0.1},
      
      # Lower complexity
      {"list", 0.05}, {"describe", 0.05}, {"explain", 0.08}, {"summarize", 0.08},
      {"translate", 0.05}, {"format", 0.05}
    ]
    
    prompt_lower = String.downcase(prompt)
    
    complexity_keywords
    |> Enum.reduce(0.0, fn {keyword, weight}, acc ->
      if String.contains?(prompt_lower, keyword) do
        acc + weight
      else
        acc
      end
    end)
    |> min(0.8)  # Cap at 0.8 to leave room for other factors
  end
  defp categorize_prompt(prompt) do
    # Intelligently categorize prompts based on content analysis
    prompt_lower = String.downcase(prompt)
    categories = []
    
    # Domain-specific categories
    categories = if String.contains?(prompt_lower, ["code", "program", "function", "algorithm", "debug", "software", "api"]) do
      ["programming", "software-development" | categories]
    else
      categories
    end
    
    categories = if String.contains?(prompt_lower, ["analyze", "data", "statistics", "metrics", "report", "insights"]) do
      ["data-analysis", "analytics" | categories]
    else
      categories
    end
    
    categories = if String.contains?(prompt_lower, ["write", "blog", "article", "content", "copy", "marketing"]) do
      ["content-creation", "writing" | categories]
    else
      categories
    end
    
    categories = if String.contains?(prompt_lower, ["translate", "language", "localization", "multilingual"]) do
      ["translation", "localization" | categories]
    else
      categories
    end
    
    categories = if String.contains?(prompt_lower, ["customer", "support", "service", "help", "assistance"]) do
      ["customer-service", "support" | categories]
    else
      categories
    end
    
    categories = if String.contains?(prompt_lower, ["email", "message", "communication", "correspondence"]) do
      ["communication", "messaging" | categories]
    else
      categories
    end
    
    categories = if String.contains?(prompt_lower, ["creative", "story", "narrative", "fiction", "imaginative"]) do
      ["creative-writing", "storytelling" | categories]
    else
      categories
    end
    
    categories = if String.contains?(prompt_lower, ["technical", "documentation", "manual", "guide", "instructions"]) do
      ["technical-writing", "documentation" | categories]
    else
      categories
    end
    
    categories = if String.contains?(prompt_lower, ["education", "teach", "explain", "learn", "tutorial"]) do
      ["educational", "instructional" | categories]
    else
      categories
    end
    
    categories = if String.contains?(prompt_lower, ["research", "academic", "scholarly", "paper", "study"]) do
      ["research", "academic" | categories]
    else
      categories
    end
    
    # Task-type categories
    categories = if String.contains?(prompt_lower, ["summarize", "summary", "brief", "overview"]) do
      ["summarization", "text-processing" | categories]
    else
      categories
    end
    
    categories = if String.contains?(prompt_lower, ["classify", "categorize", "tag", "organize"]) do
      ["classification", "organization" | categories]
    else
      categories
    end
    
    categories = if String.contains?(prompt_lower, ["extract", "parse", "find", "identify"]) do
      ["information-extraction", "parsing" | categories]
    else
      categories
    end
    
    # Complexity-based categories
    complexity_score = calculate_complexity_score(prompt)
    categories = cond do
      complexity_score > 0.7 -> ["complex", "advanced" | categories]
      complexity_score > 0.4 -> ["intermediate" | categories]
      true -> ["simple", "basic" | categories]
    end
    
    # Template parameter categories
    categories = if String.contains?(prompt, "{{") do
      ["templated", "parametrized" | categories]
    else
      categories
    end
    
    # Return unique categories, or default if none found
    case Enum.uniq(categories) do
      [] -> ["general", "text-processing"]
      unique_categories -> Enum.reverse(unique_categories) # Most specific first
    end
  end
  defp suggest_compatible_models(prompt) do
    # Suggest AI models based on prompt characteristics and requirements
    prompt_lower = String.downcase(prompt)
    categories = categorize_prompt(prompt)
    complexity_score = calculate_complexity_score(prompt)
    
    models = []
    
    # Base models suitable for most tasks
    models = ["gpt-4", "claude-3-sonnet", "gpt-3.5-turbo" | models]
    
    # Add specialized models based on content
    models = cond do
      # Complex analytical tasks
      complexity_score > 0.7 and String.contains?(prompt_lower, ["analyze", "complex", "detailed", "comprehensive"]) ->
        ["gpt-4-turbo", "claude-3-opus" | models]
        
      # Programming and code tasks
      Enum.any?(categories, &(&1 in ["programming", "software-development"])) ->
        ["gpt-4-turbo", "claude-3-sonnet", "codex", "github-copilot-chat" | models]
        
      # Creative writing tasks
      Enum.any?(categories, &(&1 in ["creative-writing", "storytelling", "content-creation"])) ->
        ["claude-3-opus", "gpt-4", "claude-3-sonnet" | models]
        
      # Data analysis and research
      Enum.any?(categories, &(&1 in ["data-analysis", "research", "analytics"])) ->
        ["gpt-4-turbo", "claude-3-opus", "gpt-4" | models]
        
      # Translation and multilingual
      Enum.any?(categories, &(&1 in ["translation", "localization"])) ->
        ["gpt-4", "claude-3-sonnet", "google-translate-api" | models]
        
      # Simple text processing
      Enum.any?(categories, &(&1 in ["simple", "basic", "summarization"])) ->
        ["gpt-3.5-turbo", "claude-3-haiku", "claude-3-sonnet" | models]
        
      true ->
        models
    end
    
    # Add cost-effective alternatives based on complexity
    models = if complexity_score < 0.4 do
      ["claude-3-haiku", "gpt-3.5-turbo" | models]
    else
      models
    end
    
    # Return unique suggestions with reasoning
    unique_models = Enum.uniq(models)
    
    # Limit to top 5 suggestions
    Enum.take(unique_models, 5)
  end
  defp generate_performance_notes(_prompt), do: "Standard performance expected"
  defp analyze_prompt_characteristics(prompt) do
    # Comprehensive analysis of prompt characteristics
    parameters = Regex.scan(~r/\{\{(.*?)\}\}/, prompt) |> Enum.map(fn [_, param] -> String.trim(param) end)
    complexity_score = calculate_complexity_score(prompt)
    categories = categorize_prompt(prompt)
    word_count = prompt |> String.split() |> length()
    
    complexity_level = cond do
      complexity_score > 0.7 -> :high
      complexity_score > 0.4 -> :medium
      true -> :low
    end
    
    # Analyze structural features
    has_code_blocks = String.contains?(prompt, ["```", "```"])
    has_lists = String.contains?(prompt, ["\n*", "\n-", "\n1.", "\n2."])
    has_headers = String.contains?(prompt, ["#", "##", "###"])
    has_tables = String.contains?(prompt, ["|"])
    
    # Analyze instruction patterns
    instruction_count = prompt
    |> String.downcase()
    |> then(fn text ->
      ["please", "create", "write", "analyze", "generate", "explain", "describe", 
       "summarize", "classify", "extract", "transform", "convert"]
      |> Enum.count(&String.contains?(text, &1))
    end)
    
    # Determine primary task type
    primary_task = determine_primary_task_type(prompt)
    
    # Calculate estimated processing requirements
    estimated_tokens = estimate_token_count(prompt)
    estimated_processing_time = estimate_processing_time(complexity_score, word_count)
    
    %{
      has_parameters: length(parameters) > 0,
      parameter_count: length(parameters),
      parameter_names: parameters,
      complexity: complexity_level,
      complexity_score: complexity_score,
      categories: categories,
      primary_category: List.first(categories) || "general",
      word_count: word_count,
      estimated_tokens: estimated_tokens,
      estimated_processing_time: estimated_processing_time,
      instruction_count: instruction_count,
      primary_task: primary_task,
      structural_features: %{
        has_code_blocks: has_code_blocks,
        has_lists: has_lists,
        has_headers: has_headers,
        has_tables: has_tables
      },
      readability: analyze_readability(prompt),
      suggested_models: suggest_compatible_models(prompt)
    }
  end
  
  defp determine_primary_task_type(prompt) do
    prompt_lower = String.downcase(prompt)
    
    cond do
      String.contains?(prompt_lower, ["analyze", "analysis", "examine", "evaluate", "assess"]) -> :analysis
      String.contains?(prompt_lower, ["write", "create", "generate", "compose", "draft"]) -> :generation
      String.contains?(prompt_lower, ["summarize", "summary", "brief", "condense"]) -> :summarization
      String.contains?(prompt_lower, ["translate", "convert", "transform"]) -> :transformation
      String.contains?(prompt_lower, ["classify", "categorize", "organize", "sort"]) -> :classification
      String.contains?(prompt_lower, ["extract", "find", "identify", "locate", "parse"]) -> :extraction
      String.contains?(prompt_lower, ["explain", "describe", "clarify", "elaborate"]) -> :explanation
      String.contains?(prompt_lower, ["compare", "contrast", "versus", "difference"]) -> :comparison
      String.contains?(prompt_lower, ["optimize", "improve", "enhance", "refine"]) -> :optimization
      String.contains?(prompt_lower, ["debug", "troubleshoot", "fix", "solve"]) -> :debugging
      true -> :general
    end
  end
  
  defp analyze_readability(prompt) do
    sentences = String.split(prompt, ~r/[.!?]+/) |> Enum.reject(&(&1 == ""))
    words = String.split(prompt) |> length()
    sentence_count = length(sentences)
    
    if sentence_count > 0 do
      avg_sentence_length = words / sentence_count
      
      readability_level = cond do
        avg_sentence_length > 20 -> :complex
        avg_sentence_length > 15 -> :moderate
        avg_sentence_length > 10 -> :simple
        true -> :very_simple
      end
      
      %{
        sentence_count: sentence_count,
        average_sentence_length: avg_sentence_length,
        readability_level: readability_level
      }
    else
      %{
        sentence_count: 0,
        average_sentence_length: 0,
        readability_level: :unknown
      }
    end
  end
  
  defp estimate_processing_time(complexity_score, word_count) do
    # Estimate processing time in seconds based on complexity and length
    base_time = word_count * 0.05  # Base time per word
    complexity_multiplier = 1 + complexity_score  # 1.0 to 2.0
    
    estimated_seconds = base_time * complexity_multiplier
    
    cond do
      estimated_seconds < 5 -> "< 5 seconds"
      estimated_seconds < 15 -> "5-15 seconds"
      estimated_seconds < 30 -> "15-30 seconds"
      estimated_seconds < 60 -> "30-60 seconds"
      true -> "> 1 minute"
    end
  end
  defp format_parameters_markdown(_params), do: "## Parameters\n\nNo parameters detected."
  defp format_examples_markdown(_examples), do: "## Examples\n\nNo examples available."
  defp format_best_practices_markdown(practices), do: "## Best Practices\n\n" <> Enum.join(practices, "\n")
  defp format_troubleshooting_markdown(_guide), do: "## Troubleshooting\n\nSee common issues section."
  defp format_examples_html(_examples), do: "<h2>Examples</h2><p>No examples available.</p>"
  defp generate_tutorial_id, do: "tutorial_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  defp generate_template_id, do: "template_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  defp generate_template_metadata(_template), do: %{}
  defp generate_prompt_examples(_prompt, _count, _levels), do: []
  defp generate_template_examples(_template, _count, _levels), do: []
  defp format_api_documentation(docs, :markdown), do: "# API Documentation\n\n" <> docs.description
  defp format_api_documentation(_docs, :html), do: "<html><body><h1>API Documentation</h1></body></html>"
  defp format_api_documentation(docs, _format), do: Jason.encode!(docs)
  defp generate_introduction(_context), do: "Welcome to the prompt engineering user guide."
  defp generate_getting_started_section(_items), do: "Getting started with prompt engineering."
  defp generate_core_concepts_section(), do: "Core concepts and terminology."
  defp document_prompt_library(_items), do: "Comprehensive prompt library documentation."
  defp generate_advanced_usage_section(_items), do: "Advanced usage patterns and techniques."
  defp generate_comprehensive_troubleshooting(), do: "Comprehensive troubleshooting guide."
  defp generate_faqs(_items), do: "Frequently asked questions and answers."
  defp generate_appendices(_items), do: "Additional resources and references."
  defp format_user_guide(guide, :markdown), do: "# #{guide.title}\n\n" <> guide.introduction
  defp format_user_guide(guide, _format), do: Jason.encode!(guide)
  defp get_general_best_practices(), do: ["Be specific", "Provide context", "Use examples"]
  defp get_domain_specific_practices(_domain), do: ["Domain-specific best practices"]
  defp get_experience_level_practices(_level), do: ["Experience-appropriate guidelines"]
  defp get_common_pitfalls(), do: ["Avoid vague language", "Don't overcomplicateOvercomplicate"]
  defp get_optimization_tips(), do: ["Optimize for clarity", "Test variations"]
  defp get_quality_guidelines(), do: ["Maintain consistency", "Validate outputs"]
  defp format_best_practices(practices), do: Jason.encode!(practices, pretty: true)
  defp generate_learning_objectives(_topic, _difficulty), do: []
  defp generate_tutorial_modules(_topic, _difficulty), do: []
  defp generate_interactive_exercises(_topic, _difficulty), do: []
  defp generate_assessments(_topic, _difficulty), do: []
  defp generate_additional_resources(_topic), do: []
end