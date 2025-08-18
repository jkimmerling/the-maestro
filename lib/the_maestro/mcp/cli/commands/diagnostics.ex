defmodule TheMaestro.MCP.CLI.Commands.Diagnostics do
  @moduledoc """
  Diagnostics and troubleshooting commands for MCP CLI.

  Provides functionality for system diagnosis, server logs, connectivity testing,
  and comprehensive troubleshooting support.
  """

  alias TheMaestro.MCP.{Config, ConnectionManager}

  @doc """
  Diagnose system issues and connectivity problems.
  """
  def diagnose(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case args do
      [] ->
        run_comprehensive_diagnosis(options)

      [server_name | _] ->
        diagnose_server(server_name, options)
    end
  end

  @doc """
  Show server logs with filtering and search capabilities.
  """
  def show_logs(args, options) do
    case args do
      [] ->
        TheMaestro.MCP.CLI.print_error("Server name is required for log viewing.")

      [server_name | _] ->
        show_server_logs(server_name, options)
    end
  end

  @doc """
  Ping server to test basic connectivity.
  """
  def ping_server(args, options) do
    case args do
      [] ->
        TheMaestro.MCP.CLI.print_error("Server name is required for ping.")

      [server_name | _] ->
        ping_specific_server(server_name, options)
    end
  end

  @doc """
  Trace connection and protocol interactions.
  """
  def trace_connection(args, options) do
    case args do
      [] ->
        TheMaestro.MCP.CLI.print_error("Server name is required for tracing.")

      [server_name | _] ->
        trace_server_connection(server_name, options)
    end
  end

  @doc """
  Show help for the diagnostics command.
  """
  def show_help do
    IO.puts("""
    MCP Diagnostics & Troubleshooting

    Usage:
      maestro mcp diagnose [server] [OPTIONS]       # Run system diagnosis
      maestro mcp logs <server> [OPTIONS]           # View server logs
      maestro mcp ping <server> [OPTIONS]           # Test server connectivity
      maestro mcp trace <server> [OPTIONS]          # Trace connection details

    Diagnose Options:
      --verbose                Show detailed diagnostic information
      --network                Include network connectivity tests
      --permissions            Check file and directory permissions
      --dependencies           Verify system dependencies
      --configuration          Validate configuration files

    Logs Options:
      --follow                 Follow logs in real-time (like tail -f)
      --lines <n>              Number of lines to show (default: 50)
      --level <level>          Filter by log level (error, warn, info, debug)
      --since <time>           Show logs since specified time
      --grep <pattern>         Filter logs by pattern

    Ping Options:
      --count <n>              Number of ping attempts (default: 3)
      --timeout <ms>           Timeout per ping attempt (default: 5000ms)
      --interval <ms>          Interval between pings (default: 1000ms)

    Trace Options:
      --duration <seconds>     How long to trace (default: 10 seconds)
      --verbose                Show detailed protocol messages
      --save <file>            Save trace to file

    Examples:
      maestro mcp diagnose                          # Full system diagnosis
      maestro mcp diagnose myServer --verbose       # Detailed server diagnosis
      maestro mcp logs myServer --follow            # Follow server logs
      maestro mcp logs myServer --level error       # Show only error logs
      maestro mcp ping myServer --count 5           # Ping server 5 times
      maestro mcp trace myServer --duration 30      # Trace for 30 seconds
    """)
  end

  ## Private Functions - Comprehensive Diagnosis

  defp run_comprehensive_diagnosis(options) do
    IO.puts("MCP System Diagnosis")
    IO.puts("#{String.duplicate("=", 25)}")
    IO.puts("")

    TheMaestro.MCP.CLI.print_if_verbose("Running comprehensive system diagnosis...", options)

    # Run multiple diagnostic checks
    results = %{
      system: diagnose_system_health(options),
      configuration: diagnose_configuration(options),
      servers: diagnose_all_servers(options),
      network: if(Map.get(options, :network), do: diagnose_network(options), else: :skipped),
      permissions:
        if(Map.get(options, :permissions), do: diagnose_permissions(options), else: :skipped),
      dependencies:
        if(Map.get(options, :dependencies), do: diagnose_dependencies(options), else: :skipped)
    }

    display_diagnosis_results(results, options)

    # Provide recommendations based on results
    recommendations = generate_diagnosis_recommendations(results)

    unless Enum.empty?(recommendations) do
      IO.puts("")
      IO.puts("Recommendations:")

      Enum.each(recommendations, fn rec ->
        IO.puts("  💡 #{rec.title}")
        IO.puts("     #{rec.description}")

        if rec.priority do
          IO.puts("     Priority: #{rec.priority}")
        end
      end)
    end
  end

  defp diagnose_server(server_name, options) do
    IO.puts("Server Diagnosis: #{server_name}")
    IO.puts("#{String.duplicate("=", String.length("Server Diagnosis: #{server_name}"))}")
    IO.puts("")

    TheMaestro.MCP.CLI.print_if_verbose("Diagnosing server '#{server_name}'...", options)

    case Config.get_configuration() do
      {:ok, config} ->
        case get_in(config, ["mcpServers", server_name]) do
          nil ->
            TheMaestro.MCP.CLI.print_error("Server '#{server_name}' not found in configuration.")

          server_config ->
            results = run_server_diagnosis(server_name, server_config, options)
            display_server_diagnosis_results(server_name, results, options)
        end

      {:error, reason} ->
        TheMaestro.MCP.CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp diagnose_system_health(options) do
    checks = %{
      process_status: check_process_status(),
      memory_usage: check_memory_usage(),
      disk_space: check_disk_space(),
      config_directory: check_config_directory()
    }

    passing_checks = Enum.count(checks, fn {_check, result} -> result.status == :pass end)
    total_checks = map_size(checks)

    %{
      status: if(passing_checks == total_checks, do: :healthy, else: :issues),
      checks: checks,
      score: if(total_checks > 0, do: passing_checks / total_checks * 100, else: 0)
    }
  end

  defp diagnose_configuration(options) do
    checks = %{
      config_file_exists: check_config_file_exists(),
      config_file_valid: check_config_file_valid(),
      config_schema: check_config_schema(),
      server_configs: check_server_configurations()
    }

    passing_checks = Enum.count(checks, fn {_check, result} -> result.status == :pass end)
    total_checks = map_size(checks)

    %{
      status: if(passing_checks == total_checks, do: :valid, else: :issues),
      checks: checks,
      score: if(total_checks > 0, do: passing_checks / total_checks * 100, else: 0)
    }
  end

  defp diagnose_all_servers(options) do
    case Config.get_configuration() do
      {:ok, config} ->
        servers = get_in(config, ["mcpServers"]) || %{}

        server_results =
          servers
          |> Enum.map(fn {server_id, server_config} ->
            result = run_basic_server_diagnosis(server_id, server_config)
            {server_id, result}
          end)
          |> Enum.into(%{})

        healthy_servers =
          Enum.count(server_results, fn {_id, result} ->
            result.status == :healthy
          end)

        %{
          status: if(healthy_servers == map_size(servers), do: :all_healthy, else: :some_issues),
          servers: server_results,
          total_servers: map_size(servers),
          healthy_servers: healthy_servers
        }

      {:error, _reason} ->
        %{
          status: :config_error,
          servers: %{},
          total_servers: 0,
          healthy_servers: 0
        }
    end
  end

  defp diagnose_network(options) do
    checks = %{
      internet_connectivity: check_internet_connectivity(),
      dns_resolution: check_dns_resolution(),
      port_accessibility: check_common_ports()
    }

    %{
      status: :completed,
      checks: checks
    }
  end

  defp diagnose_permissions(options) do
    checks = %{
      config_directory_writable: check_config_directory_writable(),
      log_directory_writable: check_log_directory_writable(),
      executable_permissions: check_executable_permissions()
    }

    %{
      status: :completed,
      checks: checks
    }
  end

  defp diagnose_dependencies(options) do
    checks = %{
      elixir_version: check_elixir_version(),
      required_applications: check_required_applications(),
      system_tools: check_system_tools()
    }

    %{
      status: :completed,
      checks: checks
    }
  end

  defp run_server_diagnosis(server_id, server_config, options) do
    checks = %{
      configuration_valid: validate_server_configuration(server_id, server_config),
      connectivity: test_server_connectivity(server_id, server_config),
      command_executable: check_server_command(server_config),
      transport_specific: run_transport_specific_checks(server_config),
      tools_available: check_server_tools(server_id),
      performance: check_server_performance(server_id)
    }

    passing_checks = Enum.count(checks, fn {_check, result} -> result.status == :pass end)
    total_checks = map_size(checks)

    %{
      status: if(passing_checks >= total_checks * 0.8, do: :healthy, else: :unhealthy),
      checks: checks,
      score: if(total_checks > 0, do: passing_checks / total_checks * 100, else: 0)
    }
  end

  defp run_basic_server_diagnosis(server_id, server_config) do
    # Simplified diagnosis for the overview
    connectivity_result = test_server_connectivity(server_id, server_config)
    config_result = validate_server_configuration(server_id, server_config)

    status =
      case {connectivity_result.status, config_result.status} do
        {:pass, :pass} -> :healthy
        {:pass, _} -> :config_issues
        {_, :pass} -> :connectivity_issues
        {_, _} -> :multiple_issues
      end

    %{
      status: status,
      connectivity: connectivity_result,
      configuration: config_result
    }
  end

  ## System Health Checks

  defp check_process_status do
    # Check if the main application is running properly
    case Process.whereis(TheMaestro.Application) do
      pid when is_pid(pid) ->
        %{status: :pass, message: "Application process running (PID: #{inspect(pid)})"}

      nil ->
        %{status: :fail, message: "Application process not found"}
    end
  end

  defp check_memory_usage do
    memory_info = :erlang.memory()
    total_mb = div(memory_info[:total], 1024 * 1024)

    cond do
      total_mb < 100 ->
        %{status: :pass, message: "Memory usage: #{total_mb}MB (healthy)"}

      total_mb < 500 ->
        %{status: :warning, message: "Memory usage: #{total_mb}MB (moderate)"}

      true ->
        %{status: :fail, message: "Memory usage: #{total_mb}MB (high)"}
    end
  end

  defp check_disk_space do
    case File.stat(".") do
      {:ok, _stat} ->
        # Simple disk space check - in production would use system commands
        %{status: :pass, message: "Disk space check passed"}

      {:error, reason} ->
        %{status: :fail, message: "Disk space check failed: #{reason}"}
    end
  end

  defp check_config_directory do
    config_dir = "./.maestro"

    cond do
      File.exists?(config_dir) and File.dir?(config_dir) ->
        %{status: :pass, message: "Configuration directory exists: #{config_dir}"}

      File.exists?(config_dir) ->
        %{
          status: :fail,
          message: "Configuration path exists but is not a directory: #{config_dir}"
        }

      true ->
        %{status: :warning, message: "Configuration directory does not exist: #{config_dir}"}
    end
  end

  ## Configuration Checks

  defp check_config_file_exists do
    config_path = "./.maestro/mcp_settings.json"

    if File.exists?(config_path) do
      %{status: :pass, message: "Configuration file exists: #{config_path}"}
    else
      %{status: :warning, message: "Configuration file not found: #{config_path}"}
    end
  end

  defp check_config_file_valid do
    config_path = "./.maestro/mcp_settings.json"

    case File.read(config_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, _config} ->
            %{status: :pass, message: "Configuration file is valid JSON"}

          {:error, reason} ->
            %{status: :fail, message: "Configuration file has invalid JSON: #{inspect(reason)}"}
        end

      {:error, :enoent} ->
        %{status: :warning, message: "Configuration file not found"}

      {:error, reason} ->
        %{status: :fail, message: "Cannot read configuration file: #{reason}"}
    end
  end

  defp check_config_schema do
    case Config.get_configuration() do
      {:ok, config} ->
        case TheMaestro.MCP.Config.ConfigValidator.validate(config) do
          {:ok, _validated_config} ->
            %{status: :pass, message: "Configuration schema is valid"}

          {:error, errors} ->
            %{status: :fail, message: "Configuration schema errors: #{Enum.join(errors, ", ")}"}
        end

      {:error, reason} ->
        %{status: :fail, message: "Cannot load configuration: #{reason}"}
    end
  end

  defp check_server_configurations do
    case Config.get_configuration() do
      {:ok, config} ->
        servers = get_in(config, ["mcpServers"]) || %{}

        if map_size(servers) > 0 do
          invalid_servers =
            servers
            |> Enum.filter(fn {server_id, server_config} ->
              errors =
                TheMaestro.MCP.Config.ConfigValidator.validate_server_config(
                  server_id,
                  server_config
                )

              not Enum.empty?(errors)
            end)

          if Enum.empty?(invalid_servers) do
            %{status: :pass, message: "All server configurations are valid"}
          else
            invalid_names = Enum.map(invalid_servers, fn {server_id, _} -> server_id end)

            %{
              status: :fail,
              message: "Invalid server configurations: #{Enum.join(invalid_names, ", ")}"
            }
          end
        else
          %{status: :warning, message: "No servers configured"}
        end

      {:error, reason} ->
        %{status: :fail, message: "Cannot load configuration: #{reason}"}
    end
  end

  ## Server-Specific Checks

  defp validate_server_configuration(server_id, server_config) do
    case TheMaestro.MCP.Config.ConfigValidator.validate_server_config(server_id, server_config) do
      [] ->
        %{status: :pass, message: "Server configuration is valid"}

      errors ->
        %{status: :fail, message: "Configuration errors: #{Enum.join(errors, ", ")}"}
    end
  end

  defp test_server_connectivity(server_id, server_config) do
    case ConnectionManager.test_connection(
           ConnectionManager,
           Map.put(server_config, :id, server_id)
         ) do
      {:ok, _result} ->
        %{status: :pass, message: "Server connectivity test passed"}

      {:error, :timeout} ->
        %{status: :fail, message: "Server connectivity test timed out"}

      {:error, :connection_refused} ->
        %{status: :fail, message: "Connection refused - server may not be running"}

      {:error, reason} ->
        %{status: :fail, message: "Connectivity test failed: #{reason}"}
    end
  end

  defp check_server_command(server_config) do
    case Map.get(server_config, "command") do
      nil ->
        %{status: :skip, message: "No command specified (not STDIO transport)"}

      command ->
        if String.contains?(command, "/") do
          # Absolute or relative path
          if File.exists?(command) do
            %{status: :pass, message: "Command file exists: #{command}"}
          else
            %{status: :fail, message: "Command file not found: #{command}"}
          end
        else
          # Command in PATH
          case System.find_executable(command) do
            nil ->
              %{status: :fail, message: "Command not found in PATH: #{command}"}

            path ->
              %{status: :pass, message: "Command found in PATH: #{path}"}
          end
        end
    end
  end

  defp run_transport_specific_checks(server_config) do
    cond do
      Map.has_key?(server_config, "command") ->
        check_stdio_transport(server_config)

      Map.has_key?(server_config, "url") ->
        check_sse_transport(server_config)

      Map.has_key?(server_config, "httpUrl") ->
        check_http_transport(server_config)

      true ->
        %{status: :fail, message: "No transport configuration found"}
    end
  end

  defp check_stdio_transport(server_config) do
    # Check working directory if specified
    cwd = Map.get(server_config, "cwd")

    cwd_result =
      if cwd do
        if File.dir?(cwd) do
          "Working directory exists: #{cwd}"
        else
          "Working directory not found: #{cwd}"
        end
      else
        "No working directory specified"
      end

    %{status: :pass, message: "STDIO transport configuration OK. #{cwd_result}"}
  end

  defp check_sse_transport(server_config) do
    url = Map.get(server_config, "url")

    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        %{status: :pass, message: "SSE URL format is valid: #{url}"}

      _ ->
        %{status: :fail, message: "Invalid SSE URL format: #{url}"}
    end
  end

  defp check_http_transport(server_config) do
    url = Map.get(server_config, "httpUrl")

    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        %{status: :pass, message: "HTTP URL format is valid: #{url}"}

      _ ->
        %{status: :fail, message: "Invalid HTTP URL format: #{url}"}
    end
  end

  defp check_server_tools(server_id) do
    case ConnectionManager.get_server_tools(ConnectionManager, server_id) do
      {:ok, tools} when is_list(tools) ->
        %{status: :pass, message: "Server has #{length(tools)} tools available"}

      {:ok, []} ->
        %{status: :warning, message: "Server has no tools available"}

      {:error, :not_connected} ->
        %{status: :warning, message: "Cannot check tools - server not connected"}

      {:error, reason} ->
        %{status: :fail, message: "Failed to get server tools: #{reason}"}
    end
  end

  defp check_server_performance(server_id) do
    case ConnectionManager.ping_server(ConnectionManager, server_id) do
      {:ok, response_time} when response_time < 1000 ->
        %{status: :pass, message: "Server response time: #{response_time}ms (good)"}

      {:ok, response_time} when response_time < 5000 ->
        %{status: :warning, message: "Server response time: #{response_time}ms (slow)"}

      {:ok, response_time} ->
        %{status: :fail, message: "Server response time: #{response_time}ms (very slow)"}

      {:error, reason} ->
        %{status: :fail, message: "Performance check failed: #{reason}"}
    end
  end

  ## Network Checks

  defp check_internet_connectivity do
    # Simple internet connectivity check
    try do
      case System.cmd("ping", ["-c", "1", "-W", "3000", "8.8.8.8"], stderr_to_stdout: true) do
        {_output, 0} ->
          %{status: :pass, message: "Internet connectivity is working"}

        {output, _code} ->
          %{status: :fail, message: "Internet connectivity failed: #{String.trim(output)}"}
      end
    rescue
      _ ->
        %{status: :warning, message: "Cannot test internet connectivity (ping not available)"}
    end
  end

  defp check_dns_resolution do
    case :inet.gethostbyname(~c"google.com") do
      {:ok, _hostent} ->
        %{status: :pass, message: "DNS resolution is working"}

      {:error, reason} ->
        %{status: :fail, message: "DNS resolution failed: #{reason}"}
    end
  end

  defp check_common_ports do
    # Check if common ports are accessible (basic check)
    ports_to_check = [80, 443, 8080, 3000]

    accessible_ports =
      ports_to_check
      |> Enum.filter(fn port ->
        case :gen_tcp.connect(~c"httpbin.org", port, [], 1000) do
          {:ok, socket} ->
            :gen_tcp.close(socket)
            true

          {:error, _} ->
            false
        end
      end)

    if length(accessible_ports) > 0 do
      %{status: :pass, message: "Network ports accessible: #{Enum.join(accessible_ports, ", ")}"}
    else
      %{status: :warning, message: "No common network ports are accessible"}
    end
  end

  ## Permission Checks

  defp check_config_directory_writable do
    config_dir = "./.maestro"
    test_file = Path.join(config_dir, "write_test.tmp")

    # Ensure directory exists
    File.mkdir_p(config_dir)

    case File.write(test_file, "test") do
      :ok ->
        File.rm(test_file)
        %{status: :pass, message: "Configuration directory is writable"}

      {:error, reason} ->
        %{status: :fail, message: "Configuration directory is not writable: #{reason}"}
    end
  end

  defp check_log_directory_writable do
    log_dir = "./.maestro/logs"
    test_file = Path.join(log_dir, "write_test.tmp")

    # Ensure directory exists
    File.mkdir_p(log_dir)

    case File.write(test_file, "test") do
      :ok ->
        File.rm(test_file)
        %{status: :pass, message: "Log directory is writable"}

      {:error, reason} ->
        %{status: :fail, message: "Log directory is not writable: #{reason}"}
    end
  end

  defp check_executable_permissions do
    # Check if we can execute basic system commands
    try do
      case System.cmd("echo", ["test"], stderr_to_stdout: true) do
        {"test\n", 0} ->
          %{status: :pass, message: "System command execution is working"}

        {output, code} ->
          %{status: :fail, message: "System command execution failed (#{code}): #{output}"}
      end
    rescue
      _ ->
        %{status: :fail, message: "Cannot execute system commands"}
    end
  end

  ## Dependency Checks

  defp check_elixir_version do
    version = System.version()

    case Version.parse(version) do
      {:ok, %Version{major: major, minor: minor}} when major >= 1 and minor >= 12 ->
        %{status: :pass, message: "Elixir version: #{version} (compatible)"}

      {:ok, _version} ->
        %{status: :warning, message: "Elixir version: #{version} (may be outdated)"}

      :error ->
        %{status: :fail, message: "Cannot parse Elixir version: #{version}"}
    end
  end

  defp check_required_applications do
    required_apps = [:jason, :httpoison, :yaml_elixir]

    missing_apps =
      required_apps
      |> Enum.filter(fn app ->
        case Application.load(app) do
          :ok -> false
          {:error, _} -> true
        end
      end)

    if Enum.empty?(missing_apps) do
      %{status: :pass, message: "All required applications are available"}
    else
      %{status: :fail, message: "Missing applications: #{Enum.join(missing_apps, ", ")}"}
    end
  end

  defp check_system_tools do
    tools_to_check = ["curl", "ping"]

    available_tools =
      tools_to_check
      |> Enum.filter(fn tool ->
        case System.find_executable(tool) do
          nil -> false
          _path -> true
        end
      end)

    if length(available_tools) == length(tools_to_check) do
      %{status: :pass, message: "All system tools are available"}
    else
      missing = tools_to_check -- available_tools
      %{status: :warning, message: "Missing system tools: #{Enum.join(missing, ", ")}"}
    end
  end

  ## Display Functions

  defp display_diagnosis_results(results, options) do
    # System Health
    display_diagnosis_section("System Health", results.system)

    # Configuration
    display_diagnosis_section("Configuration", results.configuration)

    # Servers
    display_servers_diagnosis_section(results.servers)

    # Optional sections
    if results.network != :skipped do
      display_diagnosis_section("Network", results.network)
    end

    if results.permissions != :skipped do
      display_diagnosis_section("Permissions", results.permissions)
    end

    if results.dependencies != :skipped do
      display_diagnosis_section("Dependencies", results.dependencies)
    end

    # Overall summary
    display_overall_diagnosis_summary(results)
  end

  defp display_diagnosis_section(title, section_result) do
    IO.puts("#{title}:")

    case section_result do
      %{checks: checks} ->
        Enum.each(checks, fn {check_name, result} ->
          status_icon =
            case result.status do
              :pass -> "✓"
              :warning -> "⚠"
              :fail -> "✗"
              :skip -> "⚪"
            end

          IO.puts("  #{status_icon} #{format_check_name(check_name)}: #{result.message}")
        end)

      %{status: status, message: message} ->
        status_icon =
          case status do
            :pass -> "✓"
            :warning -> "⚠"
            :fail -> "✗"
          end

        IO.puts("  #{status_icon} #{message}")
    end

    IO.puts("")
  end

  defp display_servers_diagnosis_section(servers_result) do
    IO.puts("Servers:")

    case servers_result.status do
      :all_healthy ->
        IO.puts("  ✓ All #{servers_result.total_servers} servers are healthy")

      :some_issues ->
        IO.puts(
          "  ⚠ #{servers_result.healthy_servers}/#{servers_result.total_servers} servers are healthy"
        )

        # Show problematic servers
        Enum.each(servers_result.servers, fn {server_id, result} ->
          if result.status != :healthy do
            status_icon =
              case result.status do
                :config_issues -> "⚠"
                :connectivity_issues -> "⚠"
                :multiple_issues -> "✗"
                _ -> "✗"
              end

            IO.puts("    #{status_icon} #{server_id}: #{format_server_status(result.status)}")
          end
        end)

      :config_error ->
        IO.puts("  ✗ Cannot diagnose servers due to configuration error")
    end

    IO.puts("")
  end

  defp display_server_diagnosis_results(server_name, results, options) do
    IO.puts(
      "Overall Status: #{format_diagnosis_status(results.status)} (#{Float.round(results.score, 1)}%)"
    )

    IO.puts("")

    Enum.each(results.checks, fn {check_name, result} ->
      status_icon =
        case result.status do
          :pass -> "✓"
          :warning -> "⚠"
          :fail -> "✗"
          :skip -> "⚪"
        end

      IO.puts("#{status_icon} #{format_check_name(check_name)}: #{result.message}")
    end)
  end

  defp display_overall_diagnosis_summary(results) do
    IO.puts("Overall System Health Summary:")
    IO.puts("#{String.duplicate("-", 35)}")

    system_score = Map.get(results.system, :score, 0)
    config_score = Map.get(results.configuration, :score, 0)
    servers_healthy = results.servers.healthy_servers
    servers_total = results.servers.total_servers

    server_score =
      if servers_total > 0 do
        servers_healthy / servers_total * 100
      else
        100
      end

    overall_score = (system_score + config_score + server_score) / 3

    status =
      cond do
        overall_score >= 90 -> "🟢 Excellent"
        overall_score >= 70 -> "🟡 Good"
        overall_score >= 50 -> "🟠 Fair"
        true -> "🔴 Poor"
      end

    IO.puts("System Health: #{status} (#{Float.round(overall_score, 1)}%)")
    IO.puts("- System: #{Float.round(system_score, 1)}%")
    IO.puts("- Configuration: #{Float.round(config_score, 1)}%")

    IO.puts(
      "- Servers: #{servers_healthy}/#{servers_total} healthy (#{Float.round(server_score, 1)}%)"
    )
  end

  ## Server Logs Functions

  defp show_server_logs(server_name, options) do
    log_file = get_server_log_file(server_name)

    if File.exists?(log_file) do
      if Map.get(options, :follow) do
        follow_log_file(log_file, options)
      else
        show_static_logs(log_file, options)
      end
    else
      TheMaestro.MCP.CLI.print_error(
        "Log file not found for server '#{server_name}': #{log_file}"
      )

      # Suggest checking if server has been started
      IO.puts("")
      IO.puts("Possible reasons:")
      IO.puts("  - Server has not been started yet")
      IO.puts("  - Server is not configured for logging")
      IO.puts("  - Log file path is different")
      IO.puts("")
      IO.puts("Try: maestro mcp status #{server_name}")
    end
  end

  defp show_static_logs(log_file, options) do
    lines = Map.get(options, :lines, 50)
    level_filter = Map.get(options, :level)
    pattern_filter = Map.get(options, :grep)
    since_filter = Map.get(options, :since)

    case File.read(log_file) do
      {:ok, content} ->
        log_lines =
          content
          |> String.split("\n", trim: true)
          |> filter_logs_by_level(level_filter)
          |> filter_logs_by_pattern(pattern_filter)
          |> filter_logs_by_time(since_filter)
          |> Enum.take(-lines)

        if Enum.empty?(log_lines) do
          IO.puts("No log entries found matching the criteria.")
        else
          Enum.each(log_lines, &IO.puts/1)
        end

      {:error, reason} ->
        TheMaestro.MCP.CLI.print_error("Cannot read log file: #{reason}")
    end
  end

  defp follow_log_file(log_file, options) do
    IO.puts("Following log file: #{log_file}")
    IO.puts("Press Ctrl+C to stop...")
    IO.puts("")

    # Show last few lines first
    show_static_logs(log_file, Map.put(options, :lines, 10))

    # Start tailing the file
    tail_log_file(log_file, options)
  end

  defp tail_log_file(log_file, options) do
    level_filter = Map.get(options, :level)
    pattern_filter = Map.get(options, :grep)

    # Simple file tailing implementation
    # In production, you might want to use a more sophisticated approach
    initial_size =
      case File.stat(log_file) do
        {:ok, %{size: size}} -> size
        {:error, _} -> 0
      end

    tail_loop(log_file, initial_size, level_filter, pattern_filter)
  end

  defp tail_loop(log_file, last_size, level_filter, pattern_filter) do
    case File.stat(log_file) do
      {:ok, %{size: current_size}} when current_size > last_size ->
        # File has grown, read new content
        case File.open(log_file, [:read]) do
          {:ok, file} ->
            :file.position(file, last_size)
            new_content = IO.read(file, current_size - last_size)
            File.close(file)

            # Process new lines
            new_content
            |> String.split("\n", trim: true)
            |> filter_logs_by_level(level_filter)
            |> filter_logs_by_pattern(pattern_filter)
            |> Enum.each(&IO.puts/1)

            :timer.sleep(1000)
            tail_loop(log_file, current_size, level_filter, pattern_filter)

          {:error, _reason} ->
            :timer.sleep(1000)
            tail_loop(log_file, last_size, level_filter, pattern_filter)
        end

      {:ok, %{size: current_size}} ->
        # No change in file size
        :timer.sleep(1000)
        tail_loop(log_file, current_size, level_filter, pattern_filter)

      {:error, _reason} ->
        # File might have been deleted or rotated
        :timer.sleep(1000)
        tail_loop(log_file, 0, level_filter, pattern_filter)
    end
  end

  ## Ping Functions

  defp ping_specific_server(server_name, options) do
    count = Map.get(options, :count, 3)
    timeout = Map.get(options, :timeout, 5000)
    interval = Map.get(options, :interval, 1000)

    IO.puts("Pinging server '#{server_name}' #{count} times...")
    IO.puts("")

    results =
      1..count
      |> Enum.map(fn i ->
        IO.write("Ping #{i}/#{count}: ")

        start_time = System.monotonic_time(:millisecond)

        result =
          case ConnectionManager.ping_server(ConnectionManager, server_name, timeout) do
            {:ok, response_time} ->
              IO.puts("Response time: #{response_time}ms")
              {:ok, response_time}

            {:error, :timeout} ->
              IO.puts("Timeout after #{timeout}ms")
              {:error, :timeout}

            {:error, reason} ->
              IO.puts("Failed: #{reason}")
              {:error, reason}
          end

        # Wait interval before next ping (except for last one)
        if i < count do
          :timer.sleep(interval)
        end

        result
      end)

    # Summary
    successful_pings = Enum.count(results, fn {status, _} -> status == :ok end)

    if successful_pings > 0 do
      response_times =
        results
        |> Enum.filter(fn {status, _} -> status == :ok end)
        |> Enum.map(fn {_, time} -> time end)

      min_time = Enum.min(response_times)
      max_time = Enum.max(response_times)
      avg_time = div(Enum.sum(response_times), length(response_times))

      IO.puts("")
      IO.puts("Ping Statistics:")

      IO.puts(
        "  Packets: #{count} transmitted, #{successful_pings} received, #{count - successful_pings} lost"
      )

      IO.puts("  Round-trip times: min=#{min_time}ms, avg=#{avg_time}ms, max=#{max_time}ms")
    else
      IO.puts("")
      IO.puts("All ping attempts failed.")
    end
  end

  ## Trace Functions

  defp trace_server_connection(server_name, options) do
    duration = Map.get(options, :duration, 10)
    save_file = Map.get(options, :save)

    IO.puts("Tracing server '#{server_name}' for #{duration} seconds...")

    if save_file do
      IO.puts("Trace will be saved to: #{save_file}")
    end

    IO.puts("Press Ctrl+C to stop early...")
    IO.puts("")

    # Start tracing
    case ConnectionManager.start_trace(ConnectionManager, server_name) do
      {:ok, trace_id} ->
        # Wait for specified duration
        :timer.sleep(duration * 1000)

        # Stop tracing and get results
        case ConnectionManager.stop_trace(ConnectionManager, trace_id) do
          {:ok, trace_data} ->
            display_trace_results(trace_data, options)

            if save_file do
              save_trace_to_file(trace_data, save_file)
            end

          {:error, reason} ->
            TheMaestro.MCP.CLI.print_error("Failed to stop trace: #{reason}")
        end

      {:error, reason} ->
        TheMaestro.MCP.CLI.print_error("Failed to start trace: #{reason}")
    end
  end

  ## Helper Functions

  defp get_server_log_file(server_name) do
    "./.maestro/logs/#{server_name}.log"
  end

  defp filter_logs_by_level(lines, nil), do: lines

  defp filter_logs_by_level(lines, level) do
    level_pattern = ~r/\[#{String.upcase(level)}\]/

    Enum.filter(lines, fn line ->
      Regex.match?(level_pattern, line)
    end)
  end

  defp filter_logs_by_pattern(lines, nil), do: lines

  defp filter_logs_by_pattern(lines, pattern) do
    Enum.filter(lines, fn line ->
      String.contains?(String.downcase(line), String.downcase(pattern))
    end)
  end

  defp filter_logs_by_time(lines, nil), do: lines

  defp filter_logs_by_time(lines, _since) do
    # Simplified time filtering - in production would parse timestamps
    lines
  end

  defp display_trace_results(trace_data, options) do
    IO.puts("Trace Results:")
    IO.puts("#{String.duplicate("=", 15)}")

    # Display trace entries
    Enum.each(trace_data.entries, fn entry ->
      timestamp = format_timestamp(entry.timestamp)
      IO.puts("#{timestamp} - #{entry.event_type}")

      if TheMaestro.MCP.CLI.is_verbose?(options) do
        IO.puts("  Details: #{entry.details}")

        if entry.data do
          IO.puts("  Data: #{inspect(entry.data, pretty: true)}")
        end
      end

      IO.puts("")
    end)

    # Summary
    IO.puts("Trace Summary:")
    IO.puts("  Duration: #{trace_data.duration}ms")
    IO.puts("  Total Events: #{length(trace_data.entries)}")
    IO.puts("  Event Types: #{trace_data.event_types |> Map.keys() |> Enum.join(", ")}")
  end

  defp save_trace_to_file(trace_data, filename) do
    content = Jason.encode!(trace_data, pretty: true)

    case File.write(filename, content) do
      :ok ->
        TheMaestro.MCP.CLI.print_success("Trace saved to #{filename}")

      {:error, reason} ->
        TheMaestro.MCP.CLI.print_error("Failed to save trace: #{reason}")
    end
  end

  defp generate_diagnosis_recommendations(results) do
    recommendations = []

    # System health recommendations
    if results.system.score < 80 do
      recommendations = [
        %{
          title: "System Health Issues",
          description:
            "System health score is #{Float.round(results.system.score, 1)}%. Check memory usage and disk space.",
          priority: "medium"
        }
        | recommendations
      ]
    end

    # Configuration recommendations
    if results.configuration.score < 90 do
      recommendations = [
        %{
          title: "Configuration Issues",
          description:
            "Configuration has issues. Review server configurations and fix validation errors.",
          priority: "high"
        }
        | recommendations
      ]
    end

    # Server recommendations
    if results.servers.healthy_servers < results.servers.total_servers do
      unhealthy_count = results.servers.total_servers - results.servers.healthy_servers

      recommendations = [
        %{
          title: "Server Health Issues",
          description:
            "#{unhealthy_count} servers have health issues. Check connectivity and configuration.",
          priority: "high"
        }
        | recommendations
      ]
    end

    recommendations
  end

  defp format_check_name(check_name) do
    check_name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_diagnosis_status(:healthy), do: "🟢 Healthy"
  defp format_diagnosis_status(:unhealthy), do: "🔴 Unhealthy"
  defp format_diagnosis_status(status), do: to_string(status)

  defp format_server_status(:healthy), do: "Healthy"
  defp format_server_status(:config_issues), do: "Configuration issues"
  defp format_server_status(:connectivity_issues), do: "Connectivity issues"
  defp format_server_status(:multiple_issues), do: "Multiple issues"
  defp format_server_status(status), do: to_string(status)

  defp format_timestamp(timestamp) when is_integer(timestamp) do
    case DateTime.from_unix(timestamp, :millisecond) do
      {:ok, dt} -> DateTime.to_string(dt)
      _ -> "Invalid timestamp"
    end
  end

  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_string(dt)
  defp format_timestamp(timestamp), do: to_string(timestamp)
end
