defmodule TheMaestro.Tooling.Tools.FileSystemWriteTest do
  # File operations should not run concurrently
  use ExUnit.Case, async: false

  alias TheMaestro.Tooling.Tools.FileSystem.WriteFile

  # Setup test directory structure
  @test_sandbox_dir "/tmp/maestro_test_sandbox_write"

  setup do
    # Clean up and create test sandbox
    if File.exists?(@test_sandbox_dir), do: File.rm_rf!(@test_sandbox_dir)
    File.mkdir_p!(@test_sandbox_dir)

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

  describe "WriteFile tool behaviour implementation" do
    test "implements Tool behaviour correctly" do
      assert function_exported?(WriteFile, :definition, 0)
      assert function_exported?(WriteFile, :execute, 1)
    end

    test "returns proper tool definition" do
      definition = WriteFile.definition()

      assert definition["name"] == "write_file"
      assert is_binary(definition["description"])
      assert is_map(definition["parameters"])
      assert "path" in definition["parameters"]["required"]
      assert "content" in definition["parameters"]["required"]
    end
  end

  describe "file writing operations" do
    test "writes file content successfully", %{sandbox_dir: sandbox_dir} do
      file_path = Path.join(sandbox_dir, "new_file.txt")
      content = "This is new content!"

      assert {:ok, result} = WriteFile.execute(%{"path" => file_path, "content" => content})

      assert result["message"] == "Successfully wrote to file"
      assert result["path"] == file_path
      assert result["size"] == byte_size(content)

      # Verify file was actually written
      assert File.read!(file_path) == content
    end

    test "overwrites existing file", %{sandbox_dir: sandbox_dir} do
      file_path = Path.join(sandbox_dir, "existing.txt")
      original_content = "Original content"
      new_content = "New content!"

      # Create initial file
      File.write!(file_path, original_content)

      # Overwrite it
      assert {:ok, result} = WriteFile.execute(%{"path" => file_path, "content" => new_content})

      assert result["size"] == byte_size(new_content)
      assert File.read!(file_path) == new_content
    end

    test "creates parent directories if needed", %{sandbox_dir: sandbox_dir} do
      nested_path = Path.join([sandbox_dir, "deep", "nested", "dirs", "file.txt"])
      content = "Content in deep directory"

      assert {:ok, result} = WriteFile.execute(%{"path" => nested_path, "content" => content})

      assert result["path"] == nested_path
      assert File.read!(nested_path) == content
      assert File.dir?(Path.dirname(nested_path))
    end

    test "handles empty content", %{sandbox_dir: sandbox_dir} do
      file_path = Path.join(sandbox_dir, "empty.txt")

      assert {:ok, result} = WriteFile.execute(%{"path" => file_path, "content" => ""})

      assert result["size"] == 0
      assert File.read!(file_path) == ""
    end

    test "handles unicode content", %{sandbox_dir: sandbox_dir} do
      file_path = Path.join(sandbox_dir, "unicode.txt")
      content = "Hello 世界! 🌍 Ελληνικά"

      assert {:ok, result} = WriteFile.execute(%{"path" => file_path, "content" => content})

      assert result["size"] == byte_size(content)
      assert File.read!(file_path) == content
    end
  end

  describe "path validation and sandboxing" do
    test "rejects paths outside sandbox directory" do
      invalid_path = "/etc/passwd"
      content = "malicious content"

      assert {:error, reason} = WriteFile.execute(%{"path" => invalid_path, "content" => content})
      assert String.contains?(reason, "not within allowed directories")
    end

    test "rejects relative paths that escape sandbox" do
      invalid_path = Path.join(@test_sandbox_dir, "../../../etc/passwd")
      content = "malicious content"

      assert {:error, reason} = WriteFile.execute(%{"path" => invalid_path, "content" => content})
      assert String.contains?(reason, "not within allowed directories")
    end

    test "normalizes paths correctly", %{sandbox_dir: sandbox_dir} do
      messy_path = Path.join(sandbox_dir, "./nested/../test.txt")
      content = "normalized path content"

      assert {:ok, result} = WriteFile.execute(%{"path" => messy_path, "content" => content})

      # Should normalize to simple path
      expected_path = Path.join(sandbox_dir, "test.txt")
      assert result["path"] == expected_path
      assert File.read!(expected_path) == content
    end
  end

  describe "error handling and edge cases" do
    test "handles missing path parameter" do
      assert {:error, reason} = WriteFile.execute(%{"content" => "test"})
      assert String.contains?(reason, "Path is required")
    end

    test "handles missing content parameter" do
      assert {:error, reason} = WriteFile.execute(%{"path" => "/tmp/test.txt"})
      assert String.contains?(reason, "Content is required")
    end

    test "handles missing both parameters" do
      assert {:error, reason} = WriteFile.execute(%{})
      assert String.contains?(reason, "Path and content are required")
    end

    test "handles nil parameters gracefully" do
      assert {:error, reason} = WriteFile.execute(nil)
      assert is_binary(reason)
    end

    test "handles invalid parameter types" do
      assert {:error, reason} = WriteFile.execute(%{"path" => 123, "content" => "test"})
      assert is_binary(reason)
    end

    test "handles invalid content type" do
      assert {:error, reason} = WriteFile.execute(%{"path" => "/tmp/test.txt", "content" => 123})
      assert is_binary(reason)
    end
  end

  describe "validate_arguments/1" do
    test "accepts valid arguments" do
      args = %{"path" => "/tmp/test.txt", "content" => "test content"}
      assert :ok = WriteFile.validate_arguments(args)
    end

    test "rejects empty path" do
      args = %{"path" => "", "content" => "test"}
      assert {:error, reason} = WriteFile.validate_arguments(args)
      assert String.contains?(reason, "Path cannot be empty")
    end

    test "rejects missing arguments" do
      assert {:error, reason} = WriteFile.validate_arguments(%{"path" => "test"})
      assert String.contains?(reason, "Invalid arguments")
    end
  end
end
