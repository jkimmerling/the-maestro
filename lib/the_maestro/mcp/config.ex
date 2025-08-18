defmodule TheMaestro.MCP.Config do
  @moduledoc """
  MCP Configuration Management System

  This module provides comprehensive configuration management for MCP servers,
  including file-based configuration loading, validation, environment variable
  resolution, configuration merging, and runtime configuration updates.

  ## Features

  - Multi-format configuration support (JSON, YAML)
  - Environment variable resolution with defaults
  - Configuration inheritance and merging
  - Runtime configuration updates
  - Comprehensive validation
  - Hot configuration reloading
  - Template-based configuration

  ## Configuration Structure

  ```json
  {
    "mcpServers": {
      "serverName": {
        "command": "python",
        "args": ["-m", "server"],
        "env": {"VAR": "$ENV_VAR"},
        "trust": false,
        "includeTools": ["tool1"],
        "excludeTools": ["tool2"]
      }
    },
    "globalSettings": {
      "defaultTimeout": 30000,
      "confirmationLevel": "medium"
    }
  }
  ```
  """

  require Logger

  alias TheMaestro.MCP.Config.{ConfigParser, ConfigValidator, EnvResolver}

  @type config :: map()
  @type server_config :: map()
  @type validation_result :: {:ok, config()} | {:error, [String.t()]}

  # Default configuration paths
  @global_config_path "~/.maestro/mcp_settings.json"
  @project_config_path "./.maestro/mcp_settings.json"
  @default_config_paths [@global_config_path, @project_config_path]

  # Configuration change notifications
  @config_topic "mcp:config:changed"

  ## Public API

  @doc """
  Load configuration from file(s).

  Supports loading from a single file or multiple files for inheritance.
  Files are merged in order with later files taking precedence.

  ## Examples

      # Load from single file
      {:ok, config} = Config.load_configuration("./mcp_settings.json")
      
      # Load with inheritance
      {:ok, config} = Config.load_configuration([
        "~/.maestro/mcp_settings.json",
        "./mcp_settings.json"
      ])
      
      # Load from default paths
      {:ok, config} = Config.load_configuration()
  """
  @spec load_configuration(String.t() | [String.t()] | nil) ::
          {:ok, config()} | {:error, term()}
  def load_configuration(path \\ nil)

  def load_configuration(nil) do
    load_configuration(@default_config_paths)
  end

  def load_configuration(path) when is_binary(path) do
    # For single file, we require it to exist
    expanded_path = expand_path(path)

    unless File.exists?(expanded_path) do
      {:error, :file_not_found}
    else
      case load_single_config(expanded_path) do
        {:ok, config} ->
          resolved_config = resolve_environment_variables(config)

          case validate_configuration(resolved_config) do
            {:ok, validated_config} ->
              {:ok, validated_config}

            error ->
              error
          end

        error ->
          error
      end
    end
  end

  def load_configuration(paths) when is_list(paths) do
    case load_multiple_configs(paths) do
      {:ok, configs} ->
        merged_config = merge_configurations(configs)
        resolved_config = resolve_environment_variables(merged_config)

        case validate_configuration(resolved_config) do
          {:ok, validated_config} ->
            {:ok, validated_config}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Validate configuration structure and content.

  Performs comprehensive validation including:
  - Schema validation
  - Transport-specific validation  
  - Dependency checking
  - Security validation
  - URL format validation
  """
  @spec validate_configuration(config()) :: validation_result()
  def validate_configuration(config) do
    ConfigValidator.validate(config)
  end

  @doc """
  Resolve environment variables in configuration.

  Supports multiple syntax forms:
  - `$VAR` - Simple substitution
  - `${VAR}` - Braced substitution  
  - `${VAR:-default}` - With default value
  - `${VAR}:/custom` - Path expansion
  """
  @spec resolve_environment_variables(config()) :: config()
  def resolve_environment_variables(config) do
    EnvResolver.resolve_config(config)
  end

  @doc """
  Merge multiple configurations with proper precedence.

  Later configurations in the list override earlier ones.
  Arrays are merged (not replaced), maps are deep-merged.
  """
  @spec merge_configurations([config()]) :: config()
  def merge_configurations(configs) do
    ConfigParser.merge_configs(configs)
  end

  @doc """
  Get configuration for a specific server.
  """
  @spec get_server_config(config(), String.t()) ::
          {:ok, server_config()} | {:error, :not_found}
  def get_server_config(config, server_name) do
    case get_in(config, ["mcpServers", server_name]) do
      nil -> {:error, :not_found}
      server_config -> {:ok, server_config}
    end
  end

  @doc """
  Update configuration for a specific server.

  Updates are merged with existing configuration.
  """
  @spec update_server_config(config(), String.t(), map()) ::
          config() | {:error, :server_not_found}
  def update_server_config(config, server_name, updates) do
    case get_in(config, ["mcpServers", server_name]) do
      nil ->
        {:error, :server_not_found}

      existing_config ->
        updated_server_config = deep_merge(existing_config, updates)
        put_in(config, ["mcpServers", server_name], updated_server_config)
    end
  end

  @doc """
  Add a new server to configuration.
  """
  @spec add_server_config(config(), String.t(), server_config()) ::
          config() | {:error, :server_exists}
  def add_server_config(config, server_name, server_config) do
    servers = get_in(config, ["mcpServers"]) || %{}

    if Map.has_key?(servers, server_name) do
      {:error, :server_exists}
    else
      put_in(config, ["mcpServers", server_name], server_config)
    end
  end

  @doc """
  Remove a server from configuration.
  """
  @spec remove_server_config(config(), String.t()) ::
          config() | {:error, :server_not_found}
  def remove_server_config(config, server_name) do
    servers = get_in(config, ["mcpServers"]) || %{}

    if Map.has_key?(servers, server_name) do
      updated_servers = Map.delete(servers, server_name)
      put_in(config, ["mcpServers"], updated_servers)
    else
      {:error, :server_not_found}
    end
  end

  @doc """
  Save configuration to default project location.
  """
  @spec save_configuration(config()) :: :ok | {:error, term()}
  def save_configuration(config) do
    save_configuration(config, @project_config_path)
  end

  @doc """
  Save configuration to file.

  Automatically detects format from file extension.
  """
  @spec save_configuration(config(), String.t()) :: :ok | {:error, term()}
  def save_configuration(config, path) do
    format = ConfigParser.detect_format(path)

    case ConfigParser.encode(config, format) do
      {:ok, content} ->
        # Ensure directory exists
        path |> Path.dirname() |> File.mkdir_p!()

        case File.write(path, content) do
          :ok ->
            Logger.info("Configuration saved to #{path}")
            :ok

          error ->
            Logger.error("Failed to save configuration to #{path}: #{inspect(error)}")
            error
        end

      error ->
        error
    end
  end

  @doc """
  Reload configuration from default paths and notify subscribers.
  """
  @spec reload_configuration() :: :ok | {:error, term()}
  def reload_configuration do
    case load_configuration() do
      {:ok, new_config} ->
        # Store in persistent term for quick access
        :persistent_term.put({__MODULE__, :config}, new_config)

        # Notify subscribers of configuration change
        Phoenix.PubSub.broadcast(
          TheMaestro.PubSub,
          @config_topic,
          {:config_changed, new_config}
        )

        Logger.info("Configuration reloaded successfully")
        :ok

      error ->
        Logger.error("Failed to reload configuration: #{inspect(error)}")
        error
    end
  end

  @doc """
  Get current cached configuration.

  Returns cached configuration or loads from default paths if not cached.
  """
  @spec get_configuration() :: {:ok, config()} | {:error, term()}
  def get_configuration do
    case :persistent_term.get({__MODULE__, :config}, nil) do
      nil ->
        case load_configuration() do
          {:ok, config} ->
            :persistent_term.put({__MODULE__, :config}, config)
            {:ok, config}

          error ->
            error
        end

      config ->
        {:ok, config}
    end
  end

  @doc """
  Subscribe to configuration change notifications.
  """
  @spec subscribe_to_config_changes() :: :ok
  def subscribe_to_config_changes do
    Phoenix.PubSub.subscribe(TheMaestro.PubSub, @config_topic)
  end

  @doc """
  Apply a configuration template with variable substitution.

  Templates use `{variable}` syntax for substitution.
  """
  @spec apply_template(map(), map()) :: map()
  def apply_template(template, variables) do
    TheMaestro.MCP.Config.TemplateParser.apply_template(template, variables)
  end

  @doc """
  Get available configuration templates.
  """
  @spec get_templates() :: {:ok, map()} | {:error, term()}
  def get_templates do
    templates_path =
      Path.join([
        Application.get_env(:the_maestro, :config_dir, "~/.maestro"),
        "templates.json"
      ])

    case File.read(Path.expand(templates_path)) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, templates} -> {:ok, templates}
          error -> error
        end

      {:error, :enoent} ->
        {:ok, get_default_templates()}

      error ->
        error
    end
  end

  ## Private Functions

  defp load_multiple_configs(paths) do
    {configs, errors} =
      paths
      |> Enum.map(&expand_path/1)
      |> Enum.filter(&File.exists?/1)
      |> Enum.map(&load_single_config/1)
      |> Enum.split_with(&match?({:ok, _}, &1))

    if length(errors) > 0 and length(configs) == 0 do
      {:error, :file_not_found}
    else
      successful_configs = Enum.map(configs, fn {:ok, config} -> config end)
      {:ok, successful_configs}
    end
  end

  defp load_single_config(path) do
    case File.read(path) do
      {:ok, content} ->
        format = ConfigParser.detect_format(path)

        case ConfigParser.parse(content, format) do
          {:ok, config} ->
            Logger.debug("Loaded configuration from #{path}")
            {:ok, config}

          error ->
            Logger.warning("Failed to parse configuration from #{path}: #{inspect(error)}")
            error
        end

      {:error, :enoent} ->
        Logger.debug("Configuration file not found: #{path}")
        {:error, :file_not_found}

      error ->
        Logger.error("Failed to read configuration from #{path}: #{inspect(error)}")
        error
    end
  end

  defp expand_path(path) do
    path
    |> Path.expand()
    |> String.replace("~", System.user_home!())
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, left_val, right_val when is_list(left_val) and is_list(right_val) ->
        Enum.uniq(left_val ++ right_val)

      _key, _left_val, right_val ->
        right_val
    end)
  end

  defp deep_merge(_left, right), do: right

  defp get_default_templates do
    %{
      "python-stdio" => %{
        "command" => "python",
        "args" => ["-m", "{module_name}"],
        "timeout" => 30000,
        "trust" => false,
        "description" => "Python STDIO MCP server template"
      },
      "node-stdio" => %{
        "command" => "node",
        "args" => ["{script_path}"],
        "timeout" => 30000,
        "trust" => false,
        "description" => "Node.js STDIO MCP server template"
      },
      "http-api" => %{
        "httpUrl" => "{base_url}/mcp",
        "headers" => %{
          "Authorization" => "Bearer {api_token}",
          "Content-Type" => "application/json"
        },
        "timeout" => 15000,
        "trust" => false,
        "description" => "HTTP API MCP server template"
      },
      "sse-stream" => %{
        "url" => "{base_url}/sse",
        "headers" => %{
          "Authorization" => "Bearer {api_token}",
          "User-Agent" => "TheMaestro/1.0"
        },
        "timeout" => 10000,
        "trust" => true,
        "description" => "Server-Sent Events MCP server template"
      }
    }
  end
end
