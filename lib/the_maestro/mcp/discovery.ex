defmodule TheMaestro.MCP.Discovery do
  @moduledoc """
  MCP Server Discovery and Configuration Management

  This module handles discovering MCP servers from configuration files,
  validating their configurations, and starting server connections.
  """

  require Logger

  alias TheMaestro.MCP.Transport.HTTP
  alias TheMaestro.MCP.Transport.SSE
  alias TheMaestro.MCP.Transport.Stdio

  @type server_config :: %{
          id: String.t(),
          transport: :stdio | :sse | :http,
          command: String.t() | nil,
          args: [String.t()] | nil,
          env: map() | nil,
          url: String.t() | nil,
          headers: map() | nil,
          method: String.t() | nil,
          trust: boolean(),
          priority: integer() | nil,
          heartbeat_interval: integer() | nil,
          max_failures: integer() | nil,
          failure_window: integer() | nil
        }

  @type validation_error ::
          :missing_id
          | :unknown_transport
          | :missing_command
          | :missing_url
          | :invalid_env
          | :invalid_args

  @doc """
  Discover servers from an MCP configuration file.

  ## Parameters

  * `config_path` - Path to the MCP configuration JSON file

  ## Returns

  * `{:ok, [server_config]}` - Successfully loaded server configurations
  * `{:error, term()}` - Error loading or parsing configuration

  ## Examples

      iex> Discovery.discover_servers("/path/to/mcp_settings.json")
      {:ok, [%{id: "fileSystem", transport: :stdio, ...}]}
  """
  @spec discover_servers(String.t()) :: {:ok, [server_config()]} | {:error, term()}
  def discover_servers(config_path) do
    Logger.debug("Discovering MCP servers from config: #{config_path}")

    with {:ok, content} <- read_config_file(config_path),
         {:ok, parsed} <- parse_json(content),
         {:ok, servers} <- extract_servers(parsed) do
      Logger.info("Discovered #{length(servers)} MCP servers")
      {:ok, servers}
    else
      {:error, :enoent} ->
        Logger.error("MCP config file not found: #{config_path}")
        {:error, :file_not_found}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("Invalid JSON in MCP config: #{inspect(error)}")
        {:error, {:invalid_json, error}}

      {:error, reason} = error ->
        Logger.error("Error discovering MCP servers: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Validate an MCP server configuration.

  ## Parameters

  * `config` - Raw server configuration map from JSON

  ## Returns

  * `{:ok, server_config}` - Validated and normalized configuration
  * `{:error, [validation_error]}` - List of validation errors

  ## Examples

      iex> config = %{"id" => "test", "command" => "python", "args" => ["-m", "server"]}
      iex> Discovery.validate_server_config(config)
      {:ok, %{id: "test", transport: :stdio, command: "python", args: ["-m", "server"], ...}}
  """
  @spec validate_server_config(map()) :: {:ok, server_config()} | {:error, [validation_error()]}
  def validate_server_config(config) do
    Logger.debug("Validating server config: #{inspect(config)}")

    errors = []

    with {:ok, id, errors} <- validate_id(config, errors),
         {:ok, transport, errors} <- detect_transport(config, errors),
         {:ok, validated_config, errors} <-
           validate_transport_specific(config, transport, errors),
         {:ok, final_config, errors} <- validate_common_fields(validated_config, errors) do
      if errors == [] do
        result = Map.merge(final_config, %{id: id, transport: transport})
        Logger.debug("Server config validation successful")
        {:ok, result}
      else
        Logger.warning("Server config validation failed: #{inspect(errors)}")
        {:error, errors}
      end
    else
      {:error, errors} ->
        Logger.warning("Server config validation failed: #{inspect(errors)}")
        {:error, errors}
    end
  end

  @doc """
  Start a connection to an MCP server based on its configuration.

  ## Parameters

  * `server_config` - Validated server configuration

  ## Returns

  * `{:ok, pid()}` - Successfully started connection process
  * `{:error, term()}` - Error starting connection

  ## Examples

      iex> config = %{id: "test", transport: :stdio, command: "echo", args: ["test"]}
      iex> Discovery.start_server_connection(config)
      {:ok, #PID<0.123.0>}
  """
  @spec start_server_connection(server_config()) :: {:ok, pid()} | {:error, term()}
  def start_server_connection(server_config) do
    Logger.info("Starting MCP server connection: #{server_config.id}")

    case server_config.transport do
      :stdio ->
        start_stdio_connection(server_config)

      :sse ->
        start_sse_connection(server_config)

      :http ->
        start_http_connection(server_config)

      transport ->
        Logger.error("Unsupported transport type: #{transport}")
        {:error, {:unsupported_transport, transport}}
    end
  end

  # Private helper functions

  defp read_config_file(path) do
    File.read(path)
  end

  defp parse_json(content) do
    Jason.decode(content)
  end

  defp extract_servers(%{"mcpServers" => servers}) when is_map(servers) do
    server_configs =
      Enum.reduce(servers, [], fn {id, config}, acc ->
        case validate_server_config(Map.put(config, "id", id)) do
          {:ok, validated} ->
            [validated | acc]

          {:error, errors} ->
            Logger.warning("Skipping invalid server #{id}: #{inspect(errors)}")
            acc
        end
      end)

    {:ok, Enum.reverse(server_configs)}
  end

  defp extract_servers(%{}) do
    {:ok, []}
  end

  defp extract_servers(_) do
    {:error, :invalid_config_format}
  end

  defp validate_id(%{"id" => id}, errors) when is_binary(id), do: {:ok, id, errors}
  defp validate_id(_, errors), do: {:error, [:missing_id | errors]}

  defp detect_transport(config, errors) do
    cond do
      Map.has_key?(config, "command") ->
        {:ok, :stdio, errors}

      Map.has_key?(config, "url") ->
        # Determine if SSE or HTTP based on usage patterns
        if Map.get(config, "method") do
          {:ok, :http, errors}
        else
          {:ok, :sse, errors}
        end

      true ->
        {:error, [:unknown_transport | errors]}
    end
  end

  defp validate_transport_specific(config, :stdio, errors) do
    errors =
      case Map.get(config, "command") do
        command when is_binary(command) -> errors
        _ -> [:missing_command | errors]
      end

    args = Map.get(config, "args", [])
    env = resolve_env_vars(Map.get(config, "env", %{}))

    validated =
      config
      |> Map.put(:command, Map.get(config, "command"))
      |> Map.put(:args, args)
      |> Map.put(:env, env)

    if errors == [] do
      {:ok, validated, errors}
    else
      {:error, errors}
    end
  end

  defp validate_transport_specific(config, :sse, errors) do
    errors =
      case Map.get(config, "url") do
        url when is_binary(url) -> errors
        _ -> [:missing_url | errors]
      end

    validated =
      config
      |> Map.put(:url, Map.get(config, "url"))
      |> Map.put(:headers, Map.get(config, "headers", %{}))

    if errors == [] do
      {:ok, validated, errors}
    else
      {:error, errors}
    end
  end

  defp validate_transport_specific(config, :http, errors) do
    errors =
      case Map.get(config, "url") do
        url when is_binary(url) -> errors
        _ -> [:missing_url | errors]
      end

    validated =
      config
      |> Map.put(:url, Map.get(config, "url"))
      |> Map.put(:method, Map.get(config, "method", "POST"))
      |> Map.put(:headers, Map.get(config, "headers", %{}))

    if errors == [] do
      {:ok, validated, errors}
    else
      {:error, errors}
    end
  end

  defp validate_common_fields(config, errors) do
    # Preserve trust from original config if it was explicitly set
    original_trust = Map.get(config, "trust", false)

    validated_config =
      config
      |> Map.put(:trust, original_trust)
      |> Map.put(:priority, Map.get(config, "priority", 5))
      |> Map.put(:heartbeat_interval, Map.get(config, "heartbeat_interval", 30_000))
      |> Map.put(:max_failures, Map.get(config, "max_failures", 3))
      |> Map.put(:failure_window, Map.get(config, "failure_window", 60_000))

    {:ok, validated_config, errors}
  end

  defp resolve_env_vars(env) when is_map(env) do
    Enum.reduce(env, %{}, fn {key, value}, acc ->
      resolved_value = resolve_env_var(value)
      Map.put(acc, key, resolved_value)
    end)
  end

  defp resolve_env_vars(env), do: env

  defp resolve_env_var(value) do
    case value do
      "${" <> rest ->
        case String.split(rest, "}", parts: 2) do
          [env_var, _] ->
            System.get_env(env_var) || ""

          _ ->
            rest
        end

      "$" <> env_var ->
        System.get_env(env_var, "")

      _ ->
        value
    end
  end

  defp start_stdio_connection(config) do
    transport_config = %{
      command: Map.get(config, :command),
      args: Map.get(config, :args, []),
      env: Map.get(config, :env, %{}),
      cwd: Map.get(config, :cwd, File.cwd!())
    }

    try do
      case Stdio.start(transport_config) do
        {:ok, transport_pid} ->
          # Create a connection GenServer that manages this transport
          connection_config = %{
            server_id: config.id,
            transport_pid: transport_pid,
            transport_type: :stdio,
            server_config: config
          }

          {:ok, connection_pid} = start_connection_manager(connection_config)
          Logger.info("Successfully started stdio connection for #{config.id}")
          {:ok, connection_pid}

        {:error, reason} ->
          Logger.error("Failed to start stdio transport for #{config.id}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Failed to start stdio transport (exception): #{inspect(error)}")
        {:error, {:exception, error}}
    catch
      :exit, reason ->
        Logger.error("Failed to start stdio transport (exit): #{inspect(reason)}")
        {:error, {:exit, reason}}
    end
  end

  defp start_sse_connection(config) do
    transport_config = %{
      url: config.url,
      headers: config.headers || %{}
    }

    case SSE.start_link(transport_config) do
      {:ok, transport_pid} ->
        connection_config = %{
          server_id: config.id,
          transport_pid: transport_pid,
          transport_type: :sse,
          server_config: config
        }

        {:ok, connection_pid} = start_connection_manager(connection_config)
        Logger.info("Successfully started SSE connection for #{config.id}")
        {:ok, connection_pid}

      {:error, reason} ->
        Logger.error("Failed to start SSE transport for #{config.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_http_connection(config) do
    transport_config = %{
      url: config.url,
      method: config.method || "POST",
      headers: config.headers || %{}
    }

    case HTTP.start_link(transport_config) do
      {:ok, transport_pid} ->
        connection_config = %{
          server_id: config.id,
          transport_pid: transport_pid,
          transport_type: :http,
          server_config: config
        }

        {:ok, connection_pid} = start_connection_manager(connection_config)
        Logger.info("Successfully started HTTP connection for #{config.id}")
        {:ok, connection_pid}

      {:error, reason} ->
        Logger.error("Failed to start HTTP transport for #{config.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_connection_manager(connection_config) do
    # For now, return the transport PID directly
    # Later this will be replaced with a proper connection manager GenServer
    {:ok, connection_config.transport_pid}
  end
end
