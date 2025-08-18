defmodule TheMaestro.MCP.Security.ParameterSanitizer do
  @moduledoc """
  Parameter sanitization and validation for MCP tool execution security.

  Provides comprehensive sanitization and validation of tool parameters to
  prevent various security vulnerabilities including:

  - Path traversal attacks
  - Command injection
  - SQL injection
  - Script injection
  - Buffer overflow attempts
  - Malformed data attacks

  ## Sanitization Types

  - **Path sanitization**: Prevents directory traversal and validates file paths
  - **Command sanitization**: Prevents command injection in shell parameters
  - **Data sanitization**: Sanitizes text data to prevent script injection
  - **URL sanitization**: Validates and sanitizes URLs and network endpoints
  """

  require Logger

  defmodule SanitizationResult do
    @moduledoc """
    Result of parameter sanitization.
    """
    @type t :: %__MODULE__{
            sanitized_params: map(),
            warnings: [String.t()],
            blocked: boolean(),
            reason: String.t() | nil
          }

    defstruct [
      :sanitized_params,
      warnings: [],
      blocked: false,
      reason: nil
    ]
  end

  # Dangerous characters and patterns
  @path_traversal_patterns ["../", "..\\", "%2e%2e%2f", "%2e%2e%5c"]
  @command_injection_chars [";", "&&", "||", "|", "`", "$", "(", ")"]
  @script_injection_patterns [
    "<script",
    "</script",
    "javascript:",
    "vbscript:",
    "onload=",
    "onerror="
  ]
  @sql_injection_patterns [
    "' or ",
    "\" or ",
    "union select",
    "drop table",
    "insert into",
    "delete from"
  ]

  @doc """
  Sanitizes and validates tool parameters.

  ## Parameters

  - `parameters` - Tool parameters to sanitize
  - `tool_name` - Name of the tool (affects sanitization strategy)
  - `options` - Sanitization options

  ## Options

  - `:strict_mode` - Enable strict sanitization (default: false)
  - `:allowed_paths` - List of allowed file path prefixes
  - `:block_on_suspicion` - Block execution on suspicious patterns (default: true)

  ## Returns

  `SanitizationResult.t()` with sanitized parameters and security information
  """
  @spec sanitize_parameters(map(), String.t(), keyword()) :: SanitizationResult.t()
  def sanitize_parameters(parameters, tool_name, options \\ []) do
    strict_mode = Keyword.get(options, :strict_mode, false)
    block_on_suspicion = Keyword.get(options, :block_on_suspicion, true)

    Logger.debug("Sanitizing parameters",
      tool: tool_name,
      strict_mode: strict_mode,
      param_count: map_size(parameters)
    )

    result = %SanitizationResult{sanitized_params: %{}}

    parameters
    |> Enum.reduce(result, fn {key, value}, acc ->
      sanitize_parameter(key, value, tool_name, acc, options)
    end)
    |> finalize_sanitization_result(block_on_suspicion)
  end

  @doc """
  Validates that parameters are safe for execution.

  Performs validation without modifying parameters, useful for
  read-only security checks.
  """
  @spec validate_parameters_safe?(map(), String.t(), keyword()) :: boolean()
  def validate_parameters_safe?(parameters, tool_name, options \\ []) do
    result = sanitize_parameters(parameters, tool_name, options)
    not result.blocked
  end

  @doc """
  Sanitizes a file path parameter.

  Prevents path traversal attacks and validates path structure.
  """
  @spec sanitize_path(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def sanitize_path(path, options \\ []) when is_binary(path) do
    allowed_paths = Keyword.get(options, :allowed_paths, [])

    cond do
      # Check for path traversal
      has_path_traversal?(path) ->
        {:error, "Path traversal attempt detected"}

      # Check against allowed paths if specified
      length(allowed_paths) > 0 and not path_allowed?(path, allowed_paths) ->
        {:error, "Path not in allowed directories"}

      # Basic path validation
      not valid_path_format?(path) ->
        {:error, "Invalid path format"}

      true ->
        # Normalize the path
        sanitized = normalize_path(path)
        {:ok, sanitized}
    end
  end

  @doc """
  Sanitizes a command parameter.

  Prevents command injection while preserving legitimate command structure.
  """
  @spec sanitize_command(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def sanitize_command(command, options \\ []) when is_binary(command) do
    strict_mode = Keyword.get(options, :strict_mode, false)

    cond do
      # Check for obvious injection attempts
      has_command_injection?(command) ->
        {:error, "Command injection attempt detected"}

      # In strict mode, be more restrictive
      strict_mode and has_suspicious_command_patterns?(command) ->
        {:error, "Suspicious command patterns detected"}

      true ->
        # Basic command sanitization
        sanitized = sanitize_command_basic(command)
        {:ok, sanitized}
    end
  end

  @doc """
  Sanitizes a URL parameter.

  Validates URL format and checks against allowed protocols.
  """
  @spec sanitize_url(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def sanitize_url(url, options \\ []) when is_binary(url) do
    allowed_protocols = Keyword.get(options, :allowed_protocols, ["http", "https"])

    cond do
      not valid_url_format?(url) ->
        {:error, "Invalid URL format"}

      not protocol_allowed?(url, allowed_protocols) ->
        {:error, "Protocol not allowed"}

      has_malicious_url_patterns?(url) ->
        {:error, "Malicious URL patterns detected"}

      true ->
        {:ok, String.trim(url)}
    end
  end

  ## Private Functions

  defp sanitize_parameter(key, value, tool_name, result, options) do
    {sanitized_value, warnings} =
      case {String.downcase(to_string(key)), value} do
        # File path parameters
        {path_key, path} when path_key in ["path", "file", "filename"] and is_binary(path) ->
          case sanitize_path(path, options) do
            {:ok, sanitized} -> {sanitized, []}
            {:error, reason} -> {path, ["Path parameter '#{key}': #{reason}"]}
          end

        # Command parameters
        {cmd_key, command} when cmd_key in ["command", "cmd", "script"] and is_binary(command) ->
          case sanitize_command(command, options) do
            {:ok, sanitized} -> {sanitized, []}
            {:error, reason} -> {command, ["Command parameter '#{key}': #{reason}"]}
          end

        # URL parameters
        {url_key, url} when url_key in ["url", "endpoint", "host"] and is_binary(url) ->
          case sanitize_url(url, options) do
            {:ok, sanitized} -> {sanitized, []}
            {:error, reason} -> {url, ["URL parameter '#{key}': #{reason}"]}
          end

        # String parameters (general sanitization)
        {_, string_value} when is_binary(string_value) ->
          sanitized = sanitize_string_value(string_value, options)
          warnings = detect_string_security_issues(string_value, key)
          {sanitized, warnings}

        # Map parameters (recursive sanitization)
        {_, map_value} when is_map(map_value) ->
          nested_result = sanitize_parameters(map_value, tool_name, options)
          {nested_result.sanitized_params, nested_result.warnings}

        # List parameters
        {_, list_value} when is_list(list_value) ->
          {sanitized_list, list_warnings} = sanitize_list_parameter(list_value, options)
          {sanitized_list, list_warnings}

        # Other types pass through
        {_, other_value} ->
          {other_value, []}
      end

    %{
      result
      | sanitized_params: Map.put(result.sanitized_params, key, sanitized_value),
        warnings: result.warnings ++ warnings
    }
  end

  defp finalize_sanitization_result(result, block_on_suspicion) do
    # Determine if execution should be blocked
    should_block = block_on_suspicion and length(result.warnings) > 0

    if should_block do
      reason = "Suspicious parameters detected: " <> Enum.join(result.warnings, "; ")
      %{result | blocked: true, reason: reason}
    else
      result
    end
  end

  defp has_path_traversal?(path) do
    Enum.any?(@path_traversal_patterns, &String.contains?(path, &1))
  end

  defp path_allowed?(path, allowed_paths) do
    Enum.any?(allowed_paths, &String.starts_with?(path, &1))
  end

  defp valid_path_format?(path) do
    # Basic path format validation
    # Reasonable length limit
    # No null bytes
    byte_size(path) < 4096 and
      not String.contains?(path, "\0") and
      String.printable?(path)
  end

  defp normalize_path(path) do
    path
    |> String.trim()
    # Collapse multiple slashes
    |> String.replace(~r/\/+/, "/")
  end

  defp has_command_injection?(command) do
    Enum.any?(@command_injection_chars, &String.contains?(command, &1))
  end

  defp has_suspicious_command_patterns?(command) do
    # Additional patterns that might be suspicious in strict mode
    suspicious_patterns = ["rm ", "del ", "format ", "shutdown", "reboot"]
    command_lower = String.downcase(command)
    Enum.any?(suspicious_patterns, &String.contains?(command_lower, &1))
  end

  defp sanitize_command_basic(command) do
    command
    |> String.trim()
    # Limit command length
    |> String.slice(0, 1024)
  end

  defp valid_url_format?(url) do
    # Basic URL format validation using URI
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when is_binary(scheme) and is_binary(host) ->
        true

      _ ->
        false
    end
  end

  defp protocol_allowed?(url, allowed_protocols) do
    case URI.parse(url) do
      %URI{scheme: scheme} when is_binary(scheme) ->
        String.downcase(scheme) in allowed_protocols

      _ ->
        false
    end
  end

  defp has_malicious_url_patterns?(url) do
    # Check for various malicious URL patterns
    malicious_patterns = ["javascript:", "data:", "vbscript:", "file://"]
    url_lower = String.downcase(url)
    Enum.any?(malicious_patterns, &String.starts_with?(url_lower, &1))
  end

  defp sanitize_string_value(value, options) do
    strict_mode = Keyword.get(options, :strict_mode, false)

    sanitized =
      value
      |> String.trim()
      |> remove_null_bytes()

    if strict_mode do
      sanitized |> remove_control_chars()
    else
      sanitized
    end
  end

  defp detect_string_security_issues(value, key) do
    warnings = []

    warnings =
      if has_script_injection_patterns?(value) do
        ["Parameter '#{key}' contains potential script injection patterns" | warnings]
      else
        warnings
      end

    warnings =
      if has_sql_injection_patterns?(value) do
        ["Parameter '#{key}' contains potential SQL injection patterns" | warnings]
      else
        warnings
      end

    warnings =
      if String.contains?(value, "\0") do
        ["Parameter '#{key}' contains null bytes" | warnings]
      else
        warnings
      end

    warnings
  end

  defp has_script_injection_patterns?(value) do
    value_lower = String.downcase(value)
    Enum.any?(@script_injection_patterns, &String.contains?(value_lower, &1))
  end

  defp has_sql_injection_patterns?(value) do
    value_lower = String.downcase(value)
    Enum.any?(@sql_injection_patterns, &String.contains?(value_lower, &1))
  end

  defp remove_null_bytes(string) do
    String.replace(string, "\0", "")
  end

  defp remove_control_chars(string) do
    # Remove control characters except newline and tab
    String.replace(string, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
  end

  defp sanitize_list_parameter(list, options) do
    {sanitized_items, all_warnings} =
      list
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        case item do
          string when is_binary(string) ->
            # Check if string looks like a path (for list parameters)
            warnings = []

            warnings =
              if has_path_traversal?(string) do
                ["List item[#{index}] contains path traversal patterns" | warnings]
              else
                warnings
              end

            warnings = warnings ++ detect_string_security_issues(string, "item[#{index}]")
            sanitized = sanitize_string_value(string, options)
            {sanitized, warnings}

          other ->
            {other, []}
        end
      end)
      |> Enum.unzip()

    warnings = List.flatten(all_warnings)
    {sanitized_items, warnings}
  end
end
