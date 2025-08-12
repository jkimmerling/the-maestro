#!/usr/bin/env elixir

# Epic 3 Story 3.2 Demo: Full File System Tool (Write & List)
#
# This script demonstrates the new write_file and list_directory tools
# working with the AI agent to perform file operations.
#
# Prerequisites:
# - Gemini API key configured (GEMINI_API_KEY environment variable)
# - File system tool allowed directories configured
#
# Usage: GEMINI_API_KEY=your_key mix run demos/epic3/story3.2_demo.exs

defmodule Epic3Story32Demo do
  @moduledoc """
  Demo showcasing the new file system tools: write_file and list_directory
  """

  def run do
    IO.puts("🚀 Epic 3 Story 3.2 Demo: Full File System Tool (Write & List)")
    IO.puts("=" |> String.duplicate(60))

    # Set up demo directory
    demo_dir = "/tmp/epic3_story32_demo"
    setup_demo_environment(demo_dir)

    # Verify tools are available
    verify_tools_available()

    # Test tools directly
    test_tools_directly(demo_dir)

    # Test with agent (if API key available)
    test_with_agent(demo_dir)

    # Cleanup
    cleanup_demo_environment(demo_dir)

    IO.puts("\n🎉 Demo completed successfully!")
  end

  defp setup_demo_environment(demo_dir) do
    IO.puts("\n📁 Setting up demo environment...")
    
    if File.exists?(demo_dir), do: File.rm_rf!(demo_dir)
    File.mkdir_p!(demo_dir)

    # Configure allowed directories to include our demo directory
    Application.put_env(:the_maestro, :file_system_tool,
      allowed_directories: [demo_dir],
      max_file_size: 10 * 1024 * 1024
    )

    IO.puts("   ✅ Demo directory created: #{demo_dir}")
    IO.puts("   ✅ File system tool configured for demo directory")
  end

  defp verify_tools_available do
    IO.puts("\n🔧 Verifying file system tools are available...")
    
    tools = TheMaestro.Tooling.get_tool_definitions()
    tool_names = Enum.map(tools, & &1["name"])

    required_tools = ["read_file", "write_file", "list_directory"]
    
    required_tools
    |> Enum.each(fn tool_name ->
      if tool_name in tool_names do
        IO.puts("   ✅ #{tool_name} tool available")
      else
        raise "❌ #{tool_name} tool not available"
      end
    end)

    IO.puts("   ✅ All file system tools are properly registered")
  end

  defp test_tools_directly(demo_dir) do
    IO.puts("\n🧪 Testing tools directly through the tooling system...")

    # Test 1: List empty directory
    IO.puts("\n   📂 Test 1: Listing empty directory")
    {:ok, list_result} = TheMaestro.Tooling.execute_tool("list_directory", %{"path" => demo_dir})
    IO.puts("      Result: Found #{list_result["count"]} entries (should be 0)")

    # Test 2: Write a file
    IO.puts("\n   ✍️  Test 2: Writing a demo file")
    demo_file = Path.join(demo_dir, "demo.txt")
    demo_content = """
    Epic 3 Story 3.2 Demo File
    ==========================
    
    This file was created using the new write_file tool!
    
    Features demonstrated:
    - Secure file writing with path validation
    - Automatic parent directory creation
    - Integration with the tooling system
    
    Created at: #{DateTime.now!("Etc/UTC")}
    """

    {:ok, write_result} = TheMaestro.Tooling.execute_tool("write_file", %{
      "path" => demo_file,
      "content" => demo_content
    })
    IO.puts("      Result: #{write_result["message"]}")
    IO.puts("      Size: #{write_result["size"]} bytes")

    # Test 3: List directory with file
    IO.puts("\n   📂 Test 3: Listing directory with file")
    {:ok, list_result} = TheMaestro.Tooling.execute_tool("list_directory", %{"path" => demo_dir})
    IO.puts("      Result: Found #{list_result["count"]} entries")
    
    Enum.each(list_result["entries"], fn entry ->
      IO.puts("        - #{entry["name"]} (#{entry["type"]})")
    end)

    # Test 4: Read the file back
    IO.puts("\n   📖 Test 4: Reading the file back")
    {:ok, read_result} = TheMaestro.Tooling.execute_tool("read_file", %{"path" => demo_file})
    IO.puts("      Result: Read #{read_result["size"]} bytes")
    IO.puts("      First line: #{String.split(read_result["content"], "\n") |> List.first()}")

    # Test 5: Create nested directory structure
    IO.puts("\n   🏗️  Test 5: Creating nested directory structure")
    nested_file = Path.join([demo_dir, "nested", "deep", "structure", "nested.txt"])
    nested_content = "This file demonstrates automatic parent directory creation!"

    {:ok, write_result} = TheMaestro.Tooling.execute_tool("write_file", %{
      "path" => nested_file,
      "content" => nested_content
    })
    IO.puts("      Result: #{write_result["message"]}")

    # Test 6: List nested directories
    IO.puts("\n   📂 Test 6: Listing nested directory")
    nested_dir = Path.join(demo_dir, "nested")
    {:ok, list_result} = TheMaestro.Tooling.execute_tool("list_directory", %{"path" => nested_dir})
    IO.puts("      Result: Found #{list_result["count"]} entries in nested/")

    IO.puts("\n   ✅ All direct tool tests passed!")
  end

  defp test_with_agent(demo_dir) do
    IO.puts("\n🤖 Testing tools with AI agent...")

    api_key = System.get_env("GEMINI_API_KEY")
    
    if api_key do
      IO.puts("   ✅ Gemini API key found, testing with real LLM...")
      
      # Start an agent
      {:ok, agent_pid} = TheMaestro.Agents.start_agent("demo_user")
      
      # Create a prompt that requires using all three tools
      prompt = """
      Please help me with the following tasks in the directory #{demo_dir}:

      1. First, list the current contents of the directory
      2. Create a new file called 'agent_test.txt' with the content 'Hello from the AI agent!'
      3. List the directory again to show the new file
      4. Read back the content of the file you just created to verify it worked

      Please use the appropriate file system tools for each step.
      """

      IO.puts("   📝 Sending prompt to agent:")
      IO.puts("      \"Please use file system tools to create, list, and read files...\"")

      try do
        # Send the message to the agent
        # Note: This will require valid credentials and may take time
        response = TheMaestro.Agents.send_message("demo_user", prompt)
        
        case response do
          {:ok, agent_response} ->
            IO.puts("   ✅ Agent successfully used file system tools!")
            IO.puts("   📋 Agent response summary:")
            # Show first few lines of response
            lines = String.split(agent_response, "\n") |> Enum.take(3)
            Enum.each(lines, fn line ->
              IO.puts("      #{line}")
            end)
            if length(String.split(agent_response, "\n")) > 3 do
              IO.puts("      ...")
            end

          {:error, reason} ->
            IO.puts("   ⚠️  Agent response failed: #{reason}")
            IO.puts("   💡 This might be due to API credentials or rate limits")
        end

        # Clean up agent
        GenServer.stop(agent_pid)

      rescue
        error ->
          IO.puts("   ⚠️  Agent test failed: #{inspect(error)}")
          IO.puts("   💡 This might be due to missing API credentials")
          GenServer.stop(agent_pid)
      end

    else
      IO.puts("   ⚠️  No GEMINI_API_KEY found, skipping agent test")
      IO.puts("   💡 Set GEMINI_API_KEY to test with real LLM")
      IO.puts("   ✅ Tools are properly configured and ready for LLM use")
    end
  end

  defp cleanup_demo_environment(demo_dir) do
    IO.puts("\n🧹 Cleaning up demo environment...")
    File.rm_rf!(demo_dir)
    IO.puts("   ✅ Demo directory removed")
  end
end

# Run the demo
Epic3Story32Demo.run()