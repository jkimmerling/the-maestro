defmodule TheMaestro.MCP.CLI.Commands.Update do
  @moduledoc """
  Update command for MCP CLI.

  Provides functionality to update existing MCP server configurations
  with validation and safe configuration changes.
  """

  alias TheMaestro.MCP.{Config, ConnectionManager}
  alias TheMaestro.MCP.Config.ConfigValidator
  alias TheMaestro.MCP.CLI

  @doc """
  Execute the update command.

  ## Arguments

  - `server_name` - Name of the server to update

  ## Options

  - `--command <cmd>` - Update command for STDIO transport
  - `--url <url>` - Update URL for SSE transport
  - `--http-url <url>` - Update URL for HTTP transport
  - `--timeout <ms>` - Update connection timeout
  - `--trust <bool>` - Update trust level
  - `--add-tool <name>` - Add tool to include list
  - `--remove-tool <name>` - Add tool to exclude list
  - `--description <text>` - Update server description
  """
  def execute(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case parse_update_args(args, options) do
      {:ok, server_name, updates} ->
        update_server(server_name, updates, options)

      {:error, reason} ->
        CLI.print_error(reason)
        {:error, reason}
    end
  end

  @doc """
  Show help for the update command.
  """
  def show_help do
    IO.puts("""
    Update MCP Server

    Usage:
      maestro mcp update <server_name> [OPTIONS]

    Description:
      Updates an existing MCP server configuration. Changes are validated
      and applied safely with optional connection restart.

    Transport Updates:
      --command <cmd>           Update command for STDIO transport
      --url <url>              Update URL for SSE transport  
      --http-url <url>         Update URL for HTTP transport

    Configuration Updates:
      --timeout <ms>           Update connection timeout in milliseconds
      --trust <bool>           Update trust level (true/false)
      --description <text>     Update server description

    STDIO Transport Updates:
      --args <arg>             Update command arguments (can be repeated)
      --cwd <path>             Update working directory
      --env <key=value>        Update environment variables (can be repeated)

    HTTP/SSE Transport Updates:
      --header <key:value>     Update HTTP headers (can be repeated)

    Tool Management:
      --add-tool <name>        Add tool to include list (can be repeated)
      --remove-tool <name>     Add tool to exclude list (can be repeated)
      --clear-includes         Clear all included tools
      --clear-excludes         Clear all excluded tools

    Security Updates:
      --oauth-client <id>      Update OAuth client ID
      --oauth-scope <scope>    Update OAuth scopes (can be repeated)
      --rate-limit <rpm>       Update rate limit (requests per minute)

    Connection Management:
      --restart                Restart connection after update
      --no-restart             Don't restart connection (default)

    Global Options:
      --verbose                Show detailed output
      --help                   Show this help message

    Examples:
      # Update server timeout
      maestro mcp update myServer --timeout 60000
      
      # Update server URL and restart connection
      maestro mcp update apiServer --url "https://api.newdomain.com/sse" --restart
      
      # Add tools to server
      maestro mcp update myServer --add-tool "read_file" --add-tool "write_file"
      
      # Update environment variables
      maestro mcp update myServer --env "DEBUG=true" --env "LOG_LEVEL=info"
      
      # Update trust level and description
      maestro mcp update myServer --trust true --description "Trusted file server"
    """)
  end

  ## Private Functions

  defp parse_update_args(args, options) do
    case args do
      [] ->
        {:error, "Server name is required. Use --help for usage information."}

      [server_name | _rest] ->
        case build_updates(options) do
          {:ok, updates} when map_size(updates) > 0 ->
            {:ok, server_name, updates}

          {:ok, _empty_updates} ->
            {:error, "No updates specified. Use --help for available options."}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp build_updates(options) do
    updates = %{}

    updates
    |> maybe_add_transport_updates(options)
    |> maybe_add_configuration_updates(options)
    |> maybe_add_tool_updates(options)
    |> maybe_add_security_updates(options)
    |> validate_updates()
  end

  defp maybe_add_transport_updates(updates, options) do
    updates
    |> maybe_put("command", Map.get(options, :command))
    |> maybe_put("url", Map.get(options, :url))
    |> maybe_put("httpUrl", Map.get(options, :http_url))
    |> maybe_add_stdio_updates(options)
    |> maybe_add_http_updates(options)
  end

  defp maybe_add_stdio_updates(updates, options) do
    updates
    |> maybe_put("args", normalize_list_option(Map.get(options, :args)))
    |> maybe_put("cwd", Map.get(options, :cwd))
    |> maybe_add_env_updates(options)
  end

  defp maybe_add_env_updates(updates, options) do
    case Map.get(options, :env) do
      nil ->
        updates

      env_list when is_list(env_list) ->
        env_map = parse_env_vars(env_list)
        Map.put(updates, "env", env_map)

      single_env ->
        env_map = parse_env_vars([single_env])
        Map.put(updates, "env", env_map)
    end
  end

  defp maybe_add_http_updates(updates, options) do
    case Map.get(options, :header) do
      nil ->
        updates

      header_list when is_list(header_list) ->
        headers = parse_headers(header_list)
        Map.put(updates, "headers", headers)

      single_header ->
        headers = parse_headers([single_header])
        Map.put(updates, "headers", headers)
    end
  end

  defp maybe_add_configuration_updates(updates, options) do
    updates
    |> maybe_put("timeout", Map.get(options, :timeout))
    |> maybe_put("trust", parse_trust_option(Map.get(options, :trust)))
    |> maybe_put("description", Map.get(options, :description))
  end

  defp maybe_add_tool_updates(updates, options) do
    updates
    |> maybe_add_tool_list_updates(
      "includeTools",
      Map.get(options, :add_tool),
      Map.get(options, :clear_includes)
    )
    |> maybe_add_tool_list_updates(
      "excludeTools",
      Map.get(options, :remove_tool),
      Map.get(options, :clear_excludes)
    )
  end

  defp maybe_add_tool_list_updates(updates, key, new_tools, clear_flag) do
    cond do
      clear_flag -> Map.put(updates, key, [])
      new_tools != nil -> Map.put(updates, key, normalize_list_option(new_tools))
      true -> updates
    end
  end

  defp maybe_add_security_updates(updates, options) do
    updates
    |> maybe_add_oauth_updates(options)
    |> maybe_add_rate_limit_updates(options)
  end

  defp maybe_add_oauth_updates(updates, options) do
    oauth_client = Map.get(options, :oauth_client)
    oauth_scopes = Map.get(options, :oauth_scope)

    if oauth_client || oauth_scopes do
      oauth_config = %{"enabled" => true}

      oauth_config =
        oauth_config
        |> maybe_put("clientId", oauth_client)
        |> maybe_put("scopes", normalize_list_option(oauth_scopes))

      Map.put(updates, "oauth", oauth_config)
    else
      updates
    end
  end

  defp maybe_add_rate_limit_updates(updates, options) do
    case Map.get(options, :rate_limit) do
      nil ->
        updates

      rpm when is_integer(rpm) ->
        rate_config = %{
          "enabled" => true,
          "requestsPerMinute" => rpm
        }

        Map.put(updates, "rateLimiting", rate_config)

      _ ->
        updates
    end
  end

  defp validate_updates({:error, reason}), do: {:error, reason}

  defp validate_updates(updates) when is_map(updates) do
    # Check for conflicting transport updates
    transport_fields = ["command", "url", "httpUrl"]
    transport_updates = Enum.count(transport_fields, &Map.has_key?(updates, &1))

    if transport_updates > 1 do
      {:error, "Cannot update multiple transport types in the same command"}
    else
      {:ok, updates}
    end
  end

  defp update_server(server_name, updates, options) do
    CLI.print_if_verbose("Updating server '#{server_name}'...", options)

    case Config.get_configuration() do
      {:ok, current_config} ->
        case get_in(current_config, ["mcpServers", server_name]) do
          nil ->
            CLI.print_error("Server '#{server_name}' not found.")

          current_server_config ->
            apply_updates(current_config, server_name, current_server_config, updates, options)
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end

  defp apply_updates(config, server_name, current_server_config, updates, options) do
    # Merge updates with current configuration
    updated_server_config = deep_merge(current_server_config, updates)

    # Validate the updated configuration
    case ConfigValidator.validate_server_config(server_name, updated_server_config) do
      [] ->
        save_updated_server(
          config,
          server_name,
          current_server_config,
          updated_server_config,
          updates,
          options
        )

      errors ->
        CLI.print_error("Configuration validation failed:")

        Enum.each(errors, fn error ->
          CLI.print_error("  - #{error}")
        end)
    end
  end

  defp deep_merge(original, updates) when is_map(original) and is_map(updates) do
    Map.merge(original, updates, fn _key, original_val, update_val ->
      case {original_val, update_val} do
        {orig, upd} when is_map(orig) and is_map(upd) ->
          deep_merge(orig, upd)

        {_orig, upd} ->
          upd
      end
    end)
  end

  defp save_updated_server(config, server_name, original_config, updated_config, updates, options) do
    # Update the configuration
    updated_full_config = put_in(config, ["mcpServers", server_name], updated_config)

    config_path = get_config_path()

    case Config.save_configuration(updated_full_config, config_path) do
      :ok ->
        CLI.print_success("Successfully updated server '#{server_name}'")
        print_update_summary(server_name, original_config, updated_config, updates, options)

        # Restart connection if requested
        if Map.get(options, :restart, false) do
          restart_server_connection(server_name, updated_config, options)
        end

      {:error, reason} ->
        CLI.print_error("Failed to save configuration: #{reason}")
    end
  end

  defp print_update_summary(server_name, original_config, _updated_config, updates, options) do
    unless CLI.quiet?(options) do
      IO.puts("")
      IO.puts("Update Summary for '#{server_name}':")

      Enum.each(updates, fn {key, new_value} ->
        old_value = Map.get(original_config, key)
        print_change_summary(key, old_value, new_value)
      end)

      IO.puts("")
      IO.puts("Use 'maestro mcp status #{server_name}' to check connection status.")
    end
  end

  defp print_change_summary(key, old_value, new_value) do
    case key do
      "command" ->
        IO.puts("  Command: #{old_value || "none"} → #{new_value}")

      "url" ->
        IO.puts("  URL: #{old_value || "none"} → #{new_value}")

      "httpUrl" ->
        IO.puts("  HTTP URL: #{old_value || "none"} → #{new_value}")

      "timeout" ->
        IO.puts("  Timeout: #{old_value || "default"}ms → #{new_value}ms")

      "trust" ->
        IO.puts("  Trust: #{old_value || false} → #{new_value}")

      "description" ->
        IO.puts(~s|  Description: "#{old_value || ""}" → "#{new_value}"|)

      "includeTools" ->
        IO.puts(
          "  Include Tools: #{format_tool_list(old_value)} → #{format_tool_list(new_value)}"
        )

      "excludeTools" ->
        IO.puts(
          "  Exclude Tools: #{format_tool_list(old_value)} → #{format_tool_list(new_value)}"
        )

      other ->
        IO.puts("  #{String.capitalize(other)}: #{inspect(old_value)} → #{inspect(new_value)}")
    end
  end

  defp format_tool_list(nil), do: "none"
  defp format_tool_list([]), do: "none"
  defp format_tool_list(tools) when is_list(tools), do: Enum.join(tools, ", ")
  defp format_tool_list(other), do: inspect(other)

  defp restart_server_connection(server_name, server_config, options) do
    CLI.print_if_verbose("Restarting server connection...", options)

    # Stop existing connection
    case ConnectionManager.stop_connection(ConnectionManager, server_name) do
      :ok ->
        CLI.print_if_verbose("Stopped existing connection.", options)

      {:error, :not_found} ->
        CLI.print_if_verbose("No existing connection to stop.", options)

      {:error, reason} ->
        CLI.print_warning("Warning: Could not stop existing connection: #{reason}")
    end

    # Start new connection
    server_config_with_id = Map.put(server_config, :id, server_name)

    case ConnectionManager.start_connection(ConnectionManager, server_config_with_id) do
      {:ok, _pid} ->
        CLI.print_success("Server connection restarted successfully.")

      {:error, reason} ->
        CLI.print_error("Failed to restart connection: #{reason}")
    end
  end

  # Helper functions

  defp parse_env_vars(env_list) do
    Enum.reduce(env_list, %{}, fn env_string, acc ->
      case String.split(env_string, "=", parts: 2) do
        [key, value] -> Map.put(acc, key, value)
        [key] -> Map.put(acc, key, "")
        _ -> acc
      end
    end)
  end

  defp parse_headers(header_list) do
    Enum.reduce(header_list, %{}, fn header_string, acc ->
      case String.split(header_string, ":", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp parse_trust_option(nil), do: nil
  defp parse_trust_option("true"), do: true
  defp parse_trust_option("false"), do: false
  defp parse_trust_option(true), do: true
  defp parse_trust_option(false), do: false
  defp parse_trust_option(_), do: nil

  defp normalize_list_option(nil), do: nil
  defp normalize_list_option(list) when is_list(list), do: list
  defp normalize_list_option(single_item), do: [single_item]

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp get_config_path do
    "./.maestro/mcp_settings.json"
  end
end
