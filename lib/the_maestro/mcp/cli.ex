defmodule TheMaestro.MCP.CLI do
  @moduledoc """
  Main entry point for MCP CLI commands.

  This module provides the command-line interface for managing MCP servers,
  including server management, tool management, authentication, monitoring,
  and diagnostic commands.

  ## Available Commands

  ### Server Management
  - `maestro mcp list` - List all configured servers
  - `maestro mcp add` - Add new MCP server
  - `maestro mcp update` - Update server configuration
  - `maestro mcp remove` - Remove MCP server

  ### Server Status & Monitoring
  - `maestro mcp status` - Show server status
  - `maestro mcp test` - Test server connections
  - `maestro mcp health` - Health monitoring

  ### Tool Management
  - `maestro mcp tools` - List available tools
  - `maestro mcp run` - Execute tool
  - `maestro mcp debug` - Debug tool execution
  - `maestro mcp trace` - Full execution trace

  ### Authentication & Security
  - `maestro mcp auth` - Authentication management
  - `maestro mcp apikey` - API key management
  - `maestro mcp trust` - Trust management

  ### Monitoring & Diagnostics
  - `maestro mcp metrics` - Performance metrics
  - `maestro mcp analyze` - Performance analysis
  - `maestro mcp diagnose` - System diagnosis
  - `maestro mcp logs` - View server logs

  ### Configuration Management
  - `maestro mcp discover` - Auto-discover servers
  - `maestro mcp template` - Template management
  - `maestro mcp export` - Export configurations
  - `maestro mcp import` - Import configurations

  ### Interactive Tools
  - `maestro mcp setup` - Interactive setup wizard
  - `maestro mcp configure` - Interactive server configuration
  """

  alias TheMaestro.MCP.CLI.Commands.{
    List,
    Add,
    Remove,
    Update,
    Status,
    Tools,
    Auth,
    Trust,
    Metrics,
    Diagnostics,
    Discovery,
    Templates,
    ImportExport,
    Setup,
    Interactive
  }

  alias TheMaestro.MCP.CLI.Formatters.{TableFormatter, JsonFormatter, YamlFormatter}

  @doc """
  Main entry point for CLI commands.

  Parses arguments and dispatches to appropriate command modules.
  """
  def main(args) do
    case parse_args(args) do
      {command, subcommand, options} ->
        execute_command(command, subcommand, options)

      {:ok, :help} ->
        :ok

      {:ok, :version} ->
        :ok

      {:error, reason} ->
        print_error(reason)
        System.halt(1)
    end
  rescue
    error ->
      print_error("Unexpected error: #{Exception.message(error)}")
      System.halt(1)
  end

  @doc """
  Parse command line arguments.

  Returns {command, subcommand, options} tuple or {:error, reason}.
  """
  def parse_args(args) do
    case args do
      ["mcp" | mcp_args] ->
        parse_mcp_command(mcp_args)

      ["--help"] ->
        show_help()
        {:ok, :help}

      ["--version"] ->
        show_version()
        {:ok, :version}

      [] ->
        show_help()
        {:ok, :help}

      _ ->
        {:error, "Unknown command. Use --help for usage information."}
    end
  end

  defp parse_mcp_command(args) do
    case args do
      [] ->
        show_mcp_help()
        {:ok, :help}

      ["--help"] ->
        show_mcp_help()
        {:ok, :help}

      [subcommand | rest] ->
        {options, remaining_args} = parse_options(rest)
        {:mcp, subcommand, %{options: options, args: remaining_args}}
    end
  end

  defp parse_options(args) do
    {options, remaining, _invalid} =
      OptionParser.parse(args,
        switches: [
          # Global options
          help: :boolean,
          version: :boolean,
          format: :string,
          verbose: :boolean,
          quiet: :boolean,

          # Server management options
          command: :string,
          url: :string,
          http_url: :string,
          timeout: :integer,
          trust: :string,
          add_tool: :string,
          remove_tool: :string,
          force: :boolean,

          # Status and monitoring options
          status: :boolean,
          tools: :boolean,
          all: :boolean,
          watch: :boolean,
          follow: :boolean,

          # Tool options
          server: :string,
          available: :boolean,
          describe: :string,
          path: :string,

          # Auth options
          reset: :boolean,
          level: :string,
          allow: :boolean,
          block: :boolean,

          # Analysis options
          export: :string,
          slow_tools: :boolean,
          error_rates: :boolean,

          # Discovery options
          network: :boolean,

          # Template options
          from: :string,

          # Import/export options
          merge: :boolean,
          validate_only: :boolean,
          output: :string
        ],
        aliases: [
          h: :help,
          v: :version,
          f: :format,
          s: :server,
          t: :timeout,
          o: :output
        ]
      )

    {Map.new(options), remaining}
  end

  defp execute_command(:mcp, subcommand, %{options: options, args: args}) do
    try do
      case subcommand do
        # Server management commands
        "list" ->
          List.execute(args, options)

        "add" ->
          Add.execute(args, options)

        "update" ->
          Update.execute(args, options)

        "remove" ->
          Remove.execute(args, options)

        # Status and monitoring commands
        "status" ->
          Status.execute(args, options)

        "test" ->
          Status.test_connection(args, options)

        "health" ->
          Status.health_check(args, options)

        # Tool management commands
        "tools" ->
          Tools.list_tools(args, options)

        "run" ->
          Tools.execute_tool(args, options)

        "debug" ->
          Tools.debug_tool(args, options)

        "trace" ->
          Tools.trace_tool(args, options)

        # Authentication commands
        "auth" ->
          Auth.execute(args, options)

        "apikey" ->
          Auth.manage_apikey(args, options)

        "trust" ->
          Trust.execute(args, options)

        # Monitoring and diagnostics commands
        "metrics" ->
          Metrics.show_metrics(args, options)

        "analyze" ->
          Metrics.analyze_performance(args, options)

        "diagnose" ->
          Diagnostics.diagnose(args, options)

        "logs" ->
          Diagnostics.show_logs(args, options)

        "ping" ->
          Diagnostics.ping_server(args, options)

        "trace-conn" ->
          Diagnostics.trace_connection(args, options)

        # Audit and reporting commands
        "audit" ->
          Metrics.show_audit(args, options)

        "report" ->
          Metrics.generate_report(args, options)

        # Configuration management commands
        "discover" ->
          Discovery.execute(args, options)

        "template" ->
          Templates.execute(args, options)

        # Alternative name
        "templates" ->
          Templates.execute(args, options)

        "export" ->
          ImportExport.execute_export(args, options)

        "import" ->
          ImportExport.execute_import(args, options)

        # Interactive commands
        "setup" ->
          Setup.execute(args, options)

        "interactive" ->
          Interactive.execute(args, options)

        "configure" ->
          Interactive.execute(args, options)

        # Help for specific commands
        command when command in ["help"] ->
          case args do
            [] -> show_mcp_help()
            [cmd] -> show_command_help(cmd)
          end

        unknown ->
          print_error("Unknown MCP command: #{unknown}")
          print_info("Use 'maestro mcp --help' for available commands")
          System.halt(1)
      end
    rescue
      error ->
        handle_command_error(subcommand, error)
    end
  end

  defp execute_command(command, _subcommand, _options) do
    case command do
      :help ->
        :ok

      :version ->
        :ok

      _ ->
        print_error("Unknown command")
        System.halt(1)
    end
  end

  defp handle_command_error(command, error) do
    case error do
      %ArgumentError{message: msg} ->
        print_error("Invalid arguments for '#{command}': #{msg}")
        print_info("Use 'maestro mcp #{command} --help' for usage information")

      %RuntimeError{message: msg} ->
        print_error("Command failed: #{msg}")

      error ->
        print_error("Unexpected error in '#{command}': #{inspect(error)}")
    end

    System.halt(1)
  end

  # Help and informational functions

  defp show_help do
    IO.puts("""
    The Maestro - AI Agent with MCP Integration

    Usage:
      maestro [COMMAND] [OPTIONS]
      maestro mcp [SUBCOMMAND] [OPTIONS]

    Global Commands:
      --help, -h        Show this help message
      --version, -v     Show version information

    MCP Commands:
      maestro mcp       MCP server management (see 'maestro mcp --help')

    For detailed help on MCP commands:
      maestro mcp --help

    Examples:
      maestro mcp list                    # List all configured MCP servers
      maestro mcp add myServer --command python -m server
      maestro mcp status myServer         # Check server status
      maestro mcp tools --server myServer # List server's tools
    """)
  end

  defp show_version do
    version = Application.spec(:the_maestro, :vsn) |> to_string()
    IO.puts("The Maestro v#{version}")
  end

  defp show_mcp_help do
    IO.puts("""
    MCP Management Commands

    Usage:
      maestro mcp SUBCOMMAND [OPTIONS]

    Server Management:
      list                      List all configured servers
      add <name> [options]      Add new MCP server
      update <name> [options]   Update server configuration
      remove <name> [options]   Remove MCP server

    Server Status & Monitoring:
      status [server]           Show server status
      test <server>             Test server connection
      health [options]          Health monitoring

    Tool Management:
      tools [options]           List available tools
      run <tool> [params]       Execute tool
      debug <tool> [params]     Debug tool execution
      trace <tool> [params]     Full execution trace

    Authentication & Security:
      auth <subcommand>         Authentication management
      apikey <subcommand>       API key management
      trust <subcommand>        Trust management

    Monitoring & Diagnostics:
      metrics [server]          Show performance metrics
      analyze [options]         Performance analysis
      diagnose [server]         System diagnosis
      logs <server>             View server logs
      ping <server>             Test server connectivity
      audit [options]           Show audit trail
      report [options]          Generate reports

    Configuration Management:
      discover [options]        Auto-discover servers
      template <subcommand>     Template management
      export [options]          Export configurations
      import <file> [options]   Import configurations

    Interactive Tools:
      setup                     Interactive setup wizard
      interactive [mode]        Start interactive shell mode
      configure <server>        Interactive server configuration

    Global Options:
      --format <format>         Output format (table, json, yaml)
      --verbose                 Verbose output
      --quiet                   Quiet mode
      --help                    Show help for specific command

    Examples:
      maestro mcp list --status
      maestro mcp add myServer --command "python -m server"
      maestro mcp tools --server myServer --available
      maestro mcp run read_file --path "/tmp/test.txt"
      maestro mcp export --format yaml --output config.yaml

    For detailed help on any command:
      maestro mcp <command> --help
    """)
  end

  defp show_command_help(command) do
    case command do
      "list" ->
        List.show_help()

      "add" ->
        Add.show_help()

      "update" ->
        Update.show_help()

      "remove" ->
        Remove.show_help()

      "status" ->
        Status.show_help()

      "tools" ->
        Tools.show_help()

      "auth" ->
        Auth.show_help()

      "trust" ->
        Trust.show_help()

      "metrics" ->
        Metrics.show_help()

      "diagnose" ->
        Diagnostics.show_help()

      "discover" ->
        Discovery.show_help()

      "template" ->
        Templates.show_help()

      "templates" ->
        Templates.show_help()

      "export" ->
        ImportExport.show_export_help()

      "import" ->
        ImportExport.show_import_help()

      "setup" ->
        Setup.show_help()

      "interactive" ->
        Interactive.show_help()

      _ ->
        print_error("No help available for command: #{command}")
    end
  end

  # Utility functions

  def print_info(message) do
    IO.puts(IO.ANSI.blue() <> "ℹ " <> IO.ANSI.reset() <> message)
  end

  def print_success(message) do
    IO.puts(IO.ANSI.green() <> "✓ " <> IO.ANSI.reset() <> message)
  end

  def print_warning(message) do
    IO.puts(IO.ANSI.yellow() <> "⚠ " <> IO.ANSI.reset() <> message)
  end

  def print_error(message) do
    IO.puts(:stderr, IO.ANSI.red() <> "✗ " <> IO.ANSI.reset() <> message)
  end

  def format_output(data, format) do
    case format do
      "json" -> JsonFormatter.format(data)
      "yaml" -> YamlFormatter.format(data)
      "table" -> TableFormatter.format(data)
      # Default to table
      _ -> TableFormatter.format(data)
    end
  end

  def get_output_format(options) do
    Map.get(options, :format, "table")
  end

  def verbose?(options) do
    Map.get(options, :verbose, false)
  end

  def quiet?(options) do
    Map.get(options, :quiet, false)
  end

  def print_if_verbose(message, options) do
    if verbose?(options) and not quiet?(options) do
      print_info(message)
    end
  end

  def print_unless_quiet(message, options) do
    unless quiet?(options) do
      IO.puts(message)
    end
  end
end
