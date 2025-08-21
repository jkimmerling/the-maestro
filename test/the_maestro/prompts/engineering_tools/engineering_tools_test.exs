defmodule TheMaestro.Prompts.EngineeringToolsTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.EngineeringTools
  alias TheMaestro.Prompts.EngineeringTools.{
    EngineeringEnvironment,
    PromptWorkspace,
    ToolPalette
  }

  describe "initialize_engineering_environment/1" do
    test "initializes comprehensive engineering environment" do
      user_context = %{
        user_id: "engineer_123",
        skill_level: :advanced,
        preferred_tools: [:interactive_builder, :testing_framework, :performance_analyzer],
        project_context: %{
          type: :software_engineering,
          domain: :web_development,
          team_size: 5
        },
        collaboration_preferences: %{
          real_time_sync: true,
          review_workflow: :peer_review,
          approval_process: :lead_approval
        }
      }

      environment = EngineeringTools.initialize_engineering_environment(user_context)

      assert %EngineeringEnvironment{} = environment
      assert environment.user_profile.user_id == "engineer_123"
      assert environment.user_profile.skill_level == :advanced
      
      # Should initialize all required components
      assert Map.has_key?(environment, :workspace)
      assert Map.has_key?(environment, :tool_palette)
      assert Map.has_key?(environment, :project_context)
      assert Map.has_key?(environment, :collaboration_session)
      assert Map.has_key?(environment, :version_control)
      assert Map.has_key?(environment, :performance_baseline)
    end

    test "loads user engineering profile with preferences" do
      user_context = %{
        user_id: "engineer_456",
        skill_level: :intermediate,
        preferred_tools: [:template_manager, :debugging_tools],
        usage_history: %{
          most_used_templates: ["code_review", "bug_analysis"],
          average_session_duration: 45,
          preferred_analysis_depth: :detailed
        }
      }

      environment = EngineeringTools.initialize_engineering_environment(user_context)

      user_profile = environment.user_profile
      
      assert user_profile.skill_level == :intermediate
      assert user_profile.preferred_tools == [:template_manager, :debugging_tools]
      assert Map.has_key?(user_profile, :usage_history)
      assert user_profile.usage_history.most_used_templates == ["code_review", "bug_analysis"]
      
      # Should have personalized recommendations
      assert Map.has_key?(user_profile, :recommended_workflows)
      assert is_list(user_profile.recommended_workflows)
    end

    test "initializes prompt workspace with project context" do
      user_context = %{
        user_id: "engineer_789",
        project_context: %{
          project_name: "E-commerce Platform",
          domain: :e_commerce,
          tech_stack: ["elixir", "phoenix", "postgresql"],
          team_context: %{
            size: 8,
            experience_distribution: %{senior: 3, mid: 4, junior: 1},
            collaboration_style: :async_review
          }
        }
      }

      environment = EngineeringTools.initialize_engineering_environment(user_context)

      workspace = environment.workspace
      
      assert %PromptWorkspace{} = workspace
      assert workspace.project_name == "E-commerce Platform"
      assert workspace.domain == :e_commerce
      assert Enum.member?(workspace.tech_stack, "elixir")
      assert Enum.member?(workspace.tech_stack, "phoenix")
      
      # Should load domain-specific templates and tools
      assert Map.has_key?(workspace, :domain_templates)
      assert Map.has_key?(workspace, :tech_stack_tools)
      assert length(workspace.domain_templates) > 0
    end

    test "loads available tools from all categories" do
      user_context = %{user_id: "engineer_000"}

      environment = EngineeringTools.initialize_engineering_environment(user_context)

      tool_palette = environment.tool_palette
      
      assert %ToolPalette{} = tool_palette
      
      # Should include all tool categories
      expected_categories = [
        :prompt_crafting,
        :template_management,
        :testing_framework,
        :optimization_tools,
        :analysis_dashboard,
        :collaboration_tools,
        :versioning_system,
        :experimentation,
        :debugging_tools,
        :documentation_gen
      ]

      loaded_categories = Map.keys(tool_palette.available_tools)
      assert Enum.all?(expected_categories, fn category ->
        Enum.member?(loaded_categories, category)
      end)
      
      # Each category should have tools
      Enum.each(expected_categories, fn category ->
        tools = Map.get(tool_palette.available_tools, category, [])
        assert length(tools) > 0
      end)
    end

    test "sets up collaboration session with team members" do
      user_context = %{
        user_id: "engineer_lead",
        collaboration_context: %{
          team_members: ["engineer_1", "engineer_2", "engineer_3"],
          project_id: "proj_123",
          collaboration_mode: :real_time,
          permissions: %{
            can_edit: true,
            can_approve: true,
            can_delete: false
          }
        }
      }

      environment = EngineeringTools.initialize_engineering_environment(user_context)

      collaboration_session = environment.collaboration_session
      
      assert Map.has_key?(collaboration_session, :session_id)
      assert Map.has_key?(collaboration_session, :participants)
      assert Map.has_key?(collaboration_session, :collaboration_mode)
      assert Map.has_key?(collaboration_session, :permissions)
      
      assert length(collaboration_session.participants) == 4  # Including the lead
      assert collaboration_session.collaboration_mode == :real_time
      assert collaboration_session.permissions.can_edit == true
    end

    test "initializes prompt versioning system" do
      user_context = %{
        user_id: "engineer_version",
        version_control_preferences: %{
          auto_save_interval: 300,  # 5 minutes
          keep_history_days: 30,
          branch_strategy: :feature_branch,
          merge_strategy: :squash_and_merge
        }
      }

      environment = EngineeringTools.initialize_engineering_environment(user_context)

      version_control = environment.version_control
      
      assert Map.has_key?(version_control, :repository_config)
      assert Map.has_key?(version_control, :auto_save_settings)
      assert Map.has_key?(version_control, :history_retention)
      assert Map.has_key?(version_control, :branching_config)
      
      assert version_control.auto_save_settings.interval == 300
      assert version_control.history_retention.days == 30
      assert version_control.branching_config.strategy == :feature_branch
    end

    test "loads performance baselines for comparison" do
      user_context = %{
        user_id: "engineer_perf",
        project_context: %{
          domain: :data_analysis,
          expected_performance: %{
            response_time_target: 2000,
            quality_score_target: 0.85,
            success_rate_target: 0.95
          }
        }
      }

      environment = EngineeringTools.initialize_engineering_environment(user_context)

      performance_baseline = environment.performance_baseline
      
      assert Map.has_key?(performance_baseline, :response_time_targets)
      assert Map.has_key?(performance_baseline, :quality_targets)
      assert Map.has_key?(performance_baseline, :success_rate_targets)
      assert Map.has_key?(performance_baseline, :benchmark_prompts)
      
      assert performance_baseline.response_time_targets.target == 2000
      assert performance_baseline.quality_targets.target == 0.85
      assert performance_baseline.success_rate_targets.target == 0.95
      
      # Should have domain-specific benchmark prompts
      assert is_list(performance_baseline.benchmark_prompts)
      assert length(performance_baseline.benchmark_prompts) > 0
    end

    test "handles minimal user context gracefully" do
      minimal_context = %{user_id: "minimal_user"}

      environment = EngineeringTools.initialize_engineering_environment(minimal_context)

      # Should still initialize all required components with defaults
      assert %EngineeringEnvironment{} = environment
      assert environment.user_profile.user_id == "minimal_user"
      assert environment.user_profile.skill_level == :intermediate  # Default
      assert Map.has_key?(environment, :workspace)
      assert Map.has_key?(environment, :tool_palette)
      
      # Should use default project context
      assert environment.project_context.domain == :general
      assert environment.project_context.type == :general_purpose
    end

    test "adapts environment based on skill level" do
      beginner_context = %{user_id: "beginner", skill_level: :beginner}
      advanced_context = %{user_id: "advanced", skill_level: :advanced}

      beginner_env = EngineeringTools.initialize_engineering_environment(beginner_context)
      advanced_env = EngineeringTools.initialize_engineering_environment(advanced_context)

      # Beginner should have more guidance and simpler tools
      beginner_tools = Map.keys(beginner_env.tool_palette.available_tools)
      advanced_tools = Map.keys(advanced_env.tool_palette.available_tools)
      
      # Advanced users should have access to all tools
      assert length(advanced_tools) >= length(beginner_tools)
      
      # Beginner should have more guided workflows
      assert length(beginner_env.user_profile.guided_workflows) > 
             length(advanced_env.user_profile.guided_workflows)
             
      # Advanced should have more automation options
      assert advanced_env.tool_palette.automation_level == :high
      assert beginner_env.tool_palette.automation_level == :low
    end
  end

  describe "tool categories and availability" do
    test "provides all required tool categories" do
      categories = EngineeringTools.get_available_tool_categories()

      expected_categories = [
        :prompt_crafting,
        :template_management,
        :testing_framework,
        :optimization_tools,
        :analysis_dashboard,
        :collaboration_tools,
        :versioning_system,
        :experimentation,
        :debugging_tools,
        :documentation_gen
      ]

      assert Enum.all?(expected_categories, fn category ->
        Enum.member?(categories, category)
      end)
    end

    test "loads tools for specific category" do
      prompt_crafting_tools = EngineeringTools.get_tools_by_category(:prompt_crafting)

      assert is_list(prompt_crafting_tools)
      assert length(prompt_crafting_tools) > 0
      
      # Should include interactive builder
      interactive_builder = Enum.find(prompt_crafting_tools, fn tool ->
        tool.name == "Interactive Prompt Builder"
      end)
      assert interactive_builder != nil
      assert interactive_builder.category == :prompt_crafting
      assert Map.has_key?(interactive_builder, :description)
      assert Map.has_key?(interactive_builder, :capabilities)
    end

    test "filters tools by user skill level" do
      beginner_tools = EngineeringTools.get_tools_for_skill_level(:beginner)
      advanced_tools = EngineeringTools.get_tools_for_skill_level(:advanced)

      # Advanced users should have access to more tools
      assert length(advanced_tools) > length(beginner_tools)
      
      # All beginner tools should be available to advanced users
      beginner_tool_names = Enum.map(beginner_tools, & &1.name)
      advanced_tool_names = Enum.map(advanced_tools, & &1.name)
      
      assert Enum.all?(beginner_tool_names, fn name ->
        Enum.member?(advanced_tool_names, name)
      end)
      
      # Advanced tools should include complex features
      advanced_only_tools = advanced_tools -- beginner_tools
      assert length(advanced_only_tools) > 0
      
      # Advanced-only tools should have higher complexity
      assert Enum.all?(advanced_only_tools, fn tool ->
        tool.complexity_level in [:advanced, :expert]
      end)
    end

    test "provides tool recommendations based on context" do
      context = %{
        task_type: :code_review,
        project_domain: :web_development,
        team_size: :small,
        quality_requirements: :high
      }

      recommendations = EngineeringTools.get_tool_recommendations(context)

      assert is_list(recommendations)
      assert length(recommendations) > 0
      
      # Should recommend testing framework for high quality requirements
      testing_recommendation = Enum.find(recommendations, fn rec ->
        rec.tool_category == :testing_framework
      end)
      assert testing_recommendation != nil
      assert testing_recommendation.reason =~ "quality"
      
      # Should recommend code review templates
      template_recommendation = Enum.find(recommendations, fn rec ->
        rec.tool_category == :template_management
      end)
      assert template_recommendation != nil
    end
  end

  describe "workspace management" do
    test "creates workspace for specific project domain" do
      project_context = %{
        domain: :machine_learning,
        project_type: :model_development,
        tech_stack: ["python", "tensorflow", "jupyter"],
        data_types: [:text, :images, :structured_data]
      }

      workspace = EngineeringTools.create_project_workspace(project_context)

      assert workspace.domain == :machine_learning
      assert workspace.project_type == :model_development
      
      # Should load ML-specific templates and tools
      template_categories = Map.keys(workspace.domain_templates)
      assert Enum.member?(template_categories, :data_preprocessing)
      assert Enum.member?(template_categories, :model_evaluation)
      assert Enum.member?(template_categories, :feature_engineering)
      
      # Should have data type specific tools
      data_tools = workspace.data_processing_tools
      assert Map.has_key?(data_tools, :text_processing)
      assert Map.has_key?(data_tools, :image_processing)
      assert Map.has_key?(data_tools, :structured_data_analysis)
    end

    test "configures workspace for team collaboration" do
      team_context = %{
        team_size: 10,
        collaboration_style: :trunk_based,
        review_process: :continuous_integration,
        deployment_frequency: :daily
      }

      workspace = EngineeringTools.configure_team_workspace(team_context)

      assert workspace.team_size == 10
      assert workspace.collaboration_style == :trunk_based
      
      # Should configure collaboration tools for large team
      collab_config = workspace.collaboration_config
      assert collab_config.concurrent_editors_limit > 5
      assert collab_config.conflict_resolution == :automatic_merge
      assert collab_config.notification_level == :minimal  # For large teams
      
      # Should enable CI-friendly features
      assert workspace.integration_config.ci_friendly == true
      assert workspace.integration_config.auto_testing == true
    end

    test "saves and loads workspace state" do
      workspace_data = %{
        workspace_id: "ws_test_123",
        user_id: "engineer_save",
        current_projects: [
          %{name: "Project A", domain: :web_dev},
          %{name: "Project B", domain: :data_science}
        ],
        recent_templates: ["bug_fix", "feature_request"],
        preferences: %{
          auto_save: true,
          theme: :dark,
          layout: :split_view
        }
      }

      # Save workspace
      :ok = EngineeringTools.save_workspace_state(workspace_data)

      # Load workspace
      loaded_workspace = EngineeringTools.load_workspace_state("ws_test_123")

      assert loaded_workspace.workspace_id == "ws_test_123"
      assert loaded_workspace.user_id == "engineer_save"
      assert length(loaded_workspace.current_projects) == 2
      assert loaded_workspace.preferences.theme == :dark
    end
  end

  describe "integration with existing systems" do
    test "integrates with agent framework" do
      agent_context = %{
        agent_id: "agent_123",
        current_session: "session_456",
        available_tools: [:read_file, :write_file, :execute_command],
        provider_info: %{provider: :anthropic, model: "claude-3-sonnet"}
      }

      integration = EngineeringTools.integrate_with_agent_framework(agent_context)

      assert integration.agent_id == "agent_123"
      assert Map.has_key?(integration, :tool_bridge)
      assert Map.has_key?(integration, :prompt_enhancement)
      assert Map.has_key?(integration, :session_management)
      
      # Should bridge engineering tools with agent tools
      tool_bridge = integration.tool_bridge
      assert Map.has_key?(tool_bridge, :file_operations)
      assert Map.has_key?(tool_bridge, :command_execution)
      assert tool_bridge.file_operations.read_enabled == true
      assert tool_bridge.file_operations.write_enabled == true
    end

    test "integrates with provider system" do
      provider_context = %{
        active_providers: [:openai, :anthropic, :google],
        provider_configs: %{
          openai: %{model: "gpt-4", temperature: 0.7},
          anthropic: %{model: "claude-3-sonnet", max_tokens: 4000},
          google: %{model: "gemini-pro", safety_settings: :default}
        }
      }

      integration = EngineeringTools.integrate_with_provider_system(provider_context)

      assert Map.has_key?(integration, :provider_optimization)
      assert Map.has_key?(integration, :cross_provider_testing)
      assert Map.has_key?(integration, :provider_performance_tracking)
      
      # Should enable cross-provider optimization
      optimization = integration.provider_optimization
      assert optimization.enabled == true
      assert length(optimization.supported_providers) == 3
      
      # Should enable A/B testing across providers
      testing = integration.cross_provider_testing
      assert testing.ab_testing_enabled == true
      assert testing.statistical_analysis_enabled == true
    end

    test "integrates with performance monitoring" do
      monitoring_context = %{
        metrics_collection: true,
        dashboard_url: "http://localhost:3000/metrics",
        alert_thresholds: %{
          response_time: 5000,
          error_rate: 0.05,
          quality_score: 0.7
        }
      }

      integration = EngineeringTools.integrate_with_performance_monitoring(monitoring_context)

      assert integration.metrics_collection == true
      assert integration.dashboard_integration.enabled == true
      assert Map.has_key?(integration, :alert_configuration)
      
      # Should configure performance alerts
      alerts = integration.alert_configuration
      assert alerts.response_time_threshold == 5000
      assert alerts.error_rate_threshold == 0.05
      assert alerts.quality_threshold == 0.7
    end
  end

  describe "CLI tools integration" do
    test "supports command-line prompt management" do
      # This would test the CLI interface functionality
      # For now, we verify that the CLI module structure exists
      assert function_exported?(EngineeringTools.CLI, :handle_command, 2)
      
      # Test basic command parsing
      {:ok, parsed} = EngineeringTools.CLI.parse_command("prompt create test_prompt --template basic")
      
      assert parsed.action == :create
      assert parsed.resource == :prompt
      assert parsed.name == "test_prompt"
      assert parsed.options.template == "basic"
    end

    test "supports template management via CLI" do
      {:ok, parsed} = EngineeringTools.CLI.parse_command("template list --category software_engineering")
      
      assert parsed.action == :list
      assert parsed.resource == :template
      assert parsed.options.category == "software_engineering"
    end

    test "supports experiment management via CLI" do
      {:ok, parsed} = EngineeringTools.CLI.parse_command("experiment create ab_test --variants 2 --duration 7d")
      
      assert parsed.action == :create
      assert parsed.resource == :experiment
      assert parsed.name == "ab_test"
      assert parsed.options.variants == "2"
      assert parsed.options.duration == "7d"
    end
  end
end