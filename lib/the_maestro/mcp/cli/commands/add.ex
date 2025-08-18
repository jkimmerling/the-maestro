defmodule TheMaestro.MCP.CLI.Commands.Add do
  @moduledoc """
  Add command for MCP CLI.

  Provides functionality to add new MCP servers with various transport types
  and configuration options.
  """

  alias TheMaestro.MCP.{Config, ConnectionManager}
  alias TheMaestro.MCP.Config.ConfigValidator
  alias TheMaestro.MCP.CLI

  @doc """
  Execute the add command.

  ## Arguments

  - `server_name` - Name for the new server

  ## Options

  - `--command <cmd>` - Command for STDIO transport
  - `--url <url>` - URL for SSE transport
  - `--http-url <url>` - URL for HTTP transport
  - `--timeout <ms>` - Connection timeout in milliseconds
  - `--trust <bool>` - Trust level (true/false)
  - `--env <key=value>` - Environment variables (can be repeated)
  - `--include-tool <name>` - Include specific tool (can be repeated)
  - `--exclude-tool <name>` - Exclude specific tool (can be repeated)
  """
  def execute(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case parse_add_args(args, options) do
      {:ok, server_name, server_config} ->
        add_server(server_name, server_config, options)

      {:error, reason} ->
        CLI.print_error(reason)
        {:error, reason}
    end
  end

  @doc """
  Show help for the add command.
  """
  def show_help do
    IO.puts("""
    Add MCP Server

    Usage:
      maestro mcp add <server_name> [OPTIONS]

    Description:
      Adds a new MCP server configuration. Must specify one transport type.

    Transport Options (choose one):
      --command <cmd>           Command for STDIO transport
      --url <url>              URL for Server-Sent Events (SSE) transport
      --http-url <url>         URL for HTTP transport

    Configuration Options:
      --timeout <ms>           Connection timeout in milliseconds (default: 30000)
      --trust <bool>           Trust level: true or false (default: false)
      --description <text>     Server description

    STDIO Transport Options:
      --args <arg>             Command arguments (can be repeated)
      --cwd <path>             Working directory
      --env <key=value>        Environment variables (can be repeated)

    HTTP/SSE Transport Options:
      --header <key:value>     HTTP headers (can be repeated)

    Tool Filtering Options:
      --include-tool <name>    Include specific tool (can be repeated)
      --exclude-tool <name>    Exclude specific tool (can be repeated)

    Security Options:
      --oauth-client <id>      OAuth client ID
      --oauth-scope <scope>    OAuth scopes (can be repeated)
      --rate-limit <rpm>       Rate limit (requests per minute)

    Global Options:
      --verbose                Show detailed output
      --help                   Show this help message

    Examples:
      # Add STDIO server
      maestro mcp add fileServer --command python --args "-m" --args "file_server"
      
      # Add SSE server with authentication
      maestro mcp add weatherAPI --url "https://weather.example.com/sse" \\
                                 --header "Authorization:Bearer TOKEN" \\
                                 --trust true
      
      # Add HTTP server with rate limiting
      maestro mcp add dbAPI --http-url "http://localhost:3000/mcp" \\
                            --rate-limit 60 \\
                            --include-tool "query_users"
      
      # Add server with environment variables
      maestro mcp add myServer --command "./server" \\
                               --env "API_KEY=secret123" \\
                               --env "DEBUG=true" \\
                               --cwd "/opt/myserver"
    """)
  end

  ## Private Functions

  defp parse_add_args(args, options) do
    case args do
      [] ->
        {:error, "Server name is required. Use --help for usage information."}

      [server_name | _rest] ->
        case build_server_config(server_name, options) do
          {:ok, server_config} ->
            {:ok, server_name, server_config}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp build_server_config(server_name, options) do
    base_config = %{
      "timeout" => Map.get(options, :timeout, 30_000),
      "trust" => parse_trust_option(Map.get(options, :trust, "false")),
      "description" => Map.get(options, :description, "")
    }

    case determine_transport(options) do
      {:ok, transport_config} ->
        server_config =
          base_config
          |> Map.merge(transport_config)
          |> add_tool_filters(options)
          |> add_security_options(options)
          |> add_transport_specific_options(options)

        case validate_server_config(server_name, server_config) do
          [] -> {:ok, server_config}
          errors -> {:error, "Configuration validation failed: #{Enum.join(errors, ", ")}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp determine_transport(options) do
    transports = [
      {:stdio, Map.get(options, :command)},
      {:sse, Map.get(options, :url)},
      {:http, Map.get(options, :http_url)}
    ]

    active_transports =
      transports
      |> Enum.filter(fn {_type, value} -> value != nil end)

    case active_transports do
      [] ->
        {:error, "Must specify one transport type: --command, --url, or --http-url"}

      [{transport_type, value}] ->
        build_transport_config(transport_type, value, options)

      _ ->
        {:error, "Can only specify one transport type"}
    end
  end

  defp build_transport_config(:stdio, command, options) do
    config = %{"command" => command}

    config =
      config
      |> maybe_add_args(options)
      |> maybe_add_cwd(options)
      |> maybe_add_env_vars(options)

    {:ok, config}
  end

  defp build_transport_config(:sse, url, options) do
    config = %{"url" => url}

    config =
      config
      |> maybe_add_headers(options)
      |> maybe_add_oauth_config(options)

    {:ok, config}
  end

  defp build_transport_config(:http, url, options) do
    config = %{"httpUrl" => url}

    config =
      config
      |> maybe_add_headers(options)
      |> maybe_add_oauth_config(options)

    {:ok, config}
  end

  defp maybe_add_args(config, options) do
    case Map.get(options, :args) do
      nil -> config
      args when is_list(args) -> Map.put(config, "args", args)
      single_arg -> Map.put(config, "args", [single_arg])
    end
  end

  defp maybe_add_cwd(config, options) do
    case Map.get(options, :cwd) do
      nil -> config
      cwd -> Map.put(config, "cwd", cwd)
    end
  end

  defp maybe_add_env_vars(config, options) do
    case Map.get(options, :env) do
      nil ->
        config

      env_list when is_list(env_list) ->
        env_map = parse_env_vars(env_list)
        Map.put(config, "env", env_map)

      single_env ->
        env_map = parse_env_vars([single_env])
        Map.put(config, "env", env_map)
    end
  end

  defp parse_env_vars(env_list) do
    Enum.reduce(env_list, %{}, fn env_string, acc ->
      case String.split(env_string, "=", parts: 2) do
        [key, value] -> Map.put(acc, key, value)
        [key] -> Map.put(acc, key, "")
        _ -> acc
      end
    end)
  end

  defp maybe_add_headers(config, options) do
    case Map.get(options, :header) do
      nil ->
        config

      header_list when is_list(header_list) ->
        headers = parse_headers(header_list)
        Map.put(config, "headers", headers)

      single_header ->
        headers = parse_headers([single_header])
        Map.put(config, "headers", headers)
    end
  end

  defp parse_headers(header_list) do
    Enum.reduce(header_list, %{}, fn header_string, acc ->
      case String.split(header_string, ":", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp maybe_add_oauth_config(config, options) do
    oauth_client = Map.get(options, :oauth_client)
    oauth_scopes = Map.get(options, :oauth_scope)

    if oauth_client || oauth_scopes do
      oauth_config = %{
        "enabled" => true
      }

      oauth_config =
        oauth_config
        |> maybe_put("clientId", oauth_client)
        |> maybe_put("scopes", normalize_scopes(oauth_scopes))

      Map.put(config, "oauth", oauth_config)
    else
      config
    end
  end

  defp normalize_scopes(nil), do: nil
  defp normalize_scopes(scopes) when is_list(scopes), do: scopes
  defp normalize_scopes(single_scope), do: [single_scope]

  defp add_tool_filters(config, options) do
    config
    |> maybe_add_tool_list("includeTools", Map.get(options, :include_tool))
    |> maybe_add_tool_list("excludeTools", Map.get(options, :exclude_tool))
  end

  defp maybe_add_tool_list(config, key, nil), do: config

  defp maybe_add_tool_list(config, key, tools) when is_list(tools) do
    Map.put(config, key, tools)
  end

  defp maybe_add_tool_list(config, key, single_tool) do
    Map.put(config, key, [single_tool])
  end

  defp add_security_options(config, options) do
    config
    |> maybe_add_rate_limiting(options)
  end

  defp maybe_add_rate_limiting(config, options) do
    case Map.get(options, :rate_limit) do
      nil ->
        config

      rpm when is_integer(rpm) ->
        rate_config = %{
          "enabled" => true,
          "requestsPerMinute" => rpm
        }

        Map.put(config, "rateLimiting", rate_config)

      _ ->
        config
    end
  end

  defp add_transport_specific_options(config, _options) do
    # Add any transport-specific options that weren't handled above
    config
  end

  defp parse_trust_option("true"), do: true
  defp parse_trust_option("false"), do: false
  defp parse_trust_option(true), do: true
  defp parse_trust_option(false), do: false
  defp parse_trust_option(_), do: false

  defp validate_server_config(server_name, server_config) do
    ConfigValidator.validate_server_config(server_name, server_config)
  end

  defp add_server(server_name, server_config, options) do
    CLI.print_if_verbose("Adding server '#{server_name}'...", options)

    case Config.get_configuration() do
      {:ok, current_config} ->
        case Config.add_server_config(current_config, server_name, server_config) do
          updated_config when is_map(updated_config) ->
            save_and_start_server(updated_config, server_name, server_config, options)

          {:error, :server_exists} ->
            CLI.print_error(
              "Server '#{server_name}' already exists. Use 'update' to modify it."
            )

          {:error, reason} ->
            CLI.print_error("Failed to add server: #{reason}")
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp save_and_start_server(updated_config, server_name, server_config, options) do
    # Save configuration
    config_path = get_config_path()

    case Config.save_configuration(updated_config, config_path) do
      :ok ->
        CLI.print_if_verbose("Configuration saved to #{config_path}", options)

        # Optionally start the server immediately
        if should_start_server?(options) do
          start_server_connection(server_name, server_config, options)
        else
          CLI.print_success("Successfully added server '#{server_name}'")
          print_server_summary(server_name, server_config, options)
        end

      {:error, reason} ->
        CLI.print_error("Failed to save configuration: #{reason}")
    end
  end

  defp should_start_server?(options) do
    # Start server by default unless explicitly disabled
    not Map.get(options, :no_start, false)
  end

  defp start_server_connection(server_name, server_config, options) do
    CLI.print_if_verbose(
      "Starting connection to server '#{server_name}'...",
      options
    )

    # Add server ID to config for ConnectionManager
    server_config_with_id = Map.put(server_config, :id, server_name)

    case ConnectionManager.start_connection(ConnectionManager, server_config_with_id) do
      {:ok, _pid} ->
        CLI.print_success("Successfully added and started server '#{server_name}'")
        print_server_summary(server_name, server_config, options)

      {:error, reason} ->
        CLI.print_warning(
          "Server '#{server_name}' was added but failed to start: #{reason}"
        )

        print_server_summary(server_name, server_config, options)
    end
  end

  defp print_server_summary(server_name, server_config, options) do
    unless CLI.is_quiet?(options) do
      IO.puts("")
      IO.puts("Server Details:")
      IO.puts("  Name: #{server_name}")
      IO.puts("  Transport: #{detect_transport_type(server_config)}")

      if Map.has_key?(server_config, "command") do
        IO.puts("  Command: #{server_config["command"]}")

        if args = Map.get(server_config, "args") do
          IO.puts("  Args: #{Enum.join(args, " ")}")
        end
      end

      if url = Map.get(server_config, "url") || Map.get(server_config, "httpUrl") do
        IO.puts("  URL: #{url}")
      end

      IO.puts("  Trust: #{server_config["trust"]}")
      IO.puts("  Timeout: #{server_config["timeout"]}ms")

      if tools = Map.get(server_config, "includeTools") do
        IO.puts("  Include Tools: #{Enum.join(tools, ", ")}")
      end

      if tools = Map.get(server_config, "excludeTools") do
        IO.puts("  Exclude Tools: #{Enum.join(tools, ", ")}")
      end

      IO.puts("")
      IO.puts("Use 'maestro mcp status #{server_name}' to check connection status.")
      IO.puts("Use 'maestro mcp tools --server #{server_name}' to see available tools.")
    end
  end

  defp detect_transport_type(server_config) do
    cond do
      Map.has_key?(server_config, "command") -> "STDIO"
      Map.has_key?(server_config, "url") -> "SSE"
      Map.has_key?(server_config, "httpUrl") -> "HTTP"
      true -> "Unknown"
    end
  end

  defp get_config_path do
    # Use project-specific config path
    "./.maestro/mcp_settings.json"
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
