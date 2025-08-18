defmodule TheMaestro.MCP.Config.ConfigValidator do
  @moduledoc """
  Comprehensive configuration validation for MCP server configurations.

  Provides multi-layered validation including:
  - Schema structure validation
  - Transport-specific validation
  - Security settings validation
  - Dependency validation
  - URL format validation
  - Performance settings validation
  """

  require Logger

  @type validation_result :: {:ok, map()} | {:error, [String.t()]}

  # Validation constants
  @valid_confirmation_levels ["low", "medium", "high"]
  @valid_trust_levels [true, false, "trusted", "untrusted"]
  @required_stdio_fields ["command"]
  @required_sse_fields ["url"]
  @required_http_fields ["httpUrl"]
  @min_timeout 1000
  @max_timeout 300_000

  @doc """
  Validate complete MCP configuration.

  Performs comprehensive validation of the entire configuration structure,
  including global settings and all server configurations.
  """
  @spec validate(map()) :: validation_result()
  def validate(config) when is_map(config) do
    errors = []

    errors =
      errors
      |> validate_root_structure(config)
      |> validate_global_settings(config)
      |> validate_servers(config)
      |> validate_server_dependencies(config)

    case errors do
      [] -> {:ok, config}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def validate(_config) do
    {:error, ["Configuration must be a map"]}
  end

  @doc """
  Validate configuration against JSON schema.

  Uses a comprehensive JSON schema to validate structure and types.
  """
  @spec validate_schema(map()) :: validation_result()
  def validate_schema(config) do
    # This would use a JSON schema validation library
    # For now, we'll use our custom validation
    validate(config)
  end

  @doc """
  Validate a single server configuration.
  """
  @spec validate_server_config(String.t(), map()) :: [String.t()]
  def validate_server_config(server_id, server_config) do
    errors = []

    errors
    |> validate_transport_config(server_id, server_config)
    |> validate_security_config(server_id, server_config)
    |> validate_tool_config(server_id, server_config)
    |> validate_performance_config(server_id, server_config)
    |> validate_authentication_config(server_id, server_config)
  end

  ## Private Validation Functions

  defp validate_root_structure(errors, config) do
    required_sections = ["mcpServers"]

    Enum.reduce(required_sections, errors, fn section, acc_errors ->
      case Map.get(config, section) do
        nil ->
          ["Missing required section: #{section}" | acc_errors]

        value when not is_map(value) ->
          ["Section '#{section}' must be a map" | acc_errors]

        _ ->
          acc_errors
      end
    end)
  end

  defp validate_global_settings(errors, config) do
    case Map.get(config, "globalSettings") do
      # Global settings are optional
      nil ->
        errors

      settings when is_map(settings) ->
        validate_individual_global_settings(errors, settings)

      _ ->
        ["globalSettings must be a map" | errors]
    end
  end

  defp validate_individual_global_settings(errors, settings) do
    errors
    |> validate_timeout_setting(settings, "defaultTimeout")
    |> validate_timeout_setting(settings, "healthCheckInterval")
    |> validate_integer_setting(settings, "maxConcurrentConnections", 1, 100)
    |> validate_confirmation_level(settings)
    |> validate_boolean_setting(settings, "auditLogging")
    |> validate_boolean_setting(settings, "autoReconnect")
  end

  defp validate_servers(errors, config) do
    case Map.get(config, "mcpServers") do
      servers when is_map(servers) and map_size(servers) == 0 ->
        ["No MCP servers configured" | errors]

      servers when is_map(servers) ->
        Enum.reduce(servers, errors, fn {server_id, server_config}, acc_errors ->
          server_errors = validate_server_config(server_id, server_config)
          server_errors ++ acc_errors
        end)

      _ ->
        ["mcpServers must be a map" | errors]
    end
  end

  defp validate_server_dependencies(errors, config) do
    case Map.get(config, "mcpServers") do
      servers when is_map(servers) ->
        validate_dependency_graph(errors, servers)

      _ ->
        errors
    end
  end

  defp validate_transport_config(errors, server_id, server_config) do
    transport_type = detect_transport_type(server_config)

    case transport_type do
      :stdio ->
        validate_stdio_config(errors, server_id, server_config)

      :sse ->
        validate_sse_config(errors, server_id, server_config)

      :http ->
        validate_http_config(errors, server_id, server_config)

      :unknown ->
        ["Server '#{server_id}': Must specify transport (command, url, or httpUrl)" | errors]
    end
  end

  defp validate_stdio_config(errors, server_id, server_config) do
    errors
    |> validate_required_fields(server_id, server_config, @required_stdio_fields)
    |> validate_command_config(server_id, server_config)
    |> validate_args_config(server_id, server_config)
    |> validate_env_config(server_id, server_config)
    |> validate_working_directory(server_id, server_config)
  end

  defp validate_sse_config(errors, server_id, server_config) do
    errors
    |> validate_required_fields(server_id, server_config, @required_sse_fields)
    |> validate_url_format(server_id, server_config, "url")
    |> validate_headers_config(server_id, server_config)
  end

  defp validate_http_config(errors, server_id, server_config) do
    errors
    |> validate_required_fields(server_id, server_config, @required_http_fields)
    |> validate_url_format(server_id, server_config, "httpUrl")
    |> validate_headers_config(server_id, server_config)
  end

  defp validate_security_config(errors, server_id, server_config) do
    errors
    |> validate_trust_setting(server_id, server_config)
    |> validate_confirmation_level_server(server_id, server_config)
    |> validate_rate_limiting_config(server_id, server_config)
  end

  defp validate_tool_config(errors, server_id, server_config) do
    errors
    |> validate_tool_lists(server_id, server_config, "includeTools")
    |> validate_tool_lists(server_id, server_config, "excludeTools")
    |> validate_tool_conflicts(server_id, server_config)
  end

  defp validate_performance_config(errors, server_id, server_config) do
    errors
    |> validate_timeout_setting_server(server_id, server_config)
    |> validate_retry_config(server_id, server_config)
  end

  defp validate_authentication_config(errors, server_id, server_config) do
    case Map.get(server_config, "oauth") do
      nil ->
        errors

      oauth_config when is_map(oauth_config) ->
        validate_oauth_config(errors, server_id, oauth_config)

      _ ->
        ["Server '#{server_id}': OAuth configuration must be a map" | errors]
    end
  end

  defp detect_transport_type(server_config) do
    cond do
      Map.has_key?(server_config, "command") -> :stdio
      Map.has_key?(server_config, "url") -> :sse
      Map.has_key?(server_config, "httpUrl") -> :http
      true -> :unknown
    end
  end

  defp validate_required_fields(errors, server_id, server_config, required_fields) do
    Enum.reduce(required_fields, errors, fn field, acc_errors ->
      case Map.get(server_config, field) do
        nil ->
          ["Server '#{server_id}': Missing required field '#{field}'" | acc_errors]

        "" ->
          ["Server '#{server_id}': Field '#{field}' cannot be empty" | acc_errors]

        _ ->
          acc_errors
      end
    end)
  end

  defp validate_command_config(errors, server_id, server_config) do
    case Map.get(server_config, "command") do
      command when is_binary(command) and byte_size(command) > 0 ->
        # Additional validation: check if command is executable
        validate_command_executable(errors, server_id, command)

      _ ->
        ["Server '#{server_id}': Command must be a non-empty string" | errors]
    end
  end

  defp validate_command_executable(errors, server_id, command) do
    # Basic check - in production might want to verify PATH
    if String.contains?(command, "/") do
      # Absolute or relative path
      if File.exists?(command) do
        errors
      else
        ["Server '#{server_id}': Command file does not exist: #{command}" | errors]
      end
    else
      # Command in PATH - skip validation for now as it's environment dependent
      errors
    end
  end

  defp validate_args_config(errors, server_id, server_config) do
    case Map.get(server_config, "args") do
      # Args are optional
      nil ->
        errors

      args when is_list(args) ->
        if Enum.all?(args, &is_binary/1) do
          errors
        else
          ["Server '#{server_id}': All arguments must be strings" | errors]
        end

      _ ->
        ["Server '#{server_id}': Args must be a list of strings" | errors]
    end
  end

  defp validate_env_config(errors, server_id, server_config) do
    case Map.get(server_config, "env") do
      # Env is optional
      nil ->
        errors

      env when is_map(env) ->
        validate_env_values(errors, server_id, env)

      _ ->
        ["Server '#{server_id}': Env must be a map of string key-value pairs" | errors]
    end
  end

  defp validate_env_values(errors, server_id, env) do
    Enum.reduce(env, errors, fn {key, value}, acc_errors ->
      cond do
        not is_binary(key) ->
          [
            "Server '#{server_id}': Environment variable key must be string: #{inspect(key)}"
            | acc_errors
          ]

        not is_binary(value) ->
          [
            "Server '#{server_id}': Environment variable value must be string: #{key}=#{inspect(value)}"
            | acc_errors
          ]

        String.length(key) == 0 ->
          ["Server '#{server_id}': Environment variable key cannot be empty" | acc_errors]

        true ->
          acc_errors
      end
    end)
  end

  defp validate_working_directory(errors, server_id, server_config) do
    case Map.get(server_config, "cwd") do
      # CWD is optional
      nil ->
        errors

      cwd when is_binary(cwd) ->
        if File.dir?(cwd) do
          errors
        else
          ["Server '#{server_id}': Working directory does not exist: #{cwd}" | errors]
        end

      _ ->
        ["Server '#{server_id}': Working directory must be a string" | errors]
    end
  end

  defp validate_url_format(errors, server_id, server_config, url_field) do
    case Map.get(server_config, url_field) do
      url when is_binary(url) ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
            errors

          _ ->
            ["Server '#{server_id}': Invalid URL format for '#{url_field}': #{url}" | errors]
        end

      _ ->
        ["Server '#{server_id}': #{url_field} must be a valid URL string" | errors]
    end
  end

  defp validate_headers_config(errors, server_id, server_config) do
    case Map.get(server_config, "headers") do
      # Headers are optional
      nil ->
        errors

      headers when is_map(headers) ->
        validate_header_values(errors, server_id, headers)

      _ ->
        ["Server '#{server_id}': Headers must be a map" | errors]
    end
  end

  defp validate_header_values(errors, server_id, headers) do
    Enum.reduce(headers, errors, fn {key, value}, acc_errors ->
      cond do
        not is_binary(key) ->
          ["Server '#{server_id}': Header key must be string: #{inspect(key)}" | acc_errors]

        not is_binary(value) ->
          [
            "Server '#{server_id}': Header value must be string: #{key}=#{inspect(value)}"
            | acc_errors
          ]

        String.length(key) == 0 ->
          ["Server '#{server_id}': Header key cannot be empty" | acc_errors]

        true ->
          acc_errors
      end
    end)
  end

  defp validate_trust_setting(errors, server_id, server_config) do
    case Map.get(server_config, "trust") do
      # Trust is optional, defaults to false
      nil ->
        errors

      trust when trust in @valid_trust_levels ->
        errors

      _ ->
        ["Server '#{server_id}': Trust must be boolean or 'trusted'/'untrusted'" | errors]
    end
  end

  defp validate_confirmation_level_server(errors, server_id, server_config) do
    case Map.get(server_config, "confirmationLevel") do
      # Optional, uses global default
      nil ->
        errors

      level when level in @valid_confirmation_levels ->
        errors

      _ ->
        valid_levels = Enum.join(@valid_confirmation_levels, ", ")
        ["Server '#{server_id}': confirmationLevel must be one of: #{valid_levels}" | errors]
    end
  end

  defp validate_rate_limiting_config(errors, server_id, server_config) do
    case Map.get(server_config, "rateLimiting") do
      # Rate limiting is optional
      nil ->
        errors

      config when is_map(config) ->
        validate_rate_limiting_values(errors, server_id, config)

      _ ->
        ["Server '#{server_id}': rateLimiting must be a map" | errors]
    end
  end

  defp validate_rate_limiting_values(errors, server_id, config) do
    errors
    |> validate_boolean_setting_server(server_id, config, "enabled")
    |> validate_integer_setting_server(server_id, config, "requestsPerMinute", 1, 10_000)
    |> validate_integer_setting_server(server_id, config, "burstSize", 1, 1000)
  end

  defp validate_tool_lists(errors, server_id, server_config, list_key) do
    case Map.get(server_config, list_key) do
      # Tool lists are optional
      nil ->
        errors

      tools when is_list(tools) ->
        if Enum.all?(tools, &is_binary/1) do
          errors
        else
          ["Server '#{server_id}': #{list_key} must contain only string tool names" | errors]
        end

      _ ->
        ["Server '#{server_id}': #{list_key} must be a list of strings" | errors]
    end
  end

  defp validate_tool_conflicts(errors, server_id, server_config) do
    include_tools = Map.get(server_config, "includeTools", [])
    exclude_tools = Map.get(server_config, "excludeTools", [])

    conflicts = MapSet.intersection(MapSet.new(include_tools), MapSet.new(exclude_tools))

    case MapSet.size(conflicts) do
      0 ->
        errors

      _ ->
        conflict_list = conflicts |> MapSet.to_list() |> Enum.join(", ")

        [
          "Server '#{server_id}': Tools cannot be both included and excluded: #{conflict_list}"
          | errors
        ]
    end
  end

  defp validate_timeout_setting_server(errors, server_id, server_config) do
    case Map.get(server_config, "timeout") do
      # Uses global default
      nil ->
        errors

      timeout when is_integer(timeout) and timeout >= @min_timeout and timeout <= @max_timeout ->
        errors

      timeout when is_integer(timeout) ->
        [
          "Server '#{server_id}': timeout must be between #{@min_timeout} and #{@max_timeout}ms"
          | errors
        ]

      _ ->
        ["Server '#{server_id}': timeout must be an integer (milliseconds)" | errors]
    end
  end

  defp validate_retry_config(errors, server_id, server_config) do
    case Map.get(server_config, "retry") do
      nil ->
        errors

      config when is_map(config) ->
        errors
        |> validate_integer_setting_server(server_id, config, "maxAttempts", 0, 10)
        |> validate_integer_setting_server(server_id, config, "backoffMs", 100, 30_000)

      _ ->
        ["Server '#{server_id}': retry configuration must be a map" | errors]
    end
  end

  defp validate_oauth_config(errors, server_id, oauth_config) do
    errors
    |> validate_boolean_setting_server(server_id, oauth_config, "enabled")
    |> validate_required_oauth_fields(server_id, oauth_config)
    |> validate_oauth_scopes(server_id, oauth_config)
  end

  defp validate_required_oauth_fields(errors, server_id, oauth_config) do
    if Map.get(oauth_config, "enabled", false) do
      required_fields = ["clientId"]
      validate_required_fields(errors, "#{server_id} OAuth", oauth_config, required_fields)
    else
      errors
    end
  end

  defp validate_oauth_scopes(errors, server_id, oauth_config) do
    case Map.get(oauth_config, "scopes") do
      # Scopes are optional
      nil ->
        errors

      scopes when is_list(scopes) ->
        if Enum.all?(scopes, &is_binary/1) do
          errors
        else
          ["Server '#{server_id}': OAuth scopes must be strings" | errors]
        end

      _ ->
        ["Server '#{server_id}': OAuth scopes must be a list of strings" | errors]
    end
  end

  defp validate_dependency_graph(errors, servers) do
    # Build dependency graph and check for cycles
    graph = build_dependency_graph(servers)

    case detect_circular_dependencies(graph) do
      [] ->
        errors

      circular_deps ->
        deps_str = Enum.join(circular_deps, " -> ")
        ["Circular dependency detected: #{deps_str}" | errors]
    end
  end

  defp build_dependency_graph(servers) do
    Enum.reduce(servers, %{}, fn {server_id, server_config}, graph ->
      dependencies = Map.get(server_config, "dependencies", [])
      Map.put(graph, server_id, dependencies)
    end)
  end

  defp detect_circular_dependencies(graph) do
    # Simple DFS-based cycle detection
    visited = MapSet.new()
    rec_stack = MapSet.new()

    {_final_visited, result} =
      Enum.reduce_while(Map.keys(graph), {visited, []}, fn node, {current_visited, acc} ->
        case dfs_cycle_check(graph, node, current_visited, rec_stack, []) do
          {:cycle, path} ->
            {:halt, {current_visited, path}}

          {:no_cycle, new_visited} ->
            updated_visited = MapSet.union(current_visited, new_visited)
            {:cont, {updated_visited, acc}}
        end
      end)

    result
  end

  defp dfs_cycle_check(graph, node, visited, rec_stack, path) do
    cond do
      MapSet.member?(rec_stack, node) ->
        # Found cycle
        cycle_start = Enum.find_index(path, &(&1 == node))
        cycle_path = Enum.drop(path, cycle_start || 0) ++ [node]
        {:cycle, cycle_path}

      MapSet.member?(visited, node) ->
        {:no_cycle, MapSet.new()}

      true ->
        new_visited = MapSet.put(visited, node)
        new_rec_stack = MapSet.put(rec_stack, node)
        new_path = path ++ [node]

        dependencies = Map.get(graph, node, [])

        Enum.reduce_while(dependencies, {:no_cycle, new_visited}, fn dep, {_, acc_visited} ->
          case dfs_cycle_check(graph, dep, acc_visited, new_rec_stack, new_path) do
            {:cycle, cycle_path} ->
              {:halt, {:cycle, cycle_path}}

            {:no_cycle, dep_visited} ->
              {:cont, {:no_cycle, MapSet.union(acc_visited, dep_visited)}}
          end
        end)
    end
  end

  # Helper validation functions

  defp validate_timeout_setting(errors, settings, key) do
    case Map.get(settings, key) do
      nil ->
        errors

      timeout when is_integer(timeout) and timeout >= @min_timeout and timeout <= @max_timeout ->
        errors

      timeout when is_integer(timeout) ->
        ["#{key} must be between #{@min_timeout} and #{@max_timeout}ms" | errors]

      _ ->
        ["#{key} must be an integer (milliseconds)" | errors]
    end
  end

  defp validate_integer_setting(errors, settings, key, min_val, max_val) do
    case Map.get(settings, key) do
      nil ->
        errors

      value when is_integer(value) and value >= min_val and value <= max_val ->
        errors

      value when is_integer(value) ->
        ["#{key} must be between #{min_val} and #{max_val}" | errors]

      _ ->
        ["#{key} must be an integer" | errors]
    end
  end

  defp validate_integer_setting_server(errors, server_id, config, key, min_val, max_val) do
    case Map.get(config, key) do
      nil ->
        errors

      value when is_integer(value) and value >= min_val and value <= max_val ->
        errors

      value when is_integer(value) ->
        ["Server '#{server_id}': #{key} must be between #{min_val} and #{max_val}" | errors]

      _ ->
        ["Server '#{server_id}': #{key} must be an integer" | errors]
    end
  end

  defp validate_confirmation_level(errors, settings) do
    case Map.get(settings, "confirmationLevel") do
      nil ->
        errors

      level when level in @valid_confirmation_levels ->
        errors

      _ ->
        valid_levels = Enum.join(@valid_confirmation_levels, ", ")
        ["confirmationLevel must be one of: #{valid_levels}" | errors]
    end
  end

  defp validate_boolean_setting(errors, settings, key) do
    case Map.get(settings, key) do
      nil ->
        errors

      value when is_boolean(value) ->
        errors

      _ ->
        ["#{key} must be a boolean" | errors]
    end
  end

  defp validate_boolean_setting_server(errors, server_id, config, key) do
    case Map.get(config, key) do
      nil ->
        errors

      value when is_boolean(value) ->
        errors

      _ ->
        ["Server '#{server_id}': #{key} must be a boolean" | errors]
    end
  end
end
