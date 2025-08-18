defmodule TheMaestro.MCP.CLI.Commands.Metrics do
  @moduledoc """
  Metrics and performance monitoring commands for MCP CLI.

  Provides functionality to collect, analyze, and report on MCP server
  performance metrics, including response times, error rates, and usage statistics.
  """

  alias TheMaestro.MCP.{Config, ConnectionManager}
  alias TheMaestro.MCP.CLI
  alias TheMaestro.MCP.CLI.Formatters.YamlFormatter

  @doc """
  Show performance metrics for MCP servers.
  """
  def show_metrics(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case args do
      [] ->
        show_all_metrics(options)

      [server_name | _] ->
        show_server_metrics(server_name, options)
    end
  end

  @doc """
  Analyze performance patterns and bottlenecks.
  """
  def analyze_performance(args, options) do
    case args do
      [] ->
        analyze_global_performance(options)

      [server_name | _] ->
        analyze_server_performance(server_name, options)
    end
  end

  @doc """
  Show audit trail and security events.
  """
  def show_audit(args, options) do
    case args do
      [] ->
        show_global_audit_trail(options)

      [server_name | _] ->
        show_server_audit_trail(server_name, options)
    end
  end

  @doc """
  Generate comprehensive performance and usage reports.
  """
  def generate_report(args, options) do
    format = Map.get(options, :format, "text")
    output_file = Map.get(options, :output)

    case args do
      [] ->
        generate_global_report(format, output_file, options)

      [server_name | _] ->
        generate_server_report(server_name, format, output_file, options)
    end
  end

  @doc """
  Show help for the metrics command.
  """
  def show_help do
    IO.puts("""
    MCP Performance Metrics & Monitoring

    Usage:
      maestro mcp metrics [server] [OPTIONS]        # Show current metrics
      maestro mcp analyze [server] [OPTIONS]        # Performance analysis
      maestro mcp audit [server] [OPTIONS]          # Security audit trail
      maestro mcp report [server] [OPTIONS]         # Generate reports

    Metrics Options:
      --export <file>          Export metrics to file
      --slow-tools             Show tools with slow response times
      --error-rates            Focus on error rate analysis
      --format <format>        Output format (table, json, yaml)
      --verbose                Show detailed metrics

    Analysis Options:
      --timeframe <hours>      Analysis timeframe (default: 24 hours)
      --threshold <ms>         Performance threshold for alerts
      --top <n>                Show top N slowest operations

    Audit Options:
      --security               Security-focused audit trail
      --errors                 Error-focused audit trail
      --since <time>           Show events since specified time

    Report Options:
      --output <file>          Save report to file
      --include-graphs         Include performance graphs (if supported)
      --summary-only           Generate summary report only

    Examples:
      maestro mcp metrics                           # Show all server metrics
      maestro mcp metrics myServer --verbose        # Detailed server metrics
      maestro mcp analyze --slow-tools              # Analyze slow tools
      maestro mcp audit --security                  # Security audit trail
      maestro mcp report --output metrics.json      # Export metrics report
    """)
  end

  ## Private Functions - Metrics Display

  defp show_all_metrics(options) do
    CLI.print_if_verbose("Collecting metrics for all servers...", options)

    case Config.get_configuration() do
      {:ok, config} ->
        case get_in(config, ["mcpServers"]) do
          servers when is_map(servers) and map_size(servers) > 0 ->
            metrics_data = collect_all_server_metrics(servers, options)
            display_metrics_overview(metrics_data, options)

          _ ->
            CLI.print_info("No MCP servers configured.")
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp show_server_metrics(server_name, options) do
    CLI.print_if_verbose(
      "Collecting metrics for server '#{server_name}'...",
      options
    )

    case Config.get_configuration() do
      {:ok, config} ->
        case get_in(config, ["mcpServers", server_name]) do
          nil ->
            CLI.print_error("Server '#{server_name}' not found.")

          server_config ->
            metrics = collect_server_metrics(server_name, server_config, options)
            display_detailed_server_metrics(server_name, metrics, options)
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp collect_all_server_metrics(servers, options) do
    servers
    |> Enum.map(fn {server_id, server_config} ->
      metrics = collect_server_metrics(server_id, server_config, options)
      {server_id, metrics}
    end)
    |> Enum.into(%{})
  end

  defp collect_server_metrics(server_id, server_config, options) do
    base_metrics = %{
      server_id: server_id,
      transport: detect_transport_type(server_config),
      collected_at: DateTime.utc_now()
    }

    # Get connection metrics
    connection_metrics = get_connection_metrics(server_id)

    # Get performance metrics
    performance_metrics = get_performance_metrics(server_id, options)

    # Get tool usage metrics
    tool_metrics = get_tool_usage_metrics(server_id, options)

    # Get error metrics
    error_metrics = get_error_metrics(server_id, options)

    Map.merge(base_metrics, %{
      connection: connection_metrics,
      performance: performance_metrics,
      tools: tool_metrics,
      errors: error_metrics
    })
  end

  defp get_connection_metrics(server_id) do
    case ConnectionManager.get_connection_metrics(ConnectionManager, server_id) do
      {:ok, metrics} ->
        %{
          status: Map.get(metrics, :status, :unknown),
          uptime_seconds: Map.get(metrics, :uptime_seconds, 0),
          total_connections: Map.get(metrics, :total_connections, 0),
          connection_failures: Map.get(metrics, :connection_failures, 0),
          last_heartbeat: Map.get(metrics, :last_heartbeat),
          average_response_time: Map.get(metrics, :average_response_time, 0)
        }

      {:error, _reason} ->
        %{
          status: :not_connected,
          uptime_seconds: 0,
          total_connections: 0,
          connection_failures: 0,
          last_heartbeat: nil,
          average_response_time: 0
        }
    end
  end

  defp get_performance_metrics(server_id, options) do
    timeframe_hours = Map.get(options, :timeframe, 24)

    case ConnectionManager.get_performance_metrics(ConnectionManager, server_id, timeframe_hours) do
      {:ok, metrics} ->
        %{
          total_requests: Map.get(metrics, :total_requests, 0),
          successful_requests: Map.get(metrics, :successful_requests, 0),
          failed_requests: Map.get(metrics, :failed_requests, 0),
          average_response_time: Map.get(metrics, :average_response_time, 0),
          median_response_time: Map.get(metrics, :median_response_time, 0),
          p95_response_time: Map.get(metrics, :p95_response_time, 0),
          p99_response_time: Map.get(metrics, :p99_response_time, 0),
          throughput_rpm: Map.get(metrics, :throughput_rpm, 0)
        }

      {:error, _reason} ->
        %{
          total_requests: 0,
          successful_requests: 0,
          failed_requests: 0,
          average_response_time: 0,
          median_response_time: 0,
          p95_response_time: 0,
          p99_response_time: 0,
          throughput_rpm: 0
        }
    end
  end

  defp get_tool_usage_metrics(server_id, options) do
    timeframe_hours = Map.get(options, :timeframe, 24)

    case ConnectionManager.get_tool_usage_metrics(ConnectionManager, server_id, timeframe_hours) do
      {:ok, metrics} ->
        %{
          total_tool_calls: Map.get(metrics, :total_tool_calls, 0),
          unique_tools_used: Map.get(metrics, :unique_tools_used, 0),
          most_used_tools: Map.get(metrics, :most_used_tools, []),
          slowest_tools: Map.get(metrics, :slowest_tools, []),
          tool_success_rate: Map.get(metrics, :tool_success_rate, 0.0)
        }

      {:error, _reason} ->
        %{
          total_tool_calls: 0,
          unique_tools_used: 0,
          most_used_tools: [],
          slowest_tools: [],
          tool_success_rate: 0.0
        }
    end
  end

  defp get_error_metrics(server_id, options) do
    timeframe_hours = Map.get(options, :timeframe, 24)

    case ConnectionManager.get_error_metrics(ConnectionManager, server_id, timeframe_hours) do
      {:ok, metrics} ->
        %{
          total_errors: Map.get(metrics, :total_errors, 0),
          error_rate: Map.get(metrics, :error_rate, 0.0),
          error_types: Map.get(metrics, :error_types, %{}),
          recent_errors: Map.get(metrics, :recent_errors, [])
        }

      {:error, _reason} ->
        %{
          total_errors: 0,
          error_rate: 0.0,
          error_types: %{},
          recent_errors: []
        }
    end
  end

  defp display_metrics_overview(metrics_data, options) do
    format = CLI.get_output_format(options)

    case format do
      "json" ->
        output = Jason.encode!(metrics_data, pretty: true)
        IO.puts(output)

      "yaml" ->
        output = YamlFormatter.format(metrics_data)
        IO.puts(output)

      _ ->
        display_metrics_table(metrics_data, options)
    end

    # Export if requested
    if export_file = Map.get(options, :export) do
      export_metrics(metrics_data, export_file, options)
    end
  end

  defp display_metrics_table(metrics_data, options) do
    if Enum.empty?(metrics_data) do
      CLI.print_info("No metrics data available.")
      {:ok, :no_data}
    end

    IO.puts("MCP Server Metrics Overview")
    IO.puts("#{String.duplicate("=", 40)}")
    IO.puts("")

    # Summary table
    headers = ["Server", "Status", "Uptime", "Requests", "Avg Response", "Error Rate"]

    rows =
      metrics_data
      |> Enum.map(fn {server_id, metrics} ->
        [
          server_id,
          format_connection_status(metrics.connection.status),
          format_uptime(metrics.connection.uptime_seconds),
          metrics.performance.total_requests,
          "#{metrics.performance.average_response_time}ms",
          "#{Float.round(metrics.errors.error_rate * 100, 1)}%"
        ]
      end)

    display_simple_table(headers, rows)

    # Show problematic servers if any
    show_performance_alerts(metrics_data, options)

    unless CLI.quiet?(options) do
      show_metrics_summary(metrics_data)
    end
  end

  defp display_detailed_server_metrics(server_name, metrics, options) do
    IO.puts("")
    IO.puts("Detailed Metrics: #{server_name}")
    IO.puts("#{String.duplicate("=", String.length("Detailed Metrics: #{server_name}"))}")
    IO.puts("")

    # Connection metrics
    IO.puts("Connection Metrics:")
    IO.puts("  Status: #{format_connection_status(metrics.connection.status)}")
    IO.puts("  Uptime: #{format_uptime(metrics.connection.uptime_seconds)}")
    IO.puts("  Total Connections: #{metrics.connection.total_connections}")
    IO.puts("  Connection Failures: #{metrics.connection.connection_failures}")

    if metrics.connection.last_heartbeat do
      IO.puts("  Last Heartbeat: #{format_timestamp(metrics.connection.last_heartbeat)}")
    end

    IO.puts("")

    # Performance metrics
    IO.puts("Performance Metrics:")
    IO.puts("  Total Requests: #{metrics.performance.total_requests}")
    IO.puts("  Successful: #{metrics.performance.successful_requests}")
    IO.puts("  Failed: #{metrics.performance.failed_requests}")
    IO.puts("  Average Response Time: #{metrics.performance.average_response_time}ms")
    IO.puts("  Median Response Time: #{metrics.performance.median_response_time}ms")
    IO.puts("  95th Percentile: #{metrics.performance.p95_response_time}ms")
    IO.puts("  99th Percentile: #{metrics.performance.p99_response_time}ms")
    IO.puts("  Throughput: #{metrics.performance.throughput_rpm} req/min")

    IO.puts("")

    # Tool metrics
    IO.puts("Tool Usage Metrics:")
    IO.puts("  Total Tool Calls: #{metrics.tools.total_tool_calls}")
    IO.puts("  Unique Tools Used: #{metrics.tools.unique_tools_used}")
    IO.puts("  Tool Success Rate: #{Float.round(metrics.tools.tool_success_rate * 100, 1)}%")

    unless Enum.empty?(metrics.tools.most_used_tools) do
      IO.puts("  Most Used Tools:")

      Enum.take(metrics.tools.most_used_tools, 5)
      |> Enum.each(fn {tool, count} ->
        IO.puts("    #{tool}: #{count} calls")
      end)
    end

    if Map.get(options, :slow_tools) and not Enum.empty?(metrics.tools.slowest_tools) do
      IO.puts("  Slowest Tools:")

      Enum.take(metrics.tools.slowest_tools, 5)
      |> Enum.each(fn {tool, avg_time} ->
        IO.puts("    #{tool}: #{avg_time}ms avg")
      end)
    end

    IO.puts("")

    # Error metrics
    IO.puts("Error Metrics:")
    IO.puts("  Total Errors: #{metrics.errors.total_errors}")
    IO.puts("  Error Rate: #{Float.round(metrics.errors.error_rate * 100, 2)}%")

    unless Enum.empty?(metrics.errors.error_types) do
      IO.puts("  Error Types:")

      Enum.each(metrics.errors.error_types, fn {error_type, count} ->
        IO.puts("    #{error_type}: #{count}")
      end)
    end

    if CLI.verbose?(options) and not Enum.empty?(metrics.errors.recent_errors) do
      IO.puts("  Recent Errors:")

      Enum.take(metrics.errors.recent_errors, 3)
      |> Enum.each(fn error ->
        IO.puts(
          "    #{format_timestamp(Map.get(error, :timestamp))}: #{Map.get(error, :message)}"
        )
      end)
    end

    IO.puts("")
  end

  defp show_performance_alerts(metrics_data, options) do
    # 5 second default threshold
    threshold = Map.get(options, :threshold, 5000)

    slow_servers =
      metrics_data
      |> Enum.filter(fn {_server_id, metrics} ->
        metrics.performance.average_response_time > threshold
      end)

    high_error_servers =
      metrics_data
      |> Enum.filter(fn {_server_id, metrics} ->
        # 5% error rate threshold
        metrics.errors.error_rate > 0.05
      end)

    if not Enum.empty?(slow_servers) do
      IO.puts("")
      IO.puts("⚠️  Performance Alerts:")

      Enum.each(slow_servers, fn {server_id, metrics} ->
        IO.puts(
          "  #{server_id}: Slow response time (#{metrics.performance.average_response_time}ms)"
        )
      end)
    end

    if not Enum.empty?(high_error_servers) do
      IO.puts("")
      IO.puts("🔴 Error Rate Alerts:")

      Enum.each(high_error_servers, fn {server_id, metrics} ->
        IO.puts(
          "  #{server_id}: High error rate (#{Float.round(metrics.errors.error_rate * 100, 1)}%)"
        )
      end)
    end
  end

  defp show_metrics_summary(metrics_data) do
    total_servers = map_size(metrics_data)

    connected_servers =
      Enum.count(metrics_data, fn {_id, metrics} ->
        metrics.connection.status == :connected
      end)

    total_requests =
      Enum.reduce(metrics_data, 0, fn {_id, metrics}, acc ->
        acc + metrics.performance.total_requests
      end)

    total_errors =
      Enum.reduce(metrics_data, 0, fn {_id, metrics}, acc ->
        acc + metrics.errors.total_errors
      end)

    overall_error_rate =
      if total_requests > 0 do
        total_errors / total_requests * 100
      else
        0.0
      end

    IO.puts("")
    IO.puts("Summary:")
    IO.puts("  Total Servers: #{total_servers}")
    IO.puts("  Connected: #{connected_servers}")
    IO.puts("  Total Requests: #{total_requests}")
    IO.puts("  Overall Error Rate: #{Float.round(overall_error_rate, 2)}%")
  end

  ## Private Functions - Performance Analysis

  defp analyze_global_performance(options) do
    CLI.print_if_verbose("Analyzing global performance patterns...", options)

    case Config.get_configuration() do
      {:ok, config} ->
        servers = get_in(config, ["mcpServers"]) || %{}

        if map_size(servers) > 0 do
          analysis = perform_global_performance_analysis(servers, options)
          display_performance_analysis(analysis, options)
        else
          CLI.print_info("No servers configured for analysis.")
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp analyze_server_performance(server_name, options) do
    CLI.print_if_verbose(
      "Analyzing performance for server '#{server_name}'...",
      options
    )

    case Config.get_configuration() do
      {:ok, config} ->
        case get_in(config, ["mcpServers", server_name]) do
          nil ->
            CLI.print_error("Server '#{server_name}' not found.")

          server_config ->
            analysis = perform_server_performance_analysis(server_name, server_config, options)
            display_server_performance_analysis(server_name, analysis, options)
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp perform_global_performance_analysis(servers, options) do
    timeframe_hours = Map.get(options, :timeframe, 24)

    # Collect performance data for all servers
    server_performances =
      servers
      |> Enum.map(fn {server_id, server_config} ->
        metrics = collect_server_metrics(server_id, server_config, options)
        {server_id, metrics}
      end)
      |> Enum.into(%{})

    # Analyze patterns
    %{
      timeframe_hours: timeframe_hours,
      total_servers: map_size(servers),
      connected_servers: count_connected_servers(server_performances),
      performance_summary: calculate_performance_summary(server_performances),
      bottlenecks: identify_bottlenecks(server_performances, options),
      trends: analyze_performance_trends(server_performances, options),
      recommendations: generate_performance_recommendations(server_performances, options)
    }
  end

  defp perform_server_performance_analysis(server_id, server_config, options) do
    metrics = collect_server_metrics(server_id, server_config, options)

    %{
      server_id: server_id,
      metrics: metrics,
      bottlenecks: identify_server_bottlenecks(metrics, options),
      trends: analyze_server_trends(server_id, options),
      recommendations: generate_server_recommendations(metrics, options)
    }
  end

  defp display_performance_analysis(analysis, _options) do
    IO.puts("Global Performance Analysis")
    IO.puts("#{String.duplicate("=", 35)}")
    IO.puts("")

    IO.puts("Overview:")
    IO.puts("  Analysis Period: #{analysis.timeframe_hours} hours")
    IO.puts("  Total Servers: #{analysis.total_servers}")
    IO.puts("  Connected Servers: #{analysis.connected_servers}")
    IO.puts("")

    # Performance summary
    summary = analysis.performance_summary
    IO.puts("Performance Summary:")
    IO.puts("  Total Requests: #{summary.total_requests}")
    IO.puts("  Average Response Time: #{summary.average_response_time}ms")
    IO.puts("  Success Rate: #{Float.round(summary.success_rate * 100, 1)}%")
    IO.puts("  Throughput: #{summary.total_throughput} req/min")
    IO.puts("")

    # Bottlenecks
    unless Enum.empty?(analysis.bottlenecks) do
      IO.puts("Identified Bottlenecks:")

      Enum.each(analysis.bottlenecks, fn bottleneck ->
        IO.puts("  ⚠️  #{bottleneck.server_id}: #{bottleneck.issue} (#{bottleneck.severity})")

        if bottleneck.details do
          IO.puts("      #{bottleneck.details}")
        end
      end)

      IO.puts("")
    end

    # Recommendations
    unless Enum.empty?(analysis.recommendations) do
      IO.puts("Performance Recommendations:")

      Enum.each(analysis.recommendations, fn rec ->
        IO.puts("  💡 #{rec.title}")
        IO.puts("     #{rec.description}")

        if rec.priority do
          IO.puts("     Priority: #{rec.priority}")
        end
      end)
    end
  end

  defp display_server_performance_analysis(server_name, analysis, _options) do
    IO.puts("")
    IO.puts("Performance Analysis: #{server_name}")
    IO.puts("#{String.duplicate("=", String.length("Performance Analysis: #{server_name}"))}")
    IO.puts("")

    metrics = analysis.metrics

    IO.puts("Current Performance:")
    IO.puts("  Status: #{format_connection_status(metrics.connection.status)}")
    IO.puts("  Average Response Time: #{metrics.performance.average_response_time}ms")
    IO.puts("  Success Rate: #{calculate_success_rate(metrics.performance)}%")
    IO.puts("  Throughput: #{metrics.performance.throughput_rpm} req/min")
    IO.puts("")

    # Bottlenecks
    unless Enum.empty?(analysis.bottlenecks) do
      IO.puts("Bottlenecks:")

      Enum.each(analysis.bottlenecks, fn bottleneck ->
        IO.puts("  ⚠️  #{bottleneck.issue}")

        if bottleneck.details do
          IO.puts("     #{bottleneck.details}")
        end
      end)

      IO.puts("")
    end

    # Recommendations
    unless Enum.empty?(analysis.recommendations) do
      IO.puts("Recommendations:")

      Enum.each(analysis.recommendations, fn rec ->
        IO.puts("  💡 #{rec.title}")
        IO.puts("     #{rec.description}")
      end)
    end

    IO.puts("")
  end

  ## Private Functions - Audit Trail

  defp show_global_audit_trail(options) do
    IO.puts("Global Audit Trail")
    IO.puts("#{String.duplicate("=", 25)}")

    # Implementation would collect audit events from all servers
    CLI.print_info("Audit trail functionality - collecting events...")

    # Placeholder for audit events
    events = []

    if Enum.empty?(events) do
      IO.puts("No audit events found.")
    else
      display_audit_events(events, options)
    end
  end

  defp show_server_audit_trail(server_name, options) do
    IO.puts("Audit Trail: #{server_name}")
    IO.puts("#{String.duplicate("=", String.length("Audit Trail: #{server_name}"))}")

    # Implementation would collect audit events for specific server
    CLI.print_info("Server audit trail functionality - collecting events...")

    # Placeholder for server-specific audit events
    events = []

    if Enum.empty?(events) do
      IO.puts("No audit events found for server '#{server_name}'.")
    else
      display_audit_events(events, options)
    end
  end

  defp display_audit_events(events, options) do
    # Display audit events in table or detailed format
    if CLI.verbose?(options) do
      Enum.each(events, fn event ->
        display_detailed_audit_event(event)
      end)
    else
      display_audit_events_table(events)
    end
  end

  defp display_detailed_audit_event(event) do
    IO.puts("#{format_timestamp(event.timestamp)} - #{event.event_type}")
    IO.puts("  Server: #{event.server_id}")
    IO.puts("  Details: #{event.details}")
    if event.user, do: IO.puts("  User: #{event.user}")
    IO.puts("")
  end

  defp display_audit_events_table(events) do
    headers = ["Time", "Server", "Event Type", "Details"]

    rows =
      Enum.map(events, fn event ->
        [
          format_timestamp(event.timestamp),
          event.server_id,
          event.event_type,
          truncate_text(event.details, 40)
        ]
      end)

    display_simple_table(headers, rows)
  end

  ## Private Functions - Report Generation

  defp generate_global_report(format, output_file, options) do
    CLI.print_if_verbose("Generating global performance report...", options)

    case Config.get_configuration() do
      {:ok, config} ->
        servers = get_in(config, ["mcpServers"]) || %{}

        report_data = compile_global_report_data(servers, options)

        content =
          case format do
            "json" ->
              Jason.encode!(report_data, pretty: true)

            "yaml" ->
              YamlFormatter.format(report_data)

            _ ->
              format_text_report(report_data, options)
          end

        if output_file do
          case File.write(output_file, content) do
            :ok ->
              CLI.print_success("Report saved to #{output_file}")

            {:error, reason} ->
              CLI.print_error("Failed to save report: #{reason}")
          end
        else
          IO.puts(content)
        end

      {:error, reason} ->
        CLI.print_error("Failed to generate report: #{reason}")
    end
  end

  defp generate_server_report(server_name, format, output_file, options) do
    CLI.print_if_verbose(
      "Generating report for server '#{server_name}'...",
      options
    )

    case Config.get_configuration() do
      {:ok, config} ->
        case get_in(config, ["mcpServers", server_name]) do
          nil ->
            CLI.print_error("Server '#{server_name}' not found.")

          server_config ->
            report_data = compile_server_report_data(server_name, server_config, options)

            content =
              case format do
                "json" ->
                  Jason.encode!(report_data, pretty: true)

                "yaml" ->
                  YamlFormatter.format(report_data)

                _ ->
                  format_server_text_report(report_data, options)
              end

            if output_file do
              case File.write(output_file, content) do
                :ok ->
                  CLI.print_success("Report saved to #{output_file}")

                {:error, reason} ->
                  CLI.print_error("Failed to save report: #{reason}")
              end
            else
              IO.puts(content)
            end
        end

      {:error, reason} ->
        CLI.print_error("Failed to generate report: #{reason}")
    end
  end

  defp compile_global_report_data(servers, options) do
    %{
      report_type: "global_performance_report",
      generated_at: DateTime.utc_now(),
      timeframe_hours: Map.get(options, :timeframe, 24),
      servers: collect_all_server_metrics(servers, options),
      summary: calculate_global_summary(servers, options)
    }
  end

  defp compile_server_report_data(server_name, server_config, options) do
    metrics = collect_server_metrics(server_name, server_config, options)

    %{
      report_type: "server_performance_report",
      server_name: server_name,
      generated_at: DateTime.utc_now(),
      timeframe_hours: Map.get(options, :timeframe, 24),
      metrics: metrics,
      analysis: perform_server_performance_analysis(server_name, server_config, options)
    }
  end

  defp format_text_report(report_data, options) do
    """
    MCP Performance Report
    =====================
    Generated: #{DateTime.to_string(report_data.generated_at)}
    Timeframe: #{report_data.timeframe_hours} hours

    #{format_report_summary(report_data.summary)}

    Server Details:
    #{format_server_details(report_data.servers, options)}
    """
  end

  defp format_server_text_report(report_data, options) do
    """
    MCP Server Performance Report
    =============================
    Server: #{report_data.server_name}
    Generated: #{DateTime.to_string(report_data.generated_at)}
    Timeframe: #{report_data.timeframe_hours} hours

    #{format_single_server_report(report_data.metrics, report_data.analysis, options)}
    """
  end

  ## Helper Functions

  defp detect_transport_type(server_config) do
    cond do
      Map.has_key?(server_config, "command") -> "stdio"
      Map.has_key?(server_config, "url") -> "sse"
      Map.has_key?(server_config, "httpUrl") -> "http"
      true -> "unknown"
    end
  end

  defp format_connection_status(:connected), do: "🟢 Connected"
  defp format_connection_status(:connecting), do: "🟡 Connecting"
  defp format_connection_status(:disconnected), do: "🔴 Disconnected"
  defp format_connection_status(:not_connected), do: "⚫ Not Connected"
  defp format_connection_status(:error), do: "🔴 Error"
  defp format_connection_status(_), do: "Unknown"

  defp format_uptime(0), do: "0s"

  defp format_uptime(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
      true -> "#{div(seconds, 86_400)}d #{div(rem(seconds, 86_400), 3600)}h"
    end
  end

  defp format_timestamp(nil), do: "Never"

  defp format_timestamp(timestamp) when is_integer(timestamp) do
    case DateTime.from_unix(timestamp, :millisecond) do
      {:ok, dt} -> DateTime.to_string(dt)
      _ -> "Invalid"
    end
  end

  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_string(dt)
  defp format_timestamp(timestamp), do: to_string(timestamp)

  defp truncate_text(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      text
    end
  end

  defp truncate_text(text, _max_length), do: to_string(text)

  defp export_metrics(metrics_data, filename, _options) do
    format = Path.extname(filename) |> String.trim_leading(".") |> String.downcase()

    content =
      case format do
        "json" ->
          Jason.encode!(metrics_data, pretty: true)

        "yaml" ->
          YamlFormatter.format(metrics_data)

        _ ->
          # Default to JSON
          Jason.encode!(metrics_data, pretty: true)
      end

    case File.write(filename, content) do
      :ok ->
        CLI.print_success("Metrics exported to #{filename}")

      {:error, reason} ->
        CLI.print_error("Failed to export metrics: #{reason}")
    end
  end

  # Analysis helper functions
  defp count_connected_servers(server_performances) do
    Enum.count(server_performances, fn {_id, metrics} ->
      metrics.connection.status == :connected
    end)
  end

  defp calculate_performance_summary(server_performances) do
    all_metrics = Map.values(server_performances)

    %{
      total_requests: Enum.reduce(all_metrics, 0, &(&1.performance.total_requests + &2)),
      average_response_time: calculate_avg_response_time(all_metrics),
      success_rate: calculate_overall_success_rate(all_metrics),
      total_throughput: Enum.reduce(all_metrics, 0, &(&1.performance.throughput_rpm + &2))
    }
  end

  defp calculate_avg_response_time(metrics_list) do
    if Enum.empty?(metrics_list) do
      0
    else
      total = Enum.reduce(metrics_list, 0, &(&1.performance.average_response_time + &2))
      div(total, length(metrics_list))
    end
  end

  defp calculate_overall_success_rate(metrics_list) do
    total_requests = Enum.reduce(metrics_list, 0, &(&1.performance.total_requests + &2))
    successful_requests = Enum.reduce(metrics_list, 0, &(&1.performance.successful_requests + &2))

    if total_requests > 0 do
      successful_requests / total_requests
    else
      0.0
    end
  end

  defp calculate_success_rate(performance_metrics) do
    total = performance_metrics.total_requests
    successful = performance_metrics.successful_requests

    if total > 0 do
      Float.round(successful / total * 100, 1)
    else
      0.0
    end
  end

  defp identify_bottlenecks(server_performances, options) do
    threshold = Map.get(options, :threshold, 5000)

    server_performances
    |> Enum.filter(fn {_id, metrics} ->
      metrics.performance.average_response_time > threshold or
        metrics.errors.error_rate > 0.05
    end)
    |> Enum.map(fn {server_id, metrics} ->
      cond do
        metrics.performance.average_response_time > threshold ->
          %{
            server_id: server_id,
            issue: "High response time",
            severity: "high",
            details: "#{metrics.performance.average_response_time}ms avg response time"
          }

        metrics.errors.error_rate > 0.05 ->
          %{
            server_id: server_id,
            issue: "High error rate",
            severity: "medium",
            details: "#{Float.round(metrics.errors.error_rate * 100, 1)}% error rate"
          }

        true ->
          nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp identify_server_bottlenecks(metrics, options) do
    threshold = Map.get(options, :threshold, 5000)
    bottlenecks = []

    bottlenecks =
      if metrics.performance.average_response_time > threshold do
        [
          %{
            issue: "High average response time",
            details: "#{metrics.performance.average_response_time}ms (threshold: #{threshold}ms)"
          }
          | bottlenecks
        ]
      else
        bottlenecks
      end

    bottlenecks =
      if metrics.errors.error_rate > 0.05 do
        [
          %{
            issue: "High error rate",
            details: "#{Float.round(metrics.errors.error_rate * 100, 1)}% (threshold: 5%)"
          }
          | bottlenecks
        ]
      else
        bottlenecks
      end

    bottlenecks
  end

  defp analyze_performance_trends(_server_performances, _options) do
    # Placeholder for trend analysis
    []
  end

  defp analyze_server_trends(_server_id, _options) do
    # Placeholder for server-specific trend analysis
    []
  end

  defp generate_performance_recommendations(server_performances, _options) do
    recommendations = []

    # Add recommendations based on analysis
    slow_servers =
      Enum.filter(server_performances, fn {_id, metrics} ->
        metrics.performance.average_response_time > 3000
      end)

    recommendations =
      if not Enum.empty?(slow_servers) do
        [
          %{
            title: "Optimize slow servers",
            description:
              "#{length(slow_servers)} servers have response times >3s. Consider increasing timeout, optimizing commands, or checking network connectivity.",
            priority: "high"
          }
          | recommendations
        ]
      else
        recommendations
      end

    high_error_servers =
      Enum.filter(server_performances, fn {_id, metrics} ->
        metrics.errors.error_rate > 0.05
      end)

    recommendations =
      if not Enum.empty?(high_error_servers) do
        [
          %{
            title: "Address error rates",
            description:
              "#{length(high_error_servers)} servers have error rates >5%. Review server logs and check configurations.",
            priority: "medium"
          }
          | recommendations
        ]
      else
        recommendations
      end

    recommendations
  end

  defp generate_server_recommendations(metrics, _options) do
    recommendations = []

    recommendations =
      if metrics.performance.average_response_time > 3000 do
        [
          %{
            title: "Optimize response time",
            description:
              "Average response time is #{metrics.performance.average_response_time}ms. Consider optimizing server command or increasing timeout."
          }
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if metrics.errors.error_rate > 0.05 do
        [
          %{
            title: "Reduce error rate",
            description:
              "Error rate is #{Float.round(metrics.errors.error_rate * 100, 1)}%. Check server logs and configuration."
          }
          | recommendations
        ]
      else
        recommendations
      end

    recommendations
  end

  defp calculate_global_summary(servers, options) do
    metrics_data = collect_all_server_metrics(servers, options)
    calculate_performance_summary(metrics_data)
  end

  defp format_report_summary(summary) do
    """
    Summary:
      Total Requests: #{summary.total_requests}
      Average Response Time: #{summary.average_response_time}ms
      Success Rate: #{Float.round(summary.success_rate * 100, 1)}%
      Total Throughput: #{summary.total_throughput} req/min
    """
  end

  defp format_server_details(servers, _options) do
    servers
    |> Enum.map(fn {server_id, metrics} ->
      """
      #{server_id}:
        Status: #{format_connection_status(metrics.connection.status)}
        Requests: #{metrics.performance.total_requests}
        Avg Response: #{metrics.performance.average_response_time}ms
        Error Rate: #{Float.round(metrics.errors.error_rate * 100, 1)}%
      """
    end)
    |> Enum.join("\n")
  end

  defp format_single_server_report(metrics, analysis, _options) do
    """
    Performance Metrics:
      Total Requests: #{metrics.performance.total_requests}
      Average Response Time: #{metrics.performance.average_response_time}ms
      Success Rate: #{calculate_success_rate(metrics.performance)}%
      Error Rate: #{Float.round(metrics.errors.error_rate * 100, 1)}%
      
    #{format_analysis_section(analysis)}
    """
  end

  defp format_analysis_section(analysis) do
    bottlenecks_text =
      if Enum.empty?(analysis.bottlenecks) do
        "No performance bottlenecks identified."
      else
        "Bottlenecks:\n" <>
          Enum.map_join(analysis.bottlenecks, "\n", fn b ->
            "  - #{b.issue}: #{b.details}"
          end)
      end

    recommendations_text =
      if Enum.empty?(analysis.recommendations) do
        "No specific recommendations."
      else
        "Recommendations:\n" <>
          Enum.map_join(analysis.recommendations, "\n", fn r ->
            "  - #{r.title}: #{r.description}"
          end)
      end

    bottlenecks_text <> "\n\n" <> recommendations_text
  end

  defp display_simple_table(headers, rows) do
    # Calculate column widths
    col_widths = calculate_column_widths(headers, rows)

    # Print headers
    header_line =
      headers
      |> Enum.with_index()
      |> Enum.map(fn {header, idx} ->
        String.pad_trailing(header, Enum.at(col_widths, idx))
      end)
      |> Enum.join(" | ")

    IO.puts(header_line)

    # Print separator
    separator =
      col_widths
      |> Enum.map(&String.duplicate("-", &1))
      |> Enum.join("-|-")

    IO.puts(separator)

    # Print rows
    Enum.each(rows, fn row ->
      row_line =
        row
        |> Enum.with_index()
        |> Enum.map(fn {cell, idx} ->
          String.pad_trailing(to_string(cell), Enum.at(col_widths, idx))
        end)
        |> Enum.join(" | ")

      IO.puts(row_line)
    end)
  end

  defp calculate_column_widths(headers, rows) do
    all_rows = [headers | rows]

    if Enum.empty?(all_rows) do
      []
    else
      num_cols = length(hd(all_rows))

      for col_idx <- 0..(num_cols - 1) do
        all_rows
        |> Enum.map(&Enum.at(&1, col_idx, ""))
        |> Enum.map(&String.length(to_string(&1)))
        |> Enum.max()
        # Minimum column width
        |> max(10)
      end
    end
  end
end
