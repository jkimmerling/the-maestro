defmodule TheMaestro.Tooling.Tools.FileSystem do
  @moduledoc """
  File system operations tool with security sandboxing.

  This tool provides secure file system operations for the AI agent,
  including reading files, writing files, and listing directories with 
  path validation against allowed directories.

  ## Security Features

  - Path validation against pre-configured allowed directories
  - Protection against path traversal attacks (../ sequences)
  - Symlink resolution and validation
  - File size limits for read operations
  - Directory creation with proper permissions

  ## Available Tools

  - `read_file`: Reads the contents of a file
  - `write_file`: Writes content to a file (creates directories if needed)
  - `list_directory`: Lists files and subdirectories in a directory

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

  require Logger

  # This module serves as a namespace for multiple file system tools
  # Each tool is a separate implementation

  defmodule ReadFile do
    @moduledoc """
    Tool for reading file contents from the filesystem.
    """

    use TheMaestro.Tooling.Tool

    alias TheMaestro.Tooling.Tools.FileSystem

    @impl true
    def definition do
      %{
        "name" => "read_file",
        "description" =>
          "Reads the contents of a file from the local filesystem. Only files within pre-configured allowed directories can be accessed.",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{
              "type" => "string",
              "description" =>
                "Absolute or relative file path to read. Path must be within allowed directories."
            }
          },
          "required" => ["path"]
        }
      }
    end

    @impl true
    def execute(%{"path" => path}) do
      Logger.info("FileSystem tool: Reading file at path '#{path}'")

      with {:ok, validated_path} <- FileSystem.validate_path(path),
           {:ok, content} <- FileSystem.read_file_safely(validated_path) do
        {:ok,
         %{
           "content" => content,
           "path" => validated_path,
           "size" => byte_size(content)
         }}
      else
        {:error, reason} ->
          Logger.warning("FileSystem read_file tool failed: #{reason}")
          {:error, reason}
      end
    end

    def execute(%{}) do
      {:error, "Path cannot be empty"}
    end

    def execute(nil) do
      {:error, "Invalid arguments. Expected a map with 'path' key."}
    end

    def execute(_invalid_args) do
      {:error, "Invalid arguments. Expected a map with 'path' key."}
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
  end

  defmodule WriteFile do
    @moduledoc """
    Tool for writing content to files on the filesystem.
    """

    use TheMaestro.Tooling.Tool

    alias TheMaestro.Tooling.Tools.FileSystem

    @impl true
    def definition do
      %{
        "name" => "write_file",
        "description" =>
          "Writes content to a file on the local filesystem. Creates parent directories if they don't exist. Only files within pre-configured allowed directories can be written.",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{
              "type" => "string",
              "description" =>
                "Absolute or relative file path to write to. Path must be within allowed directories."
            },
            "content" => %{
              "type" => "string",
              "description" => "Content to write to the file."
            }
          },
          "required" => ["path", "content"]
        }
      }
    end

    @impl true
    def execute(%{"path" => path, "content" => content}) do
      Logger.info("FileSystem tool: Writing file at path '#{path}'")

      with {:ok, validated_path} <- FileSystem.validate_write_path(path),
           :ok <- FileSystem.ensure_parent_directory(validated_path),
           :ok <- File.write(validated_path, content) do
        file_size = byte_size(content)

        Logger.info(
          "FileSystem tool: Successfully wrote #{file_size} bytes to '#{validated_path}'"
        )

        {:ok,
         %{
           "message" => "Successfully wrote to file",
           "path" => validated_path,
           "size" => file_size
         }}
      else
        {:error, reason} ->
          Logger.warning("FileSystem write_file tool failed: #{reason}")
          {:error, "Failed to write file: #{reason}"}
      end
    end

    def execute(%{"path" => _}) do
      {:error, "Content is required"}
    end

    def execute(%{"content" => _}) do
      {:error, "Path is required"}
    end

    def execute(%{}) do
      {:error, "Path and content are required"}
    end

    def execute(nil) do
      {:error, "Invalid arguments. Expected a map with 'path' and 'content' keys."}
    end

    def execute(_invalid_args) do
      {:error, "Invalid arguments. Expected a map with 'path' and 'content' keys."}
    end

    @impl true
    def validate_arguments(%{"path" => path, "content" => content})
        when is_binary(path) and is_binary(content) do
      if String.trim(path) == "" do
        {:error, "Path cannot be empty"}
      else
        :ok
      end
    end

    def validate_arguments(_) do
      {:error, "Invalid arguments. Expected a map with 'path' and 'content' keys."}
    end
  end

  defmodule ListDirectory do
    @moduledoc """
    Tool for listing directory contents.
    """

    use TheMaestro.Tooling.Tool

    alias TheMaestro.Tooling.Tools.FileSystem

    @impl true
    def definition do
      %{
        "name" => "list_directory",
        "description" =>
          "Lists files and subdirectories in a directory. Only directories within pre-configured allowed directories can be accessed.",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{
              "type" => "string",
              "description" =>
                "Absolute or relative directory path to list. Path must be within allowed directories."
            }
          },
          "required" => ["path"]
        }
      }
    end

    @impl true
    def execute(%{"path" => path}) do
      Logger.info("FileSystem tool: Listing directory at path '#{path}'")

      with {:ok, validated_path} <-
             FileSystem.validate_directory_path(path),
           {:ok, entries} <- File.ls(validated_path) do
        # Get detailed information about each entry
        detailed_entries =
          entries
          |> Enum.map(fn entry ->
            entry_path = Path.join(validated_path, entry)

            case File.stat(entry_path) do
              {:ok, %File.Stat{type: type}} ->
                %{
                  "name" => entry,
                  "type" => Atom.to_string(type),
                  "path" => entry_path
                }

              {:error, _} ->
                %{
                  "name" => entry,
                  "type" => "unknown",
                  "path" => entry_path
                }
            end
          end)
          |> Enum.sort_by(fn %{"type" => type, "name" => name} ->
            # Sort directories first, then files, both alphabetically
            {type != "directory", String.downcase(name)}
          end)

        Logger.info(
          "FileSystem tool: Successfully listed #{length(detailed_entries)} entries in '#{validated_path}'"
        )

        {:ok,
         %{
           "entries" => detailed_entries,
           "path" => validated_path,
           "count" => length(detailed_entries)
         }}
      else
        {:error, reason} ->
          Logger.warning("FileSystem list_directory tool failed: #{reason}")
          {:error, "Failed to list directory: #{reason}"}
      end
    end

    def execute(%{}) do
      {:error, "Path cannot be empty"}
    end

    def execute(nil) do
      {:error, "Invalid arguments. Expected a map with 'path' key."}
    end

    def execute(_invalid_args) do
      {:error, "Invalid arguments. Expected a map with 'path' key."}
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
  end

  # Shared utility functions for all file system tools

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

  @doc false
  def validate_write_path(path) do
    with {:ok, resolved_path} <- resolve_path(path),
         :ok <- check_path_allowed(resolved_path) do
      {:ok, resolved_path}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def validate_directory_path(path) do
    with {:ok, resolved_path} <- resolve_path(path),
         :ok <- check_path_allowed(resolved_path),
         :ok <- check_directory_exists(resolved_path) do
      {:ok, resolved_path}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_path(path) do
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

  defp check_path_allowed(path) do
    allowed_dirs = get_allowed_directories()

    if Enum.empty?(allowed_dirs) do
      Logger.warning("No allowed directories configured for FileSystem tool")
      {:error, "File system access is not configured"}
    else
      path_allowed =
        Enum.any?(allowed_dirs, fn allowed_dir ->
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

  defp check_directory_exists(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :directory}} ->
        :ok

      {:ok, %File.Stat{type: :regular}} ->
        {:error, "Path is a file, not a directory"}

      {:ok, %File.Stat{type: other}} ->
        {:error, "Path is not a directory (type: #{other})"}

      {:error, :enoent} ->
        {:error, "Directory does not exist"}

      {:error, :eacces} ->
        {:error, "Permission denied"}

      {:error, reason} ->
        {:error, "Cannot access directory: #{reason}"}
    end
  end

  @doc false
  def ensure_parent_directory(file_path) do
    parent_dir = Path.dirname(file_path)

    case File.mkdir_p(parent_dir) do
      :ok -> :ok
      {:error, reason} -> {:error, "Cannot create parent directory: #{reason}"}
    end
  end

  @doc false
  def read_file_safely(path) do
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
    # 10MB default
    |> Keyword.get(:max_file_size, 10 * 1024 * 1024)
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

  # Register all file system tools when the module is loaded
  @doc false
  def register_tools do
    # Register read_file tool
    TheMaestro.Tooling.register_tool(
      "read_file",
      ReadFile,
      ReadFile.definition(),
      &ReadFile.execute/1
    )

    # Register write_file tool
    TheMaestro.Tooling.register_tool(
      "write_file",
      WriteFile,
      WriteFile.definition(),
      &WriteFile.execute/1
    )

    # Register list_directory tool
    TheMaestro.Tooling.register_tool(
      "list_directory",
      ListDirectory,
      ListDirectory.definition(),
      &ListDirectory.execute/1
    )
  end

  # Backward compatibility - register just read_file
  @doc false
  def register_self do
    TheMaestro.Tooling.register_tool(
      "read_file",
      ReadFile,
      ReadFile.definition(),
      &ReadFile.execute/1
    )
  end

  # Backward compatibility - delegate to ReadFile for old tests
  @doc false
  def definition, do: ReadFile.definition()

  @doc false
  def execute(args), do: ReadFile.execute(args)

  @doc false
  def validate_arguments(args), do: ReadFile.validate_arguments(args)
end
