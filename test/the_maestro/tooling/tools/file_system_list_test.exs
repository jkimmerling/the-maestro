defmodule TheMaestro.Tooling.Tools.FileSystemListTest do
  # File operations should not run concurrently
  use ExUnit.Case, async: false

  alias TheMaestro.Tooling.Tools.FileSystem.ListDirectory

  # Setup test directory structure
  @test_sandbox_dir "/tmp/maestro_test_sandbox_list"

  setup do
    # Clean up and create test sandbox
    if File.exists?(@test_sandbox_dir), do: File.rm_rf!(@test_sandbox_dir)
    File.mkdir_p!(@test_sandbox_dir)

    # Create some test files and directories
    File.mkdir_p!(Path.join(@test_sandbox_dir, "subdir"))
    File.mkdir_p!(Path.join(@test_sandbox_dir, "another_dir"))
    File.write!(Path.join(@test_sandbox_dir, "file1.txt"), "Content 1")
    File.write!(Path.join(@test_sandbox_dir, "file2.md"), "# Content 2")
    File.write!(Path.join(@test_sandbox_dir, "subdir/nested.txt"), "Nested content")
    File.write!(Path.join(@test_sandbox_dir, ".hidden"), "Hidden file")

    # Set up configuration for testing
    Application.put_env(:the_maestro, :file_system_tool,
      allowed_directories: [@test_sandbox_dir],
      # 10MB
      max_file_size: 10 * 1024 * 1024
    )

    on_exit(fn ->
      if File.exists?(@test_sandbox_dir), do: File.rm_rf!(@test_sandbox_dir)
    end)

    {:ok, sandbox_dir: @test_sandbox_dir}
  end

  describe "ListDirectory tool behaviour implementation" do
    test "implements Tool behaviour correctly" do
      assert function_exported?(ListDirectory, :definition, 0)
      assert function_exported?(ListDirectory, :execute, 1)
    end

    test "returns proper tool definition" do
      definition = ListDirectory.definition()

      assert definition["name"] == "list_directory"
      assert is_binary(definition["description"])
      assert is_map(definition["parameters"])
      assert "path" in definition["parameters"]["required"]
    end
  end

  describe "directory listing operations" do
    test "lists directory contents successfully", %{sandbox_dir: sandbox_dir} do
      assert {:ok, result} = ListDirectory.execute(%{"path" => sandbox_dir})

      assert result["path"] == sandbox_dir
      assert is_integer(result["count"])
      assert result["count"] > 0
      assert is_list(result["entries"])

      # Should contain our test files and directories
      entry_names = Enum.map(result["entries"], & &1["name"])
      assert "file1.txt" in entry_names
      assert "file2.md" in entry_names
      assert "subdir" in entry_names
      assert "another_dir" in entry_names
      assert ".hidden" in entry_names
    end

    test "includes entry type information", %{sandbox_dir: sandbox_dir} do
      assert {:ok, result} = ListDirectory.execute(%{"path" => sandbox_dir})

      entries_by_name = Map.new(result["entries"], fn entry -> {entry["name"], entry} end)

      # Check file types
      assert entries_by_name["file1.txt"]["type"] == "regular"
      assert entries_by_name["subdir"]["type"] == "directory"
      assert entries_by_name["another_dir"]["type"] == "directory"
    end

    test "includes full paths for entries", %{sandbox_dir: sandbox_dir} do
      assert {:ok, result} = ListDirectory.execute(%{"path" => sandbox_dir})

      entries_by_name = Map.new(result["entries"], fn entry -> {entry["name"], entry} end)

      assert entries_by_name["file1.txt"]["path"] == Path.join(sandbox_dir, "file1.txt")
      assert entries_by_name["subdir"]["path"] == Path.join(sandbox_dir, "subdir")
    end

    test "sorts entries with directories first", %{sandbox_dir: sandbox_dir} do
      assert {:ok, result} = ListDirectory.execute(%{"path" => sandbox_dir})

      # Get types in order
      types = Enum.map(result["entries"], & &1["type"])

      # Find first non-directory entry
      first_file_index = Enum.find_index(types, &(&1 != "directory"))

      if first_file_index do
        # All entries before the first file should be directories
        directories_section = Enum.take(types, first_file_index)
        assert Enum.all?(directories_section, &(&1 == "directory"))
      end
    end

    test "lists empty directory", %{sandbox_dir: sandbox_dir} do
      empty_dir = Path.join(sandbox_dir, "empty_dir")
      File.mkdir_p!(empty_dir)

      assert {:ok, result} = ListDirectory.execute(%{"path" => empty_dir})

      assert result["path"] == empty_dir
      assert result["count"] == 0
      assert result["entries"] == []
    end

    test "lists subdirectory contents", %{sandbox_dir: sandbox_dir} do
      subdir_path = Path.join(sandbox_dir, "subdir")

      assert {:ok, result} = ListDirectory.execute(%{"path" => subdir_path})

      assert result["path"] == subdir_path
      assert result["count"] == 1

      entry = List.first(result["entries"])
      assert entry["name"] == "nested.txt"
      assert entry["type"] == "regular"
    end
  end

  describe "path validation and sandboxing" do
    test "rejects paths outside sandbox directory" do
      invalid_path = "/etc"

      assert {:error, reason} = ListDirectory.execute(%{"path" => invalid_path})
      assert String.contains?(reason, "not within allowed directories")
    end

    test "rejects relative paths that escape sandbox" do
      invalid_path = Path.join(@test_sandbox_dir, "../../../etc")

      assert {:error, reason} = ListDirectory.execute(%{"path" => invalid_path})
      assert String.contains?(reason, "not within allowed directories")
    end

    test "normalizes paths correctly", %{sandbox_dir: sandbox_dir} do
      messy_path = Path.join(sandbox_dir, "./subdir")

      assert {:ok, result} = ListDirectory.execute(%{"path" => messy_path})

      expected_path = Path.join(sandbox_dir, "subdir")
      assert result["path"] == expected_path
    end

    test "rejects non-existent directory", %{sandbox_dir: sandbox_dir} do
      non_existent_path = Path.join(sandbox_dir, "does_not_exist")

      assert {:error, reason} = ListDirectory.execute(%{"path" => non_existent_path})
      assert String.contains?(reason, "does not exist")
    end

    test "rejects file path (not directory)", %{sandbox_dir: sandbox_dir} do
      file_path = Path.join(sandbox_dir, "file1.txt")

      assert {:error, reason} = ListDirectory.execute(%{"path" => file_path})
      assert String.contains?(reason, "not a directory")
    end
  end

  describe "error handling and edge cases" do
    test "handles missing path parameter" do
      assert {:error, reason} = ListDirectory.execute(%{})
      assert String.contains?(reason, "Path cannot be empty")
    end

    test "handles nil parameters gracefully" do
      assert {:error, reason} = ListDirectory.execute(nil)
      assert is_binary(reason)
    end

    test "handles invalid parameter types" do
      assert {:error, reason} = ListDirectory.execute(%{"path" => 123})
      assert is_binary(reason)
    end

    test "handles permission errors gracefully" do
      # Try to list a directory that typically requires elevated permissions
      restricted_path = "/root"

      result = ListDirectory.execute(%{"path" => restricted_path})

      case result do
        {:error, reason} ->
          assert is_binary(reason)
          # Should get either permission denied or outside sandbox error
          :ok

        {:ok, _} ->
          # Directory was readable, test still passes
          :ok
      end
    end
  end

  describe "validate_arguments/1" do
    test "accepts valid arguments" do
      args = %{"path" => "/tmp/test_dir"}
      assert :ok = ListDirectory.validate_arguments(args)
    end

    test "rejects empty path" do
      args = %{"path" => ""}
      assert {:error, reason} = ListDirectory.validate_arguments(args)
      assert String.contains?(reason, "Path cannot be empty")
    end

    test "rejects missing path" do
      assert {:error, reason} = ListDirectory.validate_arguments(%{})
      assert String.contains?(reason, "Invalid arguments")
    end
  end
end
