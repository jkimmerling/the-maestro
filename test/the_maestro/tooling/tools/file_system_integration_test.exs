defmodule TheMaestro.Tooling.Tools.FileSystemIntegrationTest do
  # File operations should not run concurrently
  use ExUnit.Case, async: false

  alias TheMaestro.Tooling

  # Setup test directory structure
  @test_sandbox_dir "/tmp/maestro_test_sandbox_integration"

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

  describe "FileSystem tools integration with Tooling system" do
    test "all three file system tools are registered" do
      # Get tool definitions
      definitions = Tooling.get_tool_definitions()
      tool_names = Enum.map(definitions, & &1["name"])

      assert "read_file" in tool_names
      assert "write_file" in tool_names
      assert "list_directory" in tool_names
    end

    test "can use all three tools together in a workflow", %{sandbox_dir: sandbox_dir} do
      # First, list the empty directory
      assert {:ok, list_result} = Tooling.execute_tool("list_directory", %{"path" => sandbox_dir})
      assert list_result["count"] == 0

      # Write a file
      test_file = Path.join(sandbox_dir, "integration_test.txt")
      test_content = "This is integration test content!"

      assert {:ok, write_result} =
               Tooling.execute_tool("write_file", %{
                 "path" => test_file,
                 "content" => test_content
               })

      assert write_result["message"] == "Successfully wrote to file"

      # List directory again - should have our file
      assert {:ok, list_result} = Tooling.execute_tool("list_directory", %{"path" => sandbox_dir})
      assert list_result["count"] == 1

      entry = List.first(list_result["entries"])
      assert entry["name"] == "integration_test.txt"
      assert entry["type"] == "regular"

      # Read the file back
      assert {:ok, read_result} = Tooling.execute_tool("read_file", %{"path" => test_file})
      assert read_result["content"] == test_content
      assert read_result["size"] == byte_size(test_content)
    end

    test "write_file creates directory structure and list_directory shows it", %{
      sandbox_dir: sandbox_dir
    } do
      # Create nested file structure
      nested_file = Path.join([sandbox_dir, "deep", "nested", "path", "file.txt"])
      content = "Deep nested content"

      assert {:ok, _write_result} =
               Tooling.execute_tool("write_file", %{
                 "path" => nested_file,
                 "content" => content
               })

      # List the root directory
      assert {:ok, list_result} = Tooling.execute_tool("list_directory", %{"path" => sandbox_dir})
      assert list_result["count"] == 1

      deep_dir = List.first(list_result["entries"])
      assert deep_dir["name"] == "deep"
      assert deep_dir["type"] == "directory"

      # List the deep directory
      deep_path = Path.join(sandbox_dir, "deep")
      assert {:ok, deep_list} = Tooling.execute_tool("list_directory", %{"path" => deep_path})
      assert deep_list["count"] == 1

      nested_dir = List.first(deep_list["entries"])
      assert nested_dir["name"] == "nested"
      assert nested_dir["type"] == "directory"

      # Read the final file to verify it was written correctly
      assert {:ok, read_result} = Tooling.execute_tool("read_file", %{"path" => nested_file})
      assert read_result["content"] == content
    end

    test "tools respect security boundaries consistently" do
      unsafe_path = "/etc/passwd"

      # All tools should reject unsafe paths
      assert {:error, reason1} = Tooling.execute_tool("read_file", %{"path" => unsafe_path})
      assert String.contains?(reason1, "not within allowed directories")

      assert {:error, reason2} =
               Tooling.execute_tool("write_file", %{
                 "path" => unsafe_path,
                 "content" => "malicious"
               })

      assert String.contains?(reason2, "not within allowed directories")

      assert {:error, reason3} = Tooling.execute_tool("list_directory", %{"path" => "/etc"})
      assert String.contains?(reason3, "not within allowed directories")
    end

    test "tool definitions have consistent structure" do
      definitions = Tooling.get_tool_definitions()

      file_system_tools =
        Enum.filter(definitions, fn def ->
          def["name"] in ["read_file", "write_file", "list_directory"]
        end)

      assert length(file_system_tools) == 3

      for tool_def <- file_system_tools do
        # Each tool should have required fields
        assert is_binary(tool_def["name"])
        assert is_binary(tool_def["description"])
        assert is_map(tool_def["parameters"])
        assert tool_def["parameters"]["type"] == "object"
        assert is_map(tool_def["parameters"]["properties"])
        assert is_list(tool_def["parameters"]["required"])

        # All tools should require a path parameter
        assert "path" in tool_def["parameters"]["required"]
        assert is_map(tool_def["parameters"]["properties"]["path"])
        assert tool_def["parameters"]["properties"]["path"]["type"] == "string"
      end

      # write_file should also require content
      write_tool = Enum.find(file_system_tools, &(&1["name"] == "write_file"))
      assert "content" in write_tool["parameters"]["required"]
      assert is_map(write_tool["parameters"]["properties"]["content"])
    end
  end
end
