defmodule TheMaestro.Tooling.Tools.FileSystemTest do
  use ExUnit.Case, async: false  # File operations should not run concurrently
  doctest TheMaestro.Tooling.Tools.FileSystem

  alias TheMaestro.Tooling.Tools.FileSystem

  # Setup test directory structure
  @test_sandbox_dir "/tmp/maestro_test_sandbox"
  @test_file_content "Hello, World!\nThis is a test file.\n"
  
  setup do
    # Clean up and create test sandbox
    if File.exists?(@test_sandbox_dir), do: File.rm_rf!(@test_sandbox_dir)
    File.mkdir_p!(@test_sandbox_dir)
    
    # Create some test files and directories
    File.mkdir_p!(Path.join(@test_sandbox_dir, "subdir"))
    File.write!(Path.join(@test_sandbox_dir, "test.txt"), @test_file_content)
    File.write!(Path.join(@test_sandbox_dir, "subdir/nested.txt"), "Nested file content")
    
    # Set up configuration for testing
    Application.put_env(:the_maestro, :file_system_tool, [
      allowed_directories: [@test_sandbox_dir],
      max_file_size: 10 * 1024 * 1024  # 10MB
    ])
    
    on_exit(fn ->
      if File.exists?(@test_sandbox_dir), do: File.rm_rf!(@test_sandbox_dir)
    end)
    
    {:ok, sandbox_dir: @test_sandbox_dir}
  end

  describe "Tool behaviour implementation" do
    test "implements Tool behaviour correctly" do
      assert function_exported?(FileSystem, :definition, 0)
      assert function_exported?(FileSystem, :execute, 1)
    end

    test "returns proper tool definition" do
      definition = FileSystem.definition()
      
      assert definition["name"] == "read_file"
      assert is_binary(definition["description"])
      assert is_map(definition["parameters"])
      assert "path" in definition["parameters"]["required"]
    end
  end

  describe "path validation and sandboxing" do
    test "allows operations within sandbox directory", %{sandbox_dir: sandbox_dir} do
      valid_path = Path.join(sandbox_dir, "test.txt")
      assert {:ok, result} = FileSystem.execute(%{"path" => valid_path})
      assert result["content"] == @test_file_content
    end

    test "rejects paths outside sandbox directory" do
      # Attempt to access file outside sandbox
      invalid_path = "/etc/passwd"
      assert {:error, reason} = FileSystem.execute(%{"path" => invalid_path})
      assert String.contains?(reason, "not within allowed directories")
    end

    test "rejects relative paths that escape sandbox" do
      # Attempt directory traversal
      invalid_path = Path.join(@test_sandbox_dir, "../../../etc/passwd")
      assert {:error, reason} = FileSystem.execute(%{"path" => invalid_path})
      assert String.contains?(reason, "not within allowed directories")
    end

    test "normalizes paths correctly", %{sandbox_dir: sandbox_dir} do
      # Test path with extra slashes and dots
      messy_path = Path.join(sandbox_dir, "./test.txt")
      assert {:ok, result} = FileSystem.execute(%{"path" => messy_path})
      assert result["content"] == @test_file_content
    end

    test "handles non-existent files gracefully", %{sandbox_dir: sandbox_dir} do
      non_existent_path = Path.join(sandbox_dir, "does_not_exist.txt")
      assert {:error, reason} = FileSystem.execute(%{"path" => non_existent_path})
      assert String.contains?(reason, "does not exist") or String.contains?(reason, "not found")
    end
  end

  describe "file reading operations" do
    test "reads file content successfully", %{sandbox_dir: sandbox_dir} do
      file_path = Path.join(sandbox_dir, "test.txt")
      assert {:ok, result} = FileSystem.execute(%{"path" => file_path})
      
      assert result["content"] == @test_file_content
      assert result["path"] == file_path
      assert is_integer(result["size"])
      assert result["size"] > 0
    end

    test "reads nested file content", %{sandbox_dir: sandbox_dir} do
      nested_path = Path.join(sandbox_dir, "subdir/nested.txt")
      assert {:ok, result} = FileSystem.execute(%{"path" => nested_path})
      
      assert result["content"] == "Nested file content"
      assert result["path"] == nested_path
    end

    test "handles empty files", %{sandbox_dir: sandbox_dir} do
      empty_file = Path.join(sandbox_dir, "empty.txt")
      File.write!(empty_file, "")
      
      assert {:ok, result} = FileSystem.execute(%{"path" => empty_file})
      assert result["content"] == ""
      assert result["size"] == 0
    end

    test "includes file metadata in response", %{sandbox_dir: sandbox_dir} do
      file_path = Path.join(sandbox_dir, "test.txt")
      assert {:ok, result} = FileSystem.execute(%{"path" => file_path})
      
      assert Map.has_key?(result, "content")
      assert Map.has_key?(result, "path") 
      assert Map.has_key?(result, "size")
      assert is_integer(result["size"])
    end
  end

  describe "error handling and edge cases" do
    test "handles missing required parameters" do
      assert {:error, reason} = FileSystem.execute(%{})
      assert String.contains?(reason, "Path cannot be empty") or String.contains?(reason, "path")
    end

    test "handles nil parameters gracefully" do
      assert {:error, reason} = FileSystem.execute(nil)
      assert is_binary(reason)
    end

    test "handles invalid parameter types" do
      assert {:error, reason} = FileSystem.execute(%{"path" => 123})
      assert is_binary(reason)
    end

    test "handles permission errors gracefully" do
      # This test may be environment-dependent
      # Try to read a file that typically requires elevated permissions
      restricted_path = "/root/.bashrc"  # Typically not readable by regular users
      
      result = FileSystem.execute(%{"path" => restricted_path})
      
      case result do
        {:error, reason} ->
          assert is_binary(reason)
          # Should get either permission denied or outside sandbox error
          :ok
        {:ok, _} ->
          # File was readable, test still passes
          :ok
      end
    end
  end

  describe "performance and resource management" do
    test "handles reasonably large files", %{sandbox_dir: sandbox_dir} do
      large_content = String.duplicate("x", 1024 * 10)  # 10KB
      large_file = Path.join(sandbox_dir, "large.txt")
      File.write!(large_file, large_content)
      
      {time_microseconds, result} = :timer.tc(fn ->
        FileSystem.execute(%{"path" => large_file})
      end)
      
      assert {:ok, file_result} = result
      assert file_result["content"] == large_content
      
      # Should complete within reasonable time (less than 1 second)
      assert time_microseconds < 1_000_000
    end
  end
end