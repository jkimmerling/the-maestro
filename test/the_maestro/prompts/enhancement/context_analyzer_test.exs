defmodule TheMaestro.Prompts.Enhancement.ContextAnalyzerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Enhancement.ContextAnalyzer
  alias TheMaestro.Prompts.Enhancement.Structs.{
    EnhancementContext,
    ContextAnalysis
  }

  describe "analyze_context/1" do
    test "analyzes software engineering prompt" do
      context = %EnhancementContext{
        original_prompt: "Fix the authentication bug in the user service module",
        user_context: %{
          project_type: "elixir_phoenix",
          working_directory: "/app/user_service"
        },
        enhancement_config: %{},
        pipeline_state: %{}
      }

      result = ContextAnalyzer.analyze_context(context)
      analysis = result.pipeline_state.context_analysis

      assert %ContextAnalysis{
        prompt_type: prompt_type,
        user_intent: user_intent,
        mentioned_entities: entities,
        implicit_requirements: requirements,
        complexity_level: complexity,
        domain_indicators: domains,
        urgency_level: urgency,
        collaboration_mode: collab
      } = analysis

      assert prompt_type == :software_engineering
      assert user_intent in [:bug_fix, :debugging, :troubleshooting]
      assert "authentication" in entities
      assert "user service" in entities or "user_service" in entities
      assert :code_analysis in requirements or :file_access in requirements
      assert complexity in [:low, :medium, :high]
      assert :software_development in domains
      assert urgency in [:low, :medium, :high]
      assert collab in [:individual, :team, :enterprise]
    end

    test "analyzes file operation prompt" do
      context = %EnhancementContext{
        original_prompt: "Read the config.json file and show me the database settings",
        user_context: %{working_directory: "/app/config"},
        enhancement_config: %{},
        pipeline_state: %{}
      }

      result = ContextAnalyzer.analyze_context(context)
      analysis = result.pipeline_state.context_analysis

      assert analysis.prompt_type == :file_operations
      assert analysis.user_intent in [:read_file, :information_seeking]
      assert "config.json" in analysis.mentioned_entities
      assert :file_access in analysis.implicit_requirements
      assert :file_system in analysis.domain_indicators
    end

    test "analyzes information seeking prompt" do
      context = %EnhancementContext{
        original_prompt: "How do I implement OAuth2 authentication in Phoenix?",
        user_context: %{},
        enhancement_config: %{},
        pipeline_state: %{}
      }

      result = ContextAnalyzer.analyze_context(context)
      analysis = result.pipeline_state.context_analysis

      assert analysis.prompt_type == :information_seeking
      assert analysis.user_intent == :learning
      assert "OAuth2" in analysis.mentioned_entities
      assert "Phoenix" in analysis.mentioned_entities
      assert :documentation in analysis.implicit_requirements
      assert :web_development in analysis.domain_indicators
    end

    test "handles complex multi-domain prompt" do
      context = %EnhancementContext{
        original_prompt: "Deploy the new user authentication service to production and monitor its performance",
        user_context: %{},
        enhancement_config: %{},
        pipeline_state: %{}
      }

      result = ContextAnalyzer.analyze_context(context)
      analysis = result.pipeline_state.context_analysis

      assert analysis.complexity_level == :high
      assert length(analysis.domain_indicators) > 1
      assert :deployment in analysis.domain_indicators
      assert :monitoring in analysis.domain_indicators
      assert :software_development in analysis.domain_indicators
    end

    test "assesses urgency from prompt language" do
      urgent_context = %EnhancementContext{
        original_prompt: "URGENT: The production server is down and users can't login!",
        user_context: %{},
        enhancement_config: %{},
        pipeline_state: %{}
      }

      result = ContextAnalyzer.analyze_context(urgent_context)
      assert result.pipeline_state.context_analysis.urgency_level == :high

      normal_context = %EnhancementContext{
        original_prompt: "When you have time, could you review the authentication code?",
        user_context: %{},
        enhancement_config: %{},
        pipeline_state: %{}
      }

      result = ContextAnalyzer.analyze_context(normal_context)
      assert result.pipeline_state.context_analysis.urgency_level in [:low, :medium]
    end
  end

  describe "classify_prompt_type/1" do
    test "correctly classifies software engineering prompts" do
      prompts = [
        "Fix the bug in user authentication",
        "Refactor the payment processing module",
        "Add unit tests for the API endpoints",
        "Optimize the database queries"
      ]

      for prompt <- prompts do
        assert ContextAnalyzer.classify_prompt_type(prompt) == :software_engineering
      end
    end

    test "correctly classifies file operation prompts" do
      prompts = [
        "Read the package.json file",
        "Create a new configuration file",
        "List all files in the src directory",
        "Delete the temporary files"
      ]

      for prompt <- prompts do
        assert ContextAnalyzer.classify_prompt_type(prompt) == :file_operations
      end
    end

    test "correctly classifies system operation prompts" do
      prompts = [
        "Install the required dependencies",
        "Start the development server",
        "Run the test suite",
        "Configure the environment variables"
      ]

      for prompt <- prompts do
        assert ContextAnalyzer.classify_prompt_type(prompt) == :system_operations
      end
    end

    test "correctly classifies information seeking prompts" do
      prompts = [
        "What is the difference between HTTP and HTTPS?",
        "How do I implement authentication in Phoenix?",
        "Explain the MVC pattern",
        "Show me examples of functional programming"
      ]

      for prompt <- prompts do
        assert ContextAnalyzer.classify_prompt_type(prompt) == :information_seeking
      end
    end

    test "defaults to general for unclassifiable prompts" do
      prompts = [
        "Hello",
        "Good morning",
        "Thanks for your help",
        "xyz abc def"
      ]

      for prompt <- prompts do
        assert ContextAnalyzer.classify_prompt_type(prompt) == :general
      end
    end
  end

  describe "extract_entities/1" do
    test "extracts file names and paths" do
      prompt = "Read the config.json file from the src/config directory"
      entities = ContextAnalyzer.extract_entities(prompt)

      assert "config.json" in entities
      assert "src/config" in entities or "src/config directory" in entities
    end

    test "extracts programming concepts" do
      prompt = "Implement OAuth2 authentication using JWT tokens"
      entities = ContextAnalyzer.extract_entities(prompt)

      assert "OAuth2" in entities
      assert "JWT" in entities or "JWT tokens" in entities
      assert "authentication" in entities
    end

    test "extracts service and module names" do
      prompt = "Fix the UserService module in the auth package"
      entities = ContextAnalyzer.extract_entities(prompt)

      assert "UserService" in entities
      assert "auth" in entities or "auth package" in entities
    end
  end

  describe "assess_prompt_complexity/1" do
    test "assesses simple prompts as low complexity" do
      simple_prompts = [
        "Hello",
        "Read file.txt",
        "What is Phoenix?"
      ]

      for prompt <- simple_prompts do
        assert ContextAnalyzer.assess_prompt_complexity(prompt) == :low
      end
    end

    test "assesses medium complexity prompts" do
      medium_prompts = [
        "Fix the authentication bug in the user service",
        "Create a new API endpoint for user registration",
        "Refactor the payment processing module"
      ]

      for prompt <- medium_prompts do
        assert ContextAnalyzer.assess_prompt_complexity(prompt) in [:medium, :high]
      end
    end

    test "assesses high complexity prompts" do
      high_prompts = [
        "Design a microservices architecture for a e-commerce platform with user authentication, payment processing, inventory management, and real-time notifications",
        "Implement a distributed caching system with Redis clustering, connection pooling, and automatic failover"
      ]

      for prompt <- high_prompts do
        assert ContextAnalyzer.assess_prompt_complexity(prompt) == :high
      end
    end
  end
end