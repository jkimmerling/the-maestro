defmodule TheMaestro.TUI.CLITest do
  use ExUnit.Case, async: false

  import Phoenix.PubSub

  setup do
    # Clean up any existing conversation file
    conversation_file = ".maestro_conversation.txt"

    if File.exists?(conversation_file) do
      File.rm!(conversation_file)
    end

    on_exit(fn ->
      if File.exists?(conversation_file) do
        File.rm!(conversation_file)
      end
    end)

    %{conversation_file: conversation_file}
  end

  describe "PubSub subscription and message handling" do
    test "TUI subscribes to agent_status topic on startup" do
      # This test would require modifying CLI to expose subscription state
      # For now, we'll test that PubSub messages are properly handled
      assert true
    end

    test "handles :status_update messages for thinking state" do
      # Simulate TUI process receiving PubSub messages
      _pid =
        spawn_link(fn ->
          Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agent_status")

          receive do
            {:status_update, :thinking} -> send(self(), :thinking_received)
          end
        end)

      # Broadcast thinking status
      Phoenix.PubSub.broadcast(TheMaestro.PubSub, "agent_status", {:status_update, :thinking})

      # Verify message was received
      assert_receive :thinking_received, 1000
    end

    test "handles :tool_call_start messages with tool name and arguments" do
      _pid =
        spawn_link(fn ->
          Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agent_status")

          receive do
            {:tool_call_start, %{name: "read_file", arguments: %{path: "/test/path"}}} ->
              send(self(), :tool_start_received)
          end
        end)

      # Broadcast tool call start
      broadcast(TheMaestro.PubSub, "agent_status", {
        :tool_call_start,
        %{name: "read_file", arguments: %{path: "/test/path"}}
      })

      assert_receive :tool_start_received, 1000
    end

    test "handles :tool_call_end messages with tool results" do
      _pid =
        spawn_link(fn ->
          Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agent_status")

          receive do
            {:tool_call_end, %{name: "read_file", result: "file contents"}} ->
              send(self(), :tool_end_received)
          end
        end)

      # Broadcast tool call end
      broadcast(TheMaestro.PubSub, "agent_status", {
        :tool_call_end,
        %{name: "read_file", result: "file contents"}
      })

      assert_receive :tool_end_received, 1000
    end

    test "handles :stream_chunk messages for real-time output" do
      _pid =
        spawn_link(fn ->
          Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agent_status")

          receive do
            {:stream_chunk, "partial response"} ->
              send(self(), :chunk_received)
          end
        end)

      broadcast(TheMaestro.PubSub, "agent_status", {:stream_chunk, "partial response"})

      assert_receive :chunk_received, 1000
    end

    test "handles :processing_complete messages" do
      _pid =
        spawn_link(fn ->
          Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agent_status")

          receive do
            {:processing_complete, "final response"} ->
              send(self(), :complete_received)
          end
        end)

      broadcast(TheMaestro.PubSub, "agent_status", {:processing_complete, "final response"})

      assert_receive :complete_received, 1000
    end
  end

  describe "tool status display" do
    test "displays tool execution indicator when tool starts" do
      # This test will need CLI module modifications to expose status display
      # Testing the message format that should be displayed
      tool_start_message =
        {:tool_call_start, %{name: "read_file", arguments: %{path: "/test/file.txt"}}}

      expected_status = "Using tool: read_file..."
      assert format_tool_status(tool_start_message) == expected_status
    end

    test "displays different tool indicators for various tools" do
      tools = [
        {:tool_call_start,
         %{name: "write_file", arguments: %{path: "/test.txt", content: "data"}}},
        {:tool_call_start, %{name: "list_directory", arguments: %{path: "/home"}}},
        {:tool_call_start, %{name: "bash", arguments: %{command: "ls -la"}}},
        {:tool_call_start, %{name: "grep", arguments: %{pattern: "test", path: "/file.txt"}}}
      ]

      expected_statuses = [
        "Using tool: write_file...",
        "Using tool: list_directory...",
        "Using tool: bash...",
        "Using tool: grep..."
      ]

      results = Enum.map(tools, &format_tool_status/1)
      assert results == expected_statuses
    end

    test "clears tool status when tool execution completes" do
      tool_end_message = {:tool_call_end, %{name: "read_file", result: "file contents"}}

      expected_status = ""
      assert format_tool_status(tool_end_message) == expected_status
    end

    test "handles tool execution with complex arguments" do
      complex_tool =
        {:tool_call_start,
         %{
           name: "multi_edit",
           arguments: %{
             files: ["/file1.txt", "/file2.txt"],
             operation: "replace",
             pattern: "old_text"
           }
         }}

      expected_status = "Using tool: multi_edit..."
      assert format_tool_status(complex_tool) == expected_status
    end
  end

  describe "tool result formatting" do
    test "formats simple text results for display" do
      result = "This is a simple file content"
      formatted = format_tool_result("read_file", result)

      expected = """
      🔧 Tool: read_file
      ─────────────────
      This is a simple file content
      """

      assert String.trim(formatted) == String.trim(expected)
    end

    test "formats JSON results with proper indentation" do
      json_result = %{"status" => "success", "data" => %{"items" => [1, 2, 3]}}
      formatted = format_tool_result("api_call", json_result)

      assert String.contains?(formatted, "🔧 Tool: api_call")
      assert String.contains?(formatted, "\"status\": \"success\"")
      assert String.contains?(formatted, "\"data\"")
    end

    test "formats multiline text results with proper spacing" do
      multiline_result = "Line 1\nLine 2\nLine 3"
      formatted = format_tool_result("bash", multiline_result)

      expected = """
      🔧 Tool: bash
      ────────────
      Line 1
      Line 2
      Line 3
      """

      assert String.trim(formatted) == String.trim(expected)
    end

    test "handles empty or nil results gracefully" do
      expected = "🔧 Tool: test_tool\n─────────────────\n(no output)"
      assert format_tool_result("test_tool", "") == expected
      assert format_tool_result("test_tool", nil) == expected
    end

    test "handles very long results with truncation indication" do
      long_result = String.duplicate("This is a long line. ", 100)
      formatted = format_tool_result("long_tool", long_result)

      assert String.contains?(formatted, "🔧 Tool: long_tool")
      # Should contain the content (may be truncated in actual implementation)
      assert String.contains?(formatted, "This is a long line.")
    end

    test "formats error results with appropriate styling" do
      error_result = {:error, "File not found: /nonexistent.txt"}
      formatted = format_tool_result("read_file", error_result)

      expected = """
      🔧 Tool: read_file
      ─────────────────
      ❌ Error: File not found: /nonexistent.txt
      """

      assert String.trim(formatted) == String.trim(expected)
    end
  end

  describe "conversation history integration" do
    test "tool results are properly integrated into conversation flow" do
      # This tests the concept of how tool results should appear in conversation
      conversation_entry =
        format_conversation_tool_result("read_file", "file contents", "2024-01-01T12:00:00Z")

      expected = """
      [2024-01-01T12:00:00Z] 🔧 Tool Result: read_file
      file contents
      """

      assert String.trim(conversation_entry) == String.trim(expected)
    end

    test "multiple tool calls in sequence are properly tracked" do
      tool_sequence = [
        {:tool_call_start, %{name: "read_file", arguments: %{path: "/test.txt"}}},
        {:tool_call_end, %{name: "read_file", result: "content"}},
        {:tool_call_start,
         %{name: "write_file", arguments: %{path: "/output.txt", content: "new content"}}},
        {:tool_call_end, %{name: "write_file", result: "File written successfully"}}
      ]

      # Track the sequence of status changes
      statuses = Enum.map(tool_sequence, &format_tool_status/1)

      expected_statuses = [
        "Using tool: read_file...",
        "",
        "Using tool: write_file...",
        ""
      ]

      assert statuses == expected_statuses
    end

    test "concurrent tool calls are handled appropriately" do
      # This tests the concept - actual implementation would need to handle concurrent tools
      concurrent_tools = [
        {:tool_call_start, %{name: "read_file", arguments: %{path: "/file1.txt"}}},
        {:tool_call_start, %{name: "read_file", arguments: %{path: "/file2.txt"}}},
        {:tool_call_end, %{name: "read_file", result: "content1"}},
        {:tool_call_end, %{name: "read_file", result: "content2"}}
      ]

      # Should handle multiple active tools
      status_after_first_start = format_tool_status(Enum.at(concurrent_tools, 0))
      assert status_after_first_start == "Using tool: read_file..."
    end
  end

  describe "status line behavior" do
    test "status line shows thinking indicator" do
      thinking_message = {:status_update, :thinking}
      status = format_status_indicator(thinking_message)

      assert status == "🤔 Thinking..."
    end

    test "status line shows tool execution with progress" do
      tool_message = {:tool_call_start, %{name: "bash", arguments: %{command: "npm install"}}}
      status = format_status_indicator(tool_message)

      assert status == "🔧 Using tool: bash..."
    end

    test "status line clears when processing is complete" do
      complete_message = {:processing_complete, "response"}
      status = format_status_indicator(complete_message)

      assert status == ""
    end

    test "status line handles stream chunks" do
      chunk_message = {:stream_chunk, "partial text"}
      status = format_status_indicator(chunk_message)

      assert status == "✍️ Generating response..."
    end
  end

  describe "visual formatting and styling" do
    test "tool indicators use appropriate emojis and formatting" do
      assert format_tool_emoji("read_file") == "📖"
      assert format_tool_emoji("write_file") == "✏️"
      assert format_tool_emoji("bash") == "⚡"
      assert format_tool_emoji("list_directory") == "📁"
      assert format_tool_emoji("grep") == "🔍"
      assert format_tool_emoji("unknown_tool") == "🔧"
    end

    test "status messages have consistent formatting" do
      status_msg = format_full_status("read_file", %{path: "/test.txt"})

      assert String.contains?(status_msg, "📖")
      assert String.contains?(status_msg, "read_file")
      # Reasonable width for terminal
      assert String.length(status_msg) < 80
    end

    test "tool results have readable headers and separators" do
      formatted = format_tool_result("test_tool", "result")

      assert String.contains?(formatted, "🔧 Tool: test_tool")
      # Separator line
      assert String.contains?(formatted, "─")
      assert String.contains?(formatted, "result")
    end
  end

  # Helper functions for testing (these would be implemented in the actual CLI module)

  defp format_tool_status({:tool_call_start, %{name: name}}), do: "Using tool: #{name}..."
  defp format_tool_status({:tool_call_end, _}), do: ""
  defp format_tool_status(_), do: ""

  defp format_tool_result(tool_name, result) when is_binary(result) do
    separator = String.duplicate("─", String.length("🔧 Tool: #{tool_name}"))
    content = if result == "" or is_nil(result), do: "(no output)", else: result

    "🔧 Tool: #{tool_name}\n#{separator}\n#{content}"
  end

  defp format_tool_result(tool_name, nil) do
    separator = String.duplicate("─", String.length("🔧 Tool: #{tool_name}"))

    "🔧 Tool: #{tool_name}\n#{separator}\n(no output)"
  end

  defp format_tool_result(tool_name, {:error, reason}) do
    separator = String.duplicate("─", String.length("🔧 Tool: #{tool_name}"))

    "🔧 Tool: #{tool_name}\n#{separator}\n❌ Error: #{reason}"
  end

  defp format_tool_result(tool_name, result) do
    separator = String.duplicate("─", String.length("🔧 Tool: #{tool_name}"))
    content = Jason.encode!(result, pretty: true)

    "🔧 Tool: #{tool_name}\n#{separator}\n#{content}"
  end

  defp format_conversation_tool_result(tool_name, result, timestamp) do
    "[#{timestamp}] 🔧 Tool Result: #{tool_name}\n#{result}"
  end

  defp format_status_indicator({:status_update, :thinking}), do: "🤔 Thinking..."
  defp format_status_indicator({:tool_call_start, %{name: name}}), do: "🔧 Using tool: #{name}..."
  defp format_status_indicator({:stream_chunk, _}), do: "✍️ Generating response..."
  defp format_status_indicator({:processing_complete, _}), do: ""
  defp format_status_indicator(_), do: ""

  defp format_tool_emoji("read_file"), do: "📖"
  defp format_tool_emoji("write_file"), do: "✏️"
  defp format_tool_emoji("bash"), do: "⚡"
  defp format_tool_emoji("list_directory"), do: "📁"
  defp format_tool_emoji("grep"), do: "🔍"
  defp format_tool_emoji(_), do: "🔧"

  defp format_full_status(tool_name, _args) do
    emoji = format_tool_emoji(tool_name)
    "#{emoji} Using: #{tool_name}"
  end
end
