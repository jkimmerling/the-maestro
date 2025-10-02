defmodule MaestroTui.Config do
  @moduledoc """
  Configuration and settings management for Maestro TUI.

  Reads from ~/.the_maestro/config.json and ~/.the_maestro/settings.json
  to provide API configuration and user preferences.
  """

  @config_dir Path.expand("~/.the_maestro")
  @config_path Path.join(@config_dir, "config.json")
  @settings_path Path.join(@config_dir, "settings.json")

  @type config :: %{api_host: String.t(), api_key: String.t()}
  @type settings :: %{
          last_provider: String.t() | nil,
          last_auth_id: String.t() | nil,
          last_model: String.t() | nil,
          session_defaults: map() | nil
        }

  @doc """
  Load API configuration from ~/.the_maestro/config.json
  Falls back to environment variables if file doesn't exist.

  Returns:
    - `{:ok, %{api_host: string, api_key: string}}`
    - `{:error, reason}` if config is invalid
  """
  @spec load_config() :: {:ok, config()} | {:error, term()}
  def load_config do
    case File.read(@config_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"api_host" => host, "api_key" => key}} when is_binary(host) and is_binary(key) ->
            {:ok, %{api_host: String.trim_trailing(host, "/"), api_key: key}}

          {:ok, data} ->
            {:error, {:missing_fields, data}}

          {:error, reason} ->
            {:error, {:json_decode, reason}}
        end

      {:error, :enoent} ->
        # Fall back to environment variables
        case {System.get_env("TUI_API_BASE_URL"), System.get_env("TUI_API_TOKEN")} do
          {host, key} when is_binary(host) and is_binary(key) ->
            {:ok, %{api_host: String.trim_trailing(host, "/"), api_key: key}}

          _ ->
            {:error, :no_config}
        end

      {:error, reason} ->
        {:error, {:file_read, reason}}
    end
  end

  @doc """
  Load user settings from ~/.the_maestro/settings.json
  Returns empty settings if file doesn't exist.
  """
  @spec load_settings() :: settings()
  def load_settings do
    case File.read(@settings_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            %{
              last_provider: Map.get(data, "last_provider"),
              last_auth_id: Map.get(data, "last_auth_id"),
              last_model: Map.get(data, "last_model"),
              session_defaults: Map.get(data, "session_defaults")
            }

          {:error, _} ->
            empty_settings()
        end

      {:error, _} ->
        empty_settings()
    end
  end

  @doc """
  Save user settings to ~/.the_maestro/settings.json
  Creates directory if it doesn't exist.
  """
  @spec save_settings(settings()) :: :ok | {:error, term()}
  def save_settings(settings) do
    data = %{
      "last_provider" => Map.get(settings, :last_provider),
      "last_auth_id" => Map.get(settings, :last_auth_id),
      "last_model" => Map.get(settings, :last_model),
      "session_defaults" => Map.get(settings, :session_defaults) || %{}
    }

    with :ok <- File.mkdir_p(@config_dir),
         {:ok, json} <- Jason.encode(data, pretty: true),
         :ok <- File.write(@settings_path, json) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if configuration exists in either file or environment variables.
  """
  @spec has_config?() :: boolean()
  def has_config? do
    case load_config() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Check if settings file exists and has required fields.
  """
  @spec has_complete_settings?() :: boolean()
  def has_complete_settings? do
    settings = load_settings()

    valid_string?(settings.last_provider) and
      valid_string?(settings.last_auth_id) and
      valid_string?(settings.last_model)
  end

  defp valid_string?(s) when is_binary(s), do: String.trim(s) != ""
  defp valid_string?(_), do: false

  defp empty_settings do
    %{
      last_provider: nil,
      last_auth_id: nil,
      last_model: nil,
      session_defaults: nil
    }
  end
end
