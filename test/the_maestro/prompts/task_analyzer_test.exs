defmodule TheMaestro.Prompts.TaskAnalyzerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.SystemInstructions.{TaskAnalyzer, TaskContext}

  describe "analyze_task_context/1" do
    test "identifies software engineering tasks" do
      context = %{
        user_request: "Fix the bug in the user authentication system",
        available_tools: [:read_file, :write_file, :execute_command],
        project_files: ["lib/auth.ex", "test/auth_test.exs"],
        current_directory: "/app/project"
      }

      task_context = TaskAnalyzer.analyze_task_context(context)

      assert %TaskContext{} = task_context
      assert task_context.primary_task_type == :software_engineering
      assert task_context.complexity_level in [:low, :moderate, :high]
      assert task_context.risk_level in [:low, :medium, :high, :critical]
    end

    test "identifies new application development tasks" do
      context = %{
        user_request: "Create a new React application for managing todos",
        available_tools: [:read_file, :write_file],
        project_files: [],
        current_directory: "/empty/project"
      }

      task_context = TaskAnalyzer.analyze_task_context(context)

      assert task_context.primary_task_type == :new_application
      assert task_context.complexity_level in [:moderate, :high]
    end

    test "identifies debugging tasks" do
      context = %{
        user_request: "Debug why the tests are failing in CI",
        available_tools: [:read_file, :execute_command],
        project_files: ["test/integration_test.exs", "mix.exs"],
        error_indicators: ["failing tests", "CI errors"]
      }

      task_context = TaskAnalyzer.analyze_task_context(context)

      assert task_context.primary_task_type == :debugging
      assert :testing in task_context.required_capabilities
    end

    test "identifies documentation tasks" do
      context = %{
        user_request: "Create comprehensive API documentation",
        available_tools: [:read_file, :write_file],
        project_files: ["lib/api.ex", "README.md"]
      }

      task_context = TaskAnalyzer.analyze_task_context(context)

      assert task_context.primary_task_type == :documentation
      assert task_context.collaboration_mode == :collaborative
    end
  end

  describe "determine_primary_task_type/1" do
    test "recognizes software engineering keywords" do
      contexts = [
        %{user_request: "Implement a new feature for user profiles"},
        %{user_request: "Refactor the database connection logic"},
        %{user_request: "Add unit tests for the payment system"},
        %{user_request: "Optimize the search algorithm performance"}
      ]

      for context <- contexts do
        task_type = TaskAnalyzer.determine_primary_task_type(context)
        assert task_type == :software_engineering
      end
    end

    test "recognizes new application keywords" do
      contexts = [
        %{user_request: "Create a new web application"},
        %{user_request: "Build a mobile app from scratch"},
        %{user_request: "Develop a new microservice"},
        %{user_request: "Bootstrap a React project"}
      ]

      for context <- contexts do
        task_type = TaskAnalyzer.determine_primary_task_type(context)
        assert task_type == :new_application
      end
    end

    test "recognizes debugging keywords" do
      contexts = [
        %{user_request: "Debug the memory leak issue"},
        %{user_request: "Fix the failing integration tests"},
        %{user_request: "Troubleshoot the deployment errors"},
        %{user_request: "Investigate the performance bottleneck"}
      ]

      for context <- contexts do
        task_type = TaskAnalyzer.determine_primary_task_type(context)
        assert task_type == :debugging
      end
    end

    test "defaults to generic for unrecognized patterns" do
      context = %{user_request: "Tell me about the weather"}

      task_type = TaskAnalyzer.determine_primary_task_type(context)
      assert task_type == :generic
    end
  end

  describe "assess_complexity_level/1" do
    test "assesses low complexity for simple tasks" do
      context = %{
        user_request: "Fix a typo in the README",
        available_tools: [:read_file, :write_file],
        project_files: ["README.md"],
        estimated_scope: :single_file
      }

      complexity = TaskAnalyzer.assess_complexity_level(context)
      assert complexity == :low
    end

    test "assesses moderate complexity for multi-file tasks" do
      context = %{
        user_request: "Add a new API endpoint with tests",
        available_tools: [:read_file, :write_file, :execute_command],
        project_files: ["lib/router.ex", "test/api_test.exs", "lib/controllers/"],
        estimated_scope: :multi_file
      }

      complexity = TaskAnalyzer.assess_complexity_level(context)
      assert complexity == :moderate
    end

    test "assesses high complexity for system-wide changes" do
      context = %{
        user_request: "Migrate the authentication system from sessions to JWT",
        available_tools: [:read_file, :write_file, :execute_command],
        project_files: ["lib/auth/", "lib/controllers/", "test/", "config/"],
        estimated_scope: :system_wide,
        architectural_changes: true
      }

      complexity = TaskAnalyzer.assess_complexity_level(context)
      assert complexity == :high
    end
  end

  describe "identify_required_capabilities/1" do
    test "identifies file operations capability" do
      context = %{
        user_request: "Update the configuration file",
        available_tools: [:read_file, :write_file]
      }

      capabilities = TaskAnalyzer.identify_required_capabilities(context)
      assert :file_operations in capabilities
    end

    test "identifies command execution capability" do
      context = %{
        user_request: "Run the test suite and fix any failures",
        available_tools: [:execute_command, :read_file, :write_file]
      }

      capabilities = TaskAnalyzer.identify_required_capabilities(context)
      assert :command_execution in capabilities
      assert :testing in capabilities
    end

    test "identifies security capability for sensitive operations" do
      context = %{
        user_request: "Update the authentication middleware",
        security_sensitive_keywords: ["authentication", "password", "token"]
      }

      capabilities = TaskAnalyzer.identify_required_capabilities(context)
      assert :security_analysis in capabilities
    end

    test "identifies performance capability for optimization tasks" do
      context = %{
        user_request: "Optimize the database queries for better performance",
        performance_keywords: ["optimize", "performance", "slow", "bottleneck"]
      }

      capabilities = TaskAnalyzer.identify_required_capabilities(context)
      assert :performance_analysis in capabilities
    end
  end

  describe "assess_time_sensitivity/1" do
    test "recognizes urgent indicators" do
      context = %{
        user_request: "URGENT: Fix the critical security vulnerability",
        urgency_keywords: ["urgent", "critical", "immediate"]
      }

      sensitivity = TaskAnalyzer.assess_time_sensitivity(context)
      assert sensitivity == :urgent
    end

    test "recognizes normal priority" do
      context = %{
        user_request: "Add a new feature for the next sprint"
      }

      sensitivity = TaskAnalyzer.assess_time_sensitivity(context)
      assert sensitivity == :normal
    end

    test "recognizes flexible timeline" do
      context = %{
        user_request: "Refactor the code when you have time",
        flexible_keywords: ["when you have time", "eventually", "nice to have"]
      }

      sensitivity = TaskAnalyzer.assess_time_sensitivity(context)
      assert sensitivity == :flexible
    end
  end

  describe "assess_risk_level/1" do
    test "assesses low risk for documentation tasks" do
      context = %{
        primary_task_type: :documentation,
        available_tools: [:read_file, :write_file],
        affects_production: false
      }

      risk = TaskAnalyzer.assess_risk_level(context)
      assert risk == :low
    end

    test "assesses medium risk for feature development" do
      context = %{
        primary_task_type: :software_engineering,
        available_tools: [:read_file, :write_file, :execute_command],
        affects_production: false,
        has_tests: true
      }

      risk = TaskAnalyzer.assess_risk_level(context)
      assert risk == :medium
    end

    test "assesses high risk for security-sensitive tasks" do
      context = %{
        primary_task_type: :software_engineering,
        security_sensitive: true,
        affects_production: true,
        user_request: "Update the authentication system"
      }

      risk = TaskAnalyzer.assess_risk_level(context)
      assert risk == :high
    end

    test "assesses critical risk for urgent security fixes" do
      context = %{
        primary_task_type: :debugging,
        security_sensitive: true,
        affects_production: true,
        urgency_level: :urgent,
        user_request: "Fix the critical security vulnerability in production"
      }

      risk = TaskAnalyzer.assess_risk_level(context)
      assert risk == :critical
    end
  end

  describe "determine_collaboration_mode/1" do
    test "determines autonomous mode for clear technical tasks" do
      context = %{
        user_request: "Implement the user registration endpoint with validation",
        task_clarity: :high,
        technical_complexity: :moderate
      }

      mode = TaskAnalyzer.determine_collaboration_mode(context)
      assert mode == :autonomous
    end

    test "determines collaborative mode for ambiguous tasks" do
      context = %{
        user_request: "Make the app better",
        task_clarity: :low,
        requires_clarification: true
      }

      mode = TaskAnalyzer.determine_collaboration_mode(context)
      assert mode == :collaborative
    end

    test "determines guided mode for learning scenarios" do
      context = %{
        user_request: "Show me how to implement OAuth authentication",
        learning_indicators: ["show me", "how to", "explain"],
        educational_intent: true
      }

      mode = TaskAnalyzer.determine_collaboration_mode(context)
      assert mode == :guided
    end
  end

  describe "extract_context_clues/1" do
    test "extracts file-related clues" do
      context = %{
        user_request: "Fix the bug in lib/auth.ex file",
        project_files: ["lib/auth.ex", "test/auth_test.exs"]
      }

      clues = TaskAnalyzer.extract_context_clues(context)

      assert "lib/auth.ex" in clues.mentioned_files
      assert :elixir in clues.programming_languages
      assert :bug_fix in clues.task_indicators
    end

    test "extracts technology stack clues" do
      context = %{
        user_request: "Add React components with TypeScript support",
        project_files: ["package.json", "tsconfig.json", "src/App.tsx"]
      }

      clues = TaskAnalyzer.extract_context_clues(context)

      assert :react in clues.technologies
      assert :typescript in clues.programming_languages
      assert :frontend in clues.domain_areas
    end

    test "extracts urgency and priority clues" do
      context = %{
        user_request: "CRITICAL: Production database connection is failing!"
      }

      clues = TaskAnalyzer.extract_context_clues(context)

      assert :urgent in clues.priority_indicators
      assert :production in clues.environment_indicators
      assert :critical in clues.severity_indicators
    end
  end
end
