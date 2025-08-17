defmodule TheMaestro.MCP.ProtocolTest do
  use ExUnit.Case, async: true

  alias TheMaestro.MCP.Protocol

  describe "initialize/2" do
    test "creates proper initialize message with client info" do
      request_id = "test-123"
      client_info = %{name: "the_maestro", version: "1.0.0"}

      message = Protocol.initialize(request_id, client_info)

      assert message.jsonrpc == "2.0"
      assert message.id == request_id
      assert message.method == "initialize"
      assert message.params.protocolVersion == "2024-11-05"
      assert message.params.clientInfo == client_info
      assert message.params.capabilities.tools.listChanged == true
      assert message.params.capabilities.resources.subscribe == true
      assert message.params.capabilities.resources.listChanged == true
    end
  end

  describe "list_tools/1" do
    test "creates proper list_tools message" do
      request_id = "list-tools-123"

      message = Protocol.list_tools(request_id)

      assert message.jsonrpc == "2.0"
      assert message.id == request_id
      assert message.method == "tools/list"
      assert message.params == %{}
    end
  end

  describe "call_tool/3" do
    test "creates proper call_tool message" do
      request_id = "call-tool-123"
      tool_name = "test_tool"
      arguments = %{"param1" => "value1", "param2" => 42}

      message = Protocol.call_tool(request_id, tool_name, arguments)

      assert message.jsonrpc == "2.0"
      assert message.id == request_id
      assert message.method == "tools/call"
      assert message.params.name == tool_name
      assert message.params.arguments == arguments
    end
  end

  describe "validate_message/1" do
    test "validates correct JSON-RPC message" do
      message = %{
        jsonrpc: "2.0",
        id: "test-123",
        method: "test",
        params: %{}
      }

      assert {:ok, validated} = Protocol.validate_message(message)
      assert validated.jsonrpc == "2.0"
      assert validated.id == "test-123"
    end

    test "rejects message without jsonrpc field" do
      message = %{
        id: "test-123",
        method: "test"
      }

      assert {:error, _reason} = Protocol.validate_message(message)
    end

    test "rejects message with wrong jsonrpc version" do
      message = %{
        jsonrpc: "1.0",
        id: "test-123",
        method: "test"
      }

      assert {:error, _reason} = Protocol.validate_message(message)
    end
  end

  describe "format_error/3" do
    test "formats MCP protocol error" do
      request_id = "error-123"
      code = -32_600
      message = "Invalid Request"

      error = Protocol.format_error(request_id, code, message)

      assert error.jsonrpc == "2.0"
      assert error.id == request_id
      assert error.error.code == code
      assert error.error.message == message
    end

    test "formats error with additional data" do
      request_id = "error-456"
      code = -32_603
      message = "Internal error"
      data = %{details: "Something went wrong"}

      error = Protocol.format_error(request_id, code, message, data)

      assert error.error.data == data
    end
  end

  describe "parse_response/1" do
    test "parses successful response" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => "test-123",
        "result" => %{"status" => "success"}
      }

      assert {:ok, parsed} = Protocol.parse_response(response)
      assert parsed.id == "test-123"
      assert parsed.result.status == "success"
    end

    test "parses error response" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => "test-123",
        "error" => %{
          "code" => -32_600,
          "message" => "Invalid Request"
        }
      }

      assert {:error, error} = Protocol.parse_response(response)
      assert error.code == -32_600
      assert error.message == "Invalid Request"
    end
  end
end
