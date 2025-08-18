defmodule TheMaestro.MCP.Config.EnvResolver do
  @moduledoc """
  Environment variable resolution for MCP configuration.

  Supports multiple environment variable syntax forms:
  - `$VAR` - Simple substitution
  - `${VAR}` - Braced substitution
  - `${VAR:-default}` - With default value
  - `${VAR}:/custom` - Path expansion

  Provides comprehensive error handling and logging for missing variables.
  """

  require Logger

  @doc """
  Resolve environment variables in a single string value.

  ## Examples

      iex> System.put_env("TEST_VAR", "value")
      iex> EnvResolver.resolve("$TEST_VAR")
      "value"
      
      iex> EnvResolver.resolve("${MISSING:-default}")
      "default"
      
      iex> System.put_env("PATH", "/usr/bin")
      iex> EnvResolver.resolve("${PATH}:/custom")
      "/usr/bin:/custom"
  """
  @spec resolve(String.t()) :: String.t()
  def resolve(value) when is_binary(value) do
    value
    |> resolve_braced_variables()
    |> resolve_simple_variables()
  end

  def resolve(value), do: value

  @doc """
  Recursively resolve environment variables in configuration structure.

  Handles nested maps and lists, resolving environment variables in all
  string values while preserving the structure.
  """
  @spec resolve_config(map() | list() | any()) :: map() | list() | any()
  def resolve_config(config) when is_map(config) do
    Enum.into(config, %{}, fn {key, value} ->
      {resolve_key(key), resolve_config(value)}
    end)
  end

  def resolve_config(config) when is_list(config) do
    Enum.map(config, &resolve_config/1)
  end

  def resolve_config(config) when is_binary(config) do
    resolve(config)
  end

  def resolve_config(config), do: config

  ## Private Functions

  defp resolve_key(key) when is_binary(key), do: resolve(key)
  defp resolve_key(key), do: key

  defp resolve_braced_variables(value) do
    # Pattern: ${VAR} or ${VAR:-default}
    Regex.replace(~r/\$\{([A-Za-z_][A-Za-z0-9_]*)(:-([^}]*))?\}/, value, fn
      _full_match, var_name, "", "" ->
        # Simple braced variable: ${VAR}
        get_env_variable(var_name, value)

      _full_match, var_name, ":-" <> _default_part, default_value ->
        # Variable with default: ${VAR:-default}
        get_env_variable_with_default(var_name, default_value, value)
    end)
  end

  defp resolve_simple_variables(value) do
    # Pattern: $VAR (not followed by { and not preceded by })
    Regex.replace(~r/(?<!\})\$([A-Za-z_][A-Za-z0-9_]*)(?!\{)/, value, fn
      _full_match, var_name ->
        get_env_variable(var_name, value)
    end)
  end

  defp get_env_variable(var_name, original_value) do
    case System.get_env(var_name) do
      nil ->
        Logger.warning(
          "Environment variable #{var_name} not found, leaving unchanged: #{original_value}"
        )

        # Leave unresolved for debugging
        "$#{var_name}"

      value ->
        Logger.debug("Resolved environment variable #{var_name}")
        value
    end
  end

  defp get_env_variable_with_default(var_name, default_value, _original_value) do
    case System.get_env(var_name) do
      nil ->
        Logger.debug(
          "Environment variable #{var_name} not found, using default: #{default_value}"
        )

        resolve_nested_variables(default_value)

      value ->
        Logger.debug("Resolved environment variable #{var_name}")
        value
    end
  end

  defp resolve_nested_variables(default_value) do
    # Recursively resolve environment variables in default values
    # This handles cases like ${VAR:-${OTHER_VAR}/default}
    if String.contains?(default_value, "$") do
      resolve(default_value)
    else
      default_value
    end
  end

  @doc """
  Validate that all required environment variables are available.

  Scans configuration for environment variable references and checks
  that they exist in the environment.
  """
  @spec validate_env_vars(map()) :: {:ok, [String.t()]} | {:error, [String.t()]}
  def validate_env_vars(config) do
    required_vars = extract_env_vars(config)
    missing_vars = Enum.filter(required_vars, &is_nil(System.get_env(&1)))

    case missing_vars do
      [] -> {:ok, required_vars}
      missing -> {:error, missing}
    end
  end

  @doc """
  Extract all environment variable references from configuration.

  Returns a list of unique environment variable names found in the configuration.
  """
  @spec extract_env_vars(any()) :: [String.t()]
  def extract_env_vars(config) do
    config
    |> extract_vars_recursive([])
    |> Enum.uniq()
  end

  defp extract_vars_recursive(config, acc) when is_map(config) do
    Enum.reduce(config, acc, fn {_key, value}, acc ->
      extract_vars_recursive(value, acc)
    end)
  end

  defp extract_vars_recursive(config, acc) when is_list(config) do
    Enum.reduce(config, acc, fn item, acc ->
      extract_vars_recursive(item, acc)
    end)
  end

  defp extract_vars_recursive(config, acc) when is_binary(config) do
    extract_vars_from_string(config) ++ acc
  end

  defp extract_vars_recursive(_config, acc), do: acc

  defp extract_vars_from_string(value) do
    # Extract both ${VAR} and $VAR patterns
    braced_vars =
      Regex.scan(~r/\$\{([A-Za-z_][A-Za-z0-9_]*)(:-[^}]*)?\}/, value)
      |> Enum.map(fn [_, var_name | _] -> var_name end)

    simple_vars =
      Regex.scan(~r/(?<!\})\$([A-Za-z_][A-Za-z0-9_]*)(?!\{)/, value)
      |> Enum.map(fn [_, var_name] -> var_name end)

    braced_vars ++ simple_vars
  end

  @doc """
  Get environment variable with type conversion.

  Supports automatic type conversion for common configuration values.
  """
  @spec get_env_typed(String.t(), atom(), any()) :: any()
  def get_env_typed(var_name, type, default \\ nil)

  def get_env_typed(var_name, :string, default) do
    System.get_env(var_name, default)
  end

  def get_env_typed(var_name, :integer, default) do
    case System.get_env(var_name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {int_val, ""} ->
            int_val

          _ ->
            Logger.warning("Invalid integer value for #{var_name}: #{value}, using default")
            default
        end
    end
  end

  def get_env_typed(var_name, :boolean, default) do
    case System.get_env(var_name) do
      nil -> default
      value -> value in ["true", "1", "yes", "on"]
    end
  end

  def get_env_typed(var_name, :float, default) do
    case System.get_env(var_name) do
      nil ->
        default

      value ->
        case Float.parse(value) do
          {float_val, ""} ->
            float_val

          _ ->
            Logger.warning("Invalid float value for #{var_name}: #{value}, using default")
            default
        end
    end
  end

  def get_env_typed(var_name, :list, default) do
    case System.get_env(var_name) do
      nil ->
        default

      value ->
        value
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  @doc """
  Set up environment variable watching for configuration hot-reload.

  Monitors environment variables referenced in configuration and triggers
  reload when they change.
  """
  @spec setup_env_watching(map()) :: :ok
  def setup_env_watching(config) do
    env_vars = extract_env_vars(config)

    # Store current values for comparison
    current_values =
      Enum.into(env_vars, %{}, fn var ->
        {var, System.get_env(var)}
      end)

    :persistent_term.put({__MODULE__, :watched_vars}, current_values)

    # Start periodic check for environment variable changes
    schedule_env_check()

    Logger.debug("Set up environment variable watching for #{length(env_vars)} variables")
    :ok
  end

  @doc """
  Check for environment variable changes and trigger reload if needed.
  """
  @spec check_env_changes() :: :ok | :changed
  def check_env_changes do
    case :persistent_term.get({__MODULE__, :watched_vars}, %{}) do
      current_values when map_size(current_values) > 0 ->
        changes = detect_env_changes(current_values)

        case changes do
          [] ->
            :ok

          _changes ->
            Logger.info("Environment variable changes detected, triggering configuration reload")

            # Update stored values
            new_values =
              Enum.into(current_values, %{}, fn {var, _old_val} ->
                {var, System.get_env(var)}
              end)

            :persistent_term.put({__MODULE__, :watched_vars}, new_values)

            # Trigger configuration reload
            TheMaestro.MCP.Config.reload_configuration()

            :changed
        end

      _ ->
        :ok
    end
  end

  defp detect_env_changes(current_values) do
    Enum.filter(current_values, fn {var, old_value} ->
      new_value = System.get_env(var)
      new_value != old_value
    end)
  end

  defp schedule_env_check do
    # Check every 30 seconds for environment variable changes
    Process.send_after(self(), :check_env_changes, 30_000)
  end

  @doc """
  Expand path-like environment variables.

  Handles special cases like PATH expansion where new values are appended
  to existing paths with proper separators.
  """
  @spec expand_path_env(String.t()) :: String.t()
  def expand_path_env(value) when is_binary(value) do
    # Handle PATH-like expansion: ${PATH}:/new/path
    Regex.replace(~r/\$\{([A-Za-z_][A-Za-z0-9_]*)\}:([^:$]+)/, value, fn
      _full_match, var_name, additional_path ->
        case System.get_env(var_name) do
          nil ->
            Logger.warning("Environment variable #{var_name} not found for path expansion")
            additional_path

          existing_path ->
            "#{existing_path}:#{additional_path}"
        end
    end)
  end

  def expand_path_env(value), do: value

  @doc """
  Get environment variable with validation.

  Validates that the environment variable value matches expected patterns
  or constraints.
  """
  @spec get_env_validated(String.t(), (String.t() -> boolean()), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def get_env_validated(var_name, validator_fn, error_message) do
    case System.get_env(var_name) do
      nil ->
        {:error, "Environment variable #{var_name} is not set"}

      value ->
        if validator_fn.(value) do
          {:ok, value}
        else
          {:error, "Environment variable #{var_name}: #{error_message}"}
        end
    end
  end

  @doc """
  Safely resolve environment variables with error collection.

  Returns both the resolved configuration and any errors encountered
  during resolution.
  """
  @spec safe_resolve_config(map()) :: {map(), [String.t()]}
  def safe_resolve_config(config) do
    errors = []
    {resolved_config, final_errors} = safe_resolve_recursive(config, errors)
    {resolved_config, Enum.reverse(final_errors)}
  end

  defp safe_resolve_recursive(config, errors) when is_map(config) do
    {resolved_map, final_errors} =
      Enum.reduce(config, {%{}, errors}, fn {key, value}, {acc_map, acc_errors} ->
        {resolved_key, key_errors} = safe_resolve_recursive(key, acc_errors)
        {resolved_value, value_errors} = safe_resolve_recursive(value, key_errors)
        {Map.put(acc_map, resolved_key, resolved_value), value_errors}
      end)

    {resolved_map, final_errors}
  end

  defp safe_resolve_recursive(config, errors) when is_list(config) do
    Enum.reduce(config, {[], errors}, fn item, {acc_list, acc_errors} ->
      {resolved_item, item_errors} = safe_resolve_recursive(item, acc_errors)
      {[resolved_item | acc_list], item_errors}
    end)
    |> then(fn {resolved_list, final_errors} ->
      {Enum.reverse(resolved_list), final_errors}
    end)
  end

  defp safe_resolve_recursive(config, errors) when is_binary(config) do
    try do
      resolved = resolve(config)
      {resolved, errors}
    rescue
      error ->
        error_msg = "Failed to resolve environment variables in '#{config}': #{inspect(error)}"
        {config, [error_msg | errors]}
    end
  end

  defp safe_resolve_recursive(config, errors), do: {config, errors}
end
