defmodule TheMaestro.MCP.Config.ConfigParser do
  @moduledoc """
  Configuration file parsing and encoding module.

  Supports multiple configuration formats including JSON and YAML,
  with automatic format detection and comprehensive error handling.
  """

  require Logger

  @type format :: :json | :yaml
  @type config :: map()

  @doc """
  Parse configuration content in the specified format.

  ## Examples

      iex> json_content = ~s({"mcpServers": {"test": {"command": "python"}}})
      iex> {:ok, config} = ConfigParser.parse(json_content, :json)
      iex> config["mcpServers"]["test"]["command"]
      "python"
  """
  @spec parse(String.t(), format()) :: {:ok, config()} | {:error, term()}
  def parse(content, :json) do
    case Jason.decode(content) do
      {:ok, config} -> {:ok, config}
      {:error, error} -> {:error, {:json_decode_error, error}}
    end
  end

  def parse(content, :yaml) do
    try do
      case YamlElixir.read_from_string(content) do
        {:ok, config} -> {:ok, config}
        {:error, error} -> {:error, {:yaml_decode_error, error}}
      end
    rescue
      error -> {:error, {:yaml_decode_error, error}}
    end
  end

  @doc """
  Parse configuration from file.

  Automatically detects format from file extension.
  """
  @spec parse_file(String.t()) :: {:ok, config()} | {:error, term()}
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} ->
        format = detect_format(path)
        parse(content, format)

      error ->
        error
    end
  end

  @doc """
  Encode configuration in the specified format.

  ## Examples

      iex> config = %{"test" => "value"}
      iex> {:ok, json} = ConfigParser.encode(config, :json)
      iex> json
      ~s({"test":"value"})
  """
  @spec encode(config(), format()) :: {:ok, String.t()} | {:error, term()}
  def encode(config, :json) do
    case Jason.encode(config, pretty: true) do
      {:ok, content} -> {:ok, content}
      {:error, error} -> {:error, {:json_encode_error, error}}
    end
  end

  def encode(config, :yaml) do
    try do
      content = Ymlr.document!(config)
      {:ok, content}
    rescue
      error -> {:error, {:yaml_encode_error, error}}
    end
  end

  @doc """
  Detect configuration format from file extension.

  ## Examples

      iex> ConfigParser.detect_format("config.json")
      :json
      
      iex> ConfigParser.detect_format("config.yaml")
      :yaml
      
      iex> ConfigParser.detect_format("config.yml")  
      :yaml
      
      iex> ConfigParser.detect_format("unknown.txt")
      :json  # Default to JSON
  """
  @spec detect_format(String.t()) :: format()
  def detect_format(path) do
    case Path.extname(path) do
      ".json" -> :json
      ".yaml" -> :yaml
      ".yml" -> :yaml
      # Default to JSON
      _ -> :json
    end
  end

  @doc """
  Merge multiple configurations with proper precedence.

  Later configurations override earlier ones. Deep merging is performed
  for maps, and arrays are concatenated and deduplicated.

  ## Examples

      iex> base = %{"servers" => %{"s1" => %{"trust" => false}}}
      iex> override = %{"servers" => %{"s1" => %{"trust" => true}}}
      iex> ConfigParser.merge_configs([base, override])
      %{"servers" => %{"s1" => %{"trust" => true}}}
  """
  @spec merge_configs([config()]) :: config()
  def merge_configs([]), do: %{}
  def merge_configs([single_config]), do: single_config

  def merge_configs([first | rest]) do
    Enum.reduce(rest, first, &deep_merge(&2, &1))
  end

  @doc """
  Normalize configuration keys to ensure consistency.

  Converts string keys to consistent format and handles
  legacy configuration formats.
  """
  @spec normalize_config(config()) :: config()
  def normalize_config(config) when is_map(config) do
    config
    |> normalize_server_keys()
    |> normalize_global_settings()
    |> normalize_transport_keys()
  end

  ## Private Functions

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, left_val, right_val when is_list(left_val) and is_list(right_val) ->
        merge_lists(left_val, right_val)

      _key, _left_val, right_val ->
        right_val
    end)
  end

  defp deep_merge(_left, right), do: right

  defp merge_lists(left, right) do
    (left ++ right)
    |> Enum.uniq()
  end

  defp normalize_server_keys(config) do
    case Map.get(config, "mcpServers") do
      nil ->
        config

      servers when is_map(servers) ->
        normalized_servers =
          Enum.into(servers, %{}, fn {server_id, server_config} ->
            {server_id, normalize_server_config(server_config)}
          end)

        Map.put(config, "mcpServers", normalized_servers)

      _ ->
        config
    end
  end

  defp normalize_server_config(server_config) when is_map(server_config) do
    server_config
    |> normalize_transport_config()
    |> normalize_tool_lists()
    |> normalize_security_settings()
  end

  defp normalize_transport_config(config) do
    # Handle legacy transport configurations
    cond do
      Map.has_key?(config, "stdio") ->
        stdio_config = Map.get(config, "stdio")

        config
        |> Map.delete("stdio")
        |> Map.merge(stdio_config)

      Map.has_key?(config, "sse") ->
        sse_config = Map.get(config, "sse")

        config
        |> Map.delete("sse")
        |> Map.merge(sse_config)

      Map.has_key?(config, "http") ->
        http_config = Map.get(config, "http")

        config
        |> Map.delete("http")
        |> Map.merge(http_config)

      true ->
        config
    end
  end

  defp normalize_tool_lists(config) do
    config
    |> normalize_tool_list("includeTools")
    |> normalize_tool_list("excludeTools")
  end

  defp normalize_tool_list(config, key) do
    case Map.get(config, key) do
      nil ->
        config

      tools when is_list(tools) ->
        Map.put(config, key, Enum.map(tools, &to_string/1))

      tools when is_binary(tools) ->
        # Handle comma-separated strings
        tool_list =
          tools
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(config, key, tool_list)

      _ ->
        config
    end
  end

  defp normalize_security_settings(config) do
    # Normalize trust settings
    config =
      case Map.get(config, "trust") do
        nil ->
          config

        trust when is_binary(trust) ->
          Map.put(config, "trust", trust == "true")

        trust when is_boolean(trust) ->
          config

        _ ->
          Map.put(config, "trust", false)
      end

    # Normalize confirmation level
    case Map.get(config, "confirmationLevel") do
      nil ->
        config

      level when level in ["low", "medium", "high"] ->
        config

      level when is_binary(level) ->
        normalized_level = String.downcase(level)

        if normalized_level in ["low", "medium", "high"] do
          Map.put(config, "confirmationLevel", normalized_level)
        else
          Map.put(config, "confirmationLevel", "medium")
        end

      _ ->
        Map.put(config, "confirmationLevel", "medium")
    end
  end

  defp normalize_global_settings(config) do
    case Map.get(config, "globalSettings") do
      nil ->
        config

      settings when is_map(settings) ->
        normalized_settings = normalize_global_setting_values(settings)
        Map.put(config, "globalSettings", normalized_settings)

      _ ->
        config
    end
  end

  defp normalize_global_setting_values(settings) do
    settings
    |> normalize_timeout_setting("defaultTimeout")
    |> normalize_timeout_setting("healthCheckInterval")
    |> normalize_boolean_setting("auditLogging")
    |> normalize_boolean_setting("autoReconnect")
    |> normalize_confirmation_level_setting()
  end

  defp normalize_timeout_setting(settings, key) do
    case Map.get(settings, key) do
      nil ->
        settings

      value when is_integer(value) and value > 0 ->
        settings

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int_val, ""} when int_val > 0 ->
            Map.put(settings, key, int_val)

          _ ->
            Logger.warning("Invalid timeout value for #{key}: #{value}, using default")
            Map.delete(settings, key)
        end

      _ ->
        Logger.warning("Invalid timeout value for #{key}, using default")
        Map.delete(settings, key)
    end
  end

  defp normalize_boolean_setting(settings, key) do
    case Map.get(settings, key) do
      nil ->
        settings

      value when is_boolean(value) ->
        settings

      value when is_binary(value) ->
        Map.put(settings, key, value == "true")

      _ ->
        settings
    end
  end

  defp normalize_confirmation_level_setting(settings) do
    case Map.get(settings, "confirmationLevel") do
      nil ->
        settings

      level when level in ["low", "medium", "high"] ->
        settings

      level when is_binary(level) ->
        normalized = String.downcase(level)

        if normalized in ["low", "medium", "high"] do
          Map.put(settings, "confirmationLevel", normalized)
        else
          Map.put(settings, "confirmationLevel", "medium")
        end

      _ ->
        Map.put(settings, "confirmationLevel", "medium")
    end
  end

  defp normalize_transport_keys(config) do
    # Ensure consistent transport key naming
    config
    |> handle_http_url_variants()
    |> handle_sse_url_variants()
  end

  defp handle_http_url_variants(config) do
    cond do
      Map.has_key?(config, "httpUrl") ->
        config

      Map.has_key?(config, "http_url") ->
        url = Map.get(config, "http_url")

        config
        |> Map.delete("http_url")
        |> Map.put("httpUrl", url)

      Map.has_key?(config, "baseUrl") ->
        url = Map.get(config, "baseUrl")

        config
        |> Map.delete("baseUrl")
        |> Map.put("httpUrl", url)

      true ->
        config
    end
  end

  defp handle_sse_url_variants(config) do
    cond do
      Map.has_key?(config, "url") ->
        config

      Map.has_key?(config, "sse_url") ->
        url = Map.get(config, "sse_url")

        config
        |> Map.delete("sse_url")
        |> Map.put("url", url)

      true ->
        config
    end
  end
end
