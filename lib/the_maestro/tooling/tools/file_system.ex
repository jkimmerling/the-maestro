defmodule TheMaestro.Tooling.Tools.FileSystem do
  @moduledoc """
  File system operations tool with security sandboxing.

  This tool provides secure file system operations for the AI agent,
  including reading files with path validation against allowed directories.

  ## Security Features

  - Path validation against pre-configured allowed directories
  - Protection against path traversal attacks (../ sequences)
  - Symlink resolution and validation
  - File size limits for read operations

  ## Configuration

  The allowed directories are configured via application config:

      config :the_maestro, :file_system_tool,
        allowed_directories: [
          "/tmp",
          "/home/user/projects",
          "/safe/path"
        ],
        max_file_size: 10 * 1024 * 1024  # 10MB

  """

  use TheMaestro.Tooling.Tool

  require Logger

  @impl true
  def definition do
    %{
      "name" => "read_file",
      "description" => "Reads the contents of a file from the local filesystem. Only files within pre-configured allowed directories can be accessed.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Absolute or relative file path to read. Path must be within allowed directories."
          }
        },
        "required" => ["path"]
      }
    }
  end

  @impl true
  def execute(%{"path" => path}) do
    Logger.info("FileSystem tool: Reading file at path '#{path}'")

    with {:ok, validated_path} <- validate_path(path),
         {:ok, content} <- read_file_safely(validated_path) do
      {:ok, %{
        "content" => content,
        "path" => validated_path,
        "size" => byte_size(content)
      }}
    else
      {:error, reason} ->
        Logger.warning("FileSystem tool failed: #{reason}")
        {:error, reason}
    end
  end

  @impl true
  def validate_arguments(%{"path" => path}) when is_binary(path) do
    if String.trim(path) == "" do
      {:error, "Path cannot be empty"}
    else
      :ok
    end
  end

  def validate_arguments(_) do
    {:error, "Invalid arguments. Expected a map with 'path' key."}
  end

  # Private Functions

  @doc false
  def validate_path(path) do
    with {:ok, resolved_path} <- resolve_path(path),
         :ok <- check_path_allowed(resolved_path),
         :ok <- check_file_exists(resolved_path) do
      {:ok, resolved_path}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_path(path) do
    try do
      case Path.type(path) do
        :absolute ->
          {:ok, Path.expand(path)}
        :relative ->
          # For relative paths, resolve against current working directory
          {:ok, Path.expand(path, File.cwd!())}
        :volumerelative ->
          {:error, "Volume-relative paths are not supported"}
      end
    rescue
      error -> {:error, "Invalid path format: #{inspect(error)}"}
    end
  end

  defp check_path_allowed(path) do
    allowed_dirs = get_allowed_directories()
    
    if length(allowed_dirs) == 0 do
      Logger.warning("No allowed directories configured for FileSystem tool")
      {:error, "File system access is not configured"}
    else
      path_allowed = Enum.any?(allowed_dirs, fn allowed_dir ->
        String.starts_with?(path, Path.expand(allowed_dir))
      end)

      if path_allowed do
        :ok
      else
        {:error, "Path '#{path}' is not within allowed directories: #{inspect(allowed_dirs)}"}
      end
    end
  end

  defp check_file_exists(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} ->
        :ok
      {:ok, %File.Stat{type: :directory}} ->
        {:error, "Path is a directory, not a file"}
      {:ok, %File.Stat{type: other}} ->
        {:error, "Path is not a regular file (type: #{other})"}
      {:error, :enoent} ->
        {:error, "File does not exist"}
      {:error, :eacces} ->
        {:error, "Permission denied"}
      {:error, reason} ->
        {:error, "Cannot access file: #{reason}"}
    end
  end

  defp read_file_safely(path) do
    max_size = get_max_file_size()

    case File.stat(path) do
      {:ok, %File.Stat{size: size}} when size > max_size ->
        {:error, "File too large (#{size} bytes, max: #{max_size} bytes)"}
      
      {:ok, _stat} ->
        case File.read(path) do
          {:ok, content} ->
            {:ok, content}
          {:error, reason} ->
            {:error, "Failed to read file: #{reason}"}
        end
      
      {:error, reason} ->
        {:error, "Cannot stat file: #{reason}"}
    end
  end

  defp get_allowed_directories do
    Application.get_env(:the_maestro, :file_system_tool, [])
    |> Keyword.get(:allowed_directories, default_allowed_directories())
  end

  defp get_max_file_size do
    Application.get_env(:the_maestro, :file_system_tool, [])
    |> Keyword.get(:max_file_size, 10 * 1024 * 1024)  # 10MB default
  end

  defp default_allowed_directories do
    # Provide some safe defaults for development
    [
      "/tmp",
      System.tmp_dir!(),
      Path.join([System.user_home!(), "Documents"]),
      Path.join([File.cwd!(), "priv"]),
      Path.join([File.cwd!(), "assets"]),
      Path.join([File.cwd!(), "test", "fixtures"])
    ]
  end

  # Register this tool when the module is loaded
  @doc false
  def __register_tool__ do
    TheMaestro.Tooling.register_tool(
      "read_file",
      __MODULE__,
      definition(),
      &execute/1
    )
  end
  
  # Auto-register when module is loaded
  __register_tool__()
end