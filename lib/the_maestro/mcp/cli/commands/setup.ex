defmodule TheMaestro.MCP.CLI.Commands.Setup do
  @moduledoc """
  Setup command for MCP CLI.

  Provides guided setup and initialization of MCP system configuration.
  """

  alias TheMaestro.MCP.Config
  alias TheMaestro.MCP.CLI

  @doc """
  Execute the setup command.
  """
  def execute(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case args do
      [] ->
        run_guided_setup(options)

      ["init"] ->
        initialize_mcp_system(options)

      ["wizard"] ->
        run_setup_wizard(options)

      ["check"] ->
        run_system_check(options)

      ["repair"] ->
        repair_configuration(options)

      _ ->
        CLI.print_error("Invalid setup command. Use --help for usage.")
    end
  end

  @doc """
  Show help for the setup command.
  """
  def show_help do
    IO.puts("""
    MCP System Setup

    Usage:
      maestro mcp setup [subcommand] [OPTIONS]

    Commands:
      (none)           Run guided setup process
      init             Initialize MCP system with defaults
      wizard           Interactive setup wizard
      check            Check system configuration and dependencies
      repair           Repair configuration issues

    Options:
      --force          Force overwrite existing configuration
      --defaults       Use default values without prompting
      --config <path>  Specify configuration file path
      --verbose        Show detailed setup information
      --help           Show this help message

    Examples:
      maestro mcp setup                    # Guided setup
      maestro mcp setup init --defaults   # Quick initialization
      maestro mcp setup wizard            # Interactive wizard
      maestro mcp setup check --verbose   # System check
    """)
  end

  ## Private Functions

  defp run_guided_setup(options) do
    CLI.print_info("Starting MCP system setup...")

    # Check if already configured
    existing_config = check_existing_configuration()

    case existing_config do
      {:exists, config_path} ->
        if Map.get(options, :force, false) do
          proceed_with_setup(options)
        else
          CLI.print_warning("MCP configuration already exists at: #{config_path}")

          case prompt_yes_no("Do you want to reconfigure? (y/n): ") do
            true ->
              proceed_with_setup(options)

            false ->
              CLI.print_info("Setup cancelled")
              {:ok, :cancelled}
          end
        end

      {:not_exists} ->
        proceed_with_setup(options)
    end
  end

  defp initialize_mcp_system(options) do
    CLI.print_info("Initializing MCP system...")

    use_defaults = Map.get(options, :defaults, false)
    force = Map.get(options, :force, false)

    # Check system requirements
    case check_system_requirements() do
      :ok ->
        :continue

      {:error, missing} ->
        CLI.print_error("Missing system requirements:")
        Enum.each(missing, fn req -> IO.puts("  ❌ #{req}") end)
        {:error, :missing_requirements}
    end

    # Create default configuration
    config =
      if use_defaults do
        create_default_configuration()
      else
        create_interactive_configuration(options)
      end

    case config do
      {:ok, mcp_config} ->
        # Save configuration
        config_path = Map.get(options, :config, get_default_config_path())

        case save_initial_configuration(mcp_config, config_path, force) do
          :ok ->
            CLI.print_success("MCP system initialized successfully!")
            show_next_steps(config_path)
            {:ok, mcp_config}

          {:error, reason} ->
            CLI.print_error("Failed to save configuration: #{inspect(reason)}")
            {:error, :save_failed}
        end

      {:error, reason} ->
        CLI.print_error("Configuration creation failed: #{inspect(reason)}")
        {:error, :config_failed}
    end
  end

  defp run_setup_wizard(options) do
    CLI.print_info("🧙 MCP Setup Wizard")
    IO.puts("")

    # Welcome and overview
    IO.puts("This wizard will help you set up your MCP (Model Context Protocol) system.")
    IO.puts("You'll be guided through:")
    IO.puts("  1. System configuration")
    IO.puts("  2. Server setup")
    IO.puts("  3. Authentication configuration")
    IO.puts("  4. Testing and verification")
    IO.puts("")

    unless prompt_yes_no("Ready to begin? (y/n): ") do
      CLI.print_info("Setup wizard cancelled")
      {:ok, :cancelled}
    end

    # Step-by-step wizard
    with {:ok, system_config} <- wizard_step_1_system_config(options),
         {:ok, servers_config} <- wizard_step_2_servers_setup(system_config, options),
         {:ok, auth_config} <- wizard_step_3_authentication(servers_config, options),
         {:ok, final_config} <- wizard_step_4_finalization(auth_config, options) do
      CLI.print_success("🎉 Setup wizard completed successfully!")
      show_wizard_summary(final_config)

      {:ok, final_config}
    else
      {:error, reason} ->
        CLI.print_error("Setup wizard failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp run_system_check(options) do
    verbose = Map.get(options, :verbose, false)

    CLI.print_info("Running MCP system check...")
    IO.puts("")

    checks = [
      {"Configuration file", &check_configuration_file/1},
      {"System dependencies", &check_system_dependencies/1},
      {"Server configurations", &check_server_configurations/1},
      {"Network connectivity", &check_network_connectivity/1},
      {"Authentication setup", &check_authentication_setup/1},
      {"Permissions", &check_file_permissions/1}
    ]

    results =
      Enum.map(checks, fn {name, check_fn} ->
        IO.write("  Checking #{name}... ")

        result = check_fn.(verbose)

        case result do
          :ok ->
            IO.puts("✅")
            {name, :ok, nil}

          {:warning, message} ->
            IO.puts("⚠️")
            if verbose, do: IO.puts("    Warning: #{message}")
            {name, :warning, message}

          {:error, message} ->
            IO.puts("❌")
            if verbose, do: IO.puts("    Error: #{message}")
            {name, :error, message}
        end
      end)

    # Summary
    IO.puts("")
    passed = Enum.count(results, fn {_, status, _} -> status == :ok end)
    warnings = Enum.count(results, fn {_, status, _} -> status == :warning end)
    errors = Enum.count(results, fn {_, status, _} -> status == :error end)

    IO.puts("System Check Summary:")
    IO.puts("  ✅ Passed: #{passed}")
    if warnings > 0, do: IO.puts("  ⚠️  Warnings: #{warnings}")
    if errors > 0, do: IO.puts("  ❌ Errors: #{errors}")

    # Show issues if not verbose
    unless verbose do
      issues = Enum.filter(results, fn {_, status, _} -> status != :ok end)

      unless Enum.empty?(issues) do
        IO.puts("")
        IO.puts("Issues found:")

        Enum.each(issues, fn {name, status, message} ->
          icon = if status == :warning, do: "⚠️", else: "❌"
          IO.puts("  #{icon} #{name}: #{message}")
        end)
      end
    end

    if errors > 0 do
      {:error, :system_check_failed}
    else
      {:ok, :system_check_passed}
    end
  end

  defp repair_configuration(options) do
    CLI.print_info("Repairing MCP configuration...")

    # Identify issues
    case identify_configuration_issues() do
      {:ok, []} ->
        CLI.print_success("No configuration issues found")
        {:ok, :no_issues}

      {:ok, issues} ->
        IO.puts("")
        IO.puts("Configuration issues found:")

        Enum.each(issues, fn issue ->
          IO.puts("  ❌ #{issue.description}")
        end)

        IO.puts("")

        if prompt_yes_no("Attempt to repair these issues? (y/n): ") do
          repair_issues(issues, options)
        else
          CLI.print_info("Repair cancelled")
          {:ok, :cancelled}
        end

      {:error, reason} ->
        CLI.print_error("Failed to analyze configuration: #{inspect(reason)}")
        {:error, :analysis_failed}
    end
  end

  # Setup helper functions

  defp proceed_with_setup(options) do
    IO.puts("")
    IO.puts("MCP Setup Configuration:")
    IO.puts("  1. System requirements check")
    IO.puts("  2. Configuration file creation")
    IO.puts("  3. Default server setup (optional)")
    IO.puts("  4. Authentication configuration (optional)")
    IO.puts("")

    # Run the setup steps
    with :ok <- check_system_requirements(),
         {:ok, config} <- create_interactive_configuration(options),
         :ok <- save_configuration_with_backup(config, options) do
      CLI.print_success("Setup completed successfully!")
      show_next_steps(get_default_config_path())
      {:ok, config}
    else
      {:error, reason} ->
        CLI.print_error("Setup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_existing_configuration do
    config_paths = [
      get_default_config_path(),
      "./mcp_settings.json",
      "~/.config/mcp/settings.json"
    ]

    case Enum.find(config_paths, &File.exists?/1) do
      nil -> {:not_exists}
      path -> {:exists, path}
    end
  end

  defp check_system_requirements do
    requirements = [
      {"Elixir runtime", fn -> check_elixir_version() end},
      {"Network connectivity", fn -> check_internet_connectivity() end},
      {"File system permissions", fn -> check_write_permissions() end}
    ]

    missing =
      Enum.reduce(requirements, [], fn {name, check_fn}, acc ->
        case check_fn.() do
          :ok -> acc
          {:error, _} -> [name | acc]
        end
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, missing}
    end
  end

  defp create_default_configuration do
    %{
      version: "1.0",
      servers: %{},
      global: %{
        timeout: 30_000,
        max_retries: 3,
        log_level: "info"
      },
      security: %{
        default_trust_level: :medium,
        require_authentication: false,
        enable_logging: true
      }
    }
  end

  defp create_interactive_configuration(options) do
    CLI.print_info("Creating configuration...")

    config = create_default_configuration()

    # Ask about global settings
    IO.puts("")
    IO.puts("Global Settings:")

    timeout = prompt_for_integer("Request timeout (ms) [30000]: ", 30_000)
    max_retries = prompt_for_integer("Max retries [3]: ", 3)
    log_level = prompt_for_choice("Log level", ["debug", "info", "warning", "error"], "info")

    global_config = %{
      timeout: timeout,
      max_retries: max_retries,
      log_level: log_level
    }

    # Ask about security settings
    IO.puts("")
    IO.puts("Security Settings:")

    default_trust =
      prompt_for_choice("Default trust level", ["none", "low", "medium", "high"], "medium")

    require_auth = prompt_yes_no("Require authentication by default? (y/n): ")
    enable_logging = prompt_yes_no("Enable request logging? (y/n): ", true)

    security_config = %{
      default_trust_level: String.to_atom(default_trust),
      require_authentication: require_auth,
      enable_logging: enable_logging
    }

    # Ask about adding sample servers
    IO.puts("")

    if prompt_yes_no("Would you like to add some example servers? (y/n): ") do
      servers = create_sample_servers()

      final_config = %{
        config
        | global: global_config,
          security: security_config,
          servers: servers
      }

      {:ok, final_config}
    else
      final_config = %{config | global: global_config, security: security_config}
      {:ok, final_config}
    end
  end

  defp create_sample_servers do
    %{
      "example_local" => %{
        name: "example_local",
        transport: %{
          type: :stdio,
          command: "python3",
          args: ["example_server.py"]
        },
        capabilities: %{
          tools: true,
          resources: false,
          prompts: false
        },
        trust_level: :medium,
        enabled: false
      },
      "example_http" => %{
        name: "example_http",
        transport: %{
          type: :http,
          base_url: "https://api.example.com",
          headers: %{
            "Content-Type" => "application/json"
          }
        },
        capabilities: %{
          tools: true,
          resources: true,
          prompts: true
        },
        trust_level: :low,
        enabled: false
      }
    }
  end

  # Wizard step functions

  defp wizard_step_1_system_config(_options) do
    IO.puts("")
    IO.puts("📋 Step 1: System Configuration")
    IO.puts("")

    # System-level settings
    config = create_default_configuration()

    CLI.print_info("Configuring system defaults...")

    timeout = prompt_for_integer("Global timeout (ms) [30000]: ", 30_000)
    log_level = prompt_for_choice("Log level", ["debug", "info", "warning", "error"], "info")

    system_config = %{config | global: %{config.global | timeout: timeout, log_level: log_level}}

    {:ok, system_config}
  end

  defp wizard_step_2_servers_setup(config, _options) do
    IO.puts("")
    IO.puts("🖥️  Step 2: Server Setup")
    IO.puts("")

    if prompt_yes_no("Would you like to set up any MCP servers now? (y/n): ") do
      servers = add_servers_interactively(%{})
      updated_config = %{config | servers: servers}
      {:ok, updated_config}
    else
      IO.puts("   You can add servers later using: maestro mcp add <server-name>")
      {:ok, config}
    end
  end

  defp wizard_step_3_authentication(config, _options) do
    IO.puts("")
    IO.puts("🔐 Step 3: Authentication")
    IO.puts("")

    require_auth = prompt_yes_no("Require authentication for new servers by default? (y/n): ")

    default_trust =
      prompt_for_choice("Default trust level", ["none", "low", "medium", "high"], "medium")

    security_config = %{
      config.security
      | require_authentication: require_auth,
        default_trust_level: String.to_atom(default_trust)
    }

    updated_config = %{config | security: security_config}
    {:ok, updated_config}
  end

  defp wizard_step_4_finalization(config, options) do
    IO.puts("")
    IO.puts("✅ Step 4: Finalization")
    IO.puts("")

    # Show configuration summary
    show_configuration_summary(config)

    IO.puts("")

    if prompt_yes_no("Save this configuration? (y/n): ") do
      config_path = Map.get(options, :config, get_default_config_path())

      case save_initial_configuration(config, config_path, false) do
        :ok ->
          {:ok, config}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :user_cancelled}
    end
  end

  # System check functions

  defp check_configuration_file(_verbose) do
    case Config.load_configuration() do
      {:ok, _} -> :ok
      {:error, :file_not_found} -> {:error, "Configuration file not found"}
      {:error, reason} -> {:error, "Configuration error: #{inspect(reason)}"}
    end
  end

  defp check_system_dependencies(_verbose) do
    case check_elixir_version() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_server_configurations(_verbose) do
    case Config.load_configuration() do
      {:ok, config} ->
        if map_size(config.servers) == 0 do
          {:warning, "No servers configured"}
        else
          :ok
        end

      {:error, _} ->
        {:error, "Cannot check servers - configuration load failed"}
    end
  end

  defp check_network_connectivity(_verbose) do
    case check_internet_connectivity() do
      :ok -> :ok
      {:error, reason} -> {:warning, "Network connectivity issue: #{reason}"}
    end
  end

  defp check_authentication_setup(_verbose) do
    # Check if any servers require authentication but lack credentials
    case Config.load_configuration() do
      {:ok, config} ->
        servers_needing_auth =
          config.servers
          |> Enum.filter(fn {_name, server} ->
            Map.get(server, :auth_method, :none) != :none
          end)
          |> Enum.count()

        if servers_needing_auth > 0 do
          {:warning, "#{servers_needing_auth} server(s) require authentication"}
        else
          :ok
        end

      {:error, _} ->
        {:error, "Cannot check authentication - configuration load failed"}
    end
  end

  defp check_file_permissions(_verbose) do
    case check_write_permissions() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Utility functions

  defp prompt_yes_no(prompt, default \\ nil) do
    case IO.gets(prompt) do
      input when is_binary(input) ->
        case String.trim(String.downcase(input)) do
          "" when default != nil ->
            default

          "y" ->
            true

          "yes" ->
            true

          "n" ->
            false

          "no" ->
            false

          _ ->
            IO.puts("Please enter 'y' or 'n'")
            prompt_yes_no(prompt, default)
        end

      _ ->
        false
    end
  end

  defp prompt_for_integer(prompt, default) do
    case IO.gets(prompt) do
      input when is_binary(input) ->
        trimmed = String.trim(input)

        if trimmed == "" do
          default
        else
          case Integer.parse(trimmed) do
            {value, ""} ->
              value

            _ ->
              IO.puts("Please enter a valid number")
              prompt_for_integer(prompt, default)
          end
        end

      _ ->
        default
    end
  end

  defp prompt_for_choice(prompt, choices, default) do
    IO.puts("#{prompt} (#{Enum.join(choices, "/")}) [#{default}]: ")

    case IO.gets("") do
      input when is_binary(input) ->
        trimmed = String.trim(String.downcase(input))

        cond do
          trimmed == "" ->
            default

          trimmed in choices ->
            trimmed

          true ->
            IO.puts("Please choose from: #{Enum.join(choices, ", ")}")
            prompt_for_choice(prompt, choices, default)
        end

      _ ->
        default
    end
  end

  defp add_servers_interactively(servers) do
    IO.puts("Adding servers interactively...")
    # This would be a more complex interactive flow
    servers
  end

  defp get_default_config_path do
    Path.join([System.user_home!(), ".config", "maestro", "mcp_settings.json"])
  end

  defp save_initial_configuration(config, config_path, force) do
    # Create directory if needed
    config_dir = Path.dirname(config_path)
    File.mkdir_p(config_dir)

    # Check if file exists
    if File.exists?(config_path) && not force do
      {:error, :file_exists}
    else
      # Save configuration
      json_config = Jason.encode!(config, pretty: true)

      case File.write(config_path, json_config) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp save_configuration_with_backup(config, options) do
    config_path = Map.get(options, :config, get_default_config_path())

    # Create backup if file exists
    if File.exists?(config_path) do
      backup_path = config_path <> ".backup"
      File.cp(config_path, backup_path)
      CLI.print_info("Backup created: #{backup_path}")
    end

    save_initial_configuration(config, config_path, true)
  end

  defp show_configuration_summary(config) do
    IO.puts("Configuration Summary:")
    IO.puts("  Global timeout: #{config.global.timeout}ms")
    IO.puts("  Log level: #{config.global.log_level}")
    IO.puts("  Default trust: #{config.security.default_trust_level}")
    IO.puts("  Require auth: #{config.security.require_authentication}")
    IO.puts("  Servers: #{map_size(config.servers)}")
  end

  defp show_wizard_summary(config) do
    IO.puts("")
    IO.puts("Setup Summary:")
    IO.puts("  ✅ Configuration created")
    IO.puts("  ✅ System settings configured")
    IO.puts("  ✅ Security settings applied")
    IO.puts("  ✅ #{map_size(config.servers)} server(s) configured")

    show_next_steps(get_default_config_path())
  end

  defp show_next_steps(config_path) do
    IO.puts("")
    IO.puts("Next Steps:")
    IO.puts("  1. Review your configuration: #{config_path}")
    IO.puts("  2. Add MCP servers: maestro mcp add <server-name>")
    IO.puts("  3. Test connectivity: maestro mcp status")
    IO.puts("  4. Explore available tools: maestro mcp tools list")
  end

  # System check implementations

  defp check_elixir_version do
    version = System.version()

    if Version.match?(version, ">= 1.13.0") do
      :ok
    else
      {:error, "Elixir version #{version} is too old (minimum: 1.13.0)"}
    end
  end

  defp check_internet_connectivity do
    case System.cmd("ping", ["-c", "1", "8.8.8.8"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> {:error, "Cannot reach external network"}
    end
  rescue
    _ -> {:error, "Cannot test network connectivity"}
  end

  defp check_write_permissions do
    test_file = Path.join(System.tmp_dir!(), "mcp_test_#{:rand.uniform(1000)}")

    case File.write(test_file, "test") do
      :ok ->
        File.rm(test_file)
        :ok

      {:error, reason} ->
        {:error, "Cannot write files: #{reason}"}
    end
  end

  # Repair functions

  defp identify_configuration_issues do
    issues = []

    # Check configuration file
    issues =
      case Config.load_configuration() do
        {:ok, _} ->
          issues

        {:error, reason} ->
          [%{type: :config_error, description: "Configuration load failed: #{inspect(reason)}"}] ++
            issues
      end

    # Add more issue checks here

    {:ok, issues}
  end

  defp repair_issues(issues, _options) do
    CLI.print_info("Attempting to repair issues...")

    repaired =
      Enum.reduce(issues, 0, fn issue, count ->
        case repair_single_issue(issue) do
          :ok ->
            CLI.print_success("  ✅ Repaired: #{issue.description}")
            count + 1

          {:error, reason} ->
            CLI.print_error(
              "  ❌ Failed to repair: #{issue.description} (#{reason})"
            )

            count
        end
      end)

    total = length(issues)
    CLI.print_info("Repair completed: #{repaired}/#{total} issues fixed")

    if repaired == total do
      {:ok, :all_repaired}
    else
      {:error, :partial_repair}
    end
  end

  defp repair_single_issue(issue) do
    case issue.type do
      :config_error ->
        # Try to create a default configuration
        default_config = create_default_configuration()
        save_initial_configuration(default_config, get_default_config_path(), true)

      _ ->
        {:error, :unknown_issue}
    end
  end
end
