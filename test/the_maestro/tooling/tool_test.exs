defmodule TheMaestro.Tooling.ToolTest do
  use ExUnit.Case, async: true
  doctest TheMaestro.Tooling.Tool

  alias TheMaestro.Tooling.Tool

  # Test implementation of Tool behaviour
  defmodule TestTool do
    use TheMaestro.Tooling.Tool

    @impl true
    def definition do
      %{
        "name" => "test_tool",
        "description" => "A test tool for unit testing",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "action" => %{
              "type" => "string",
              "description" => "Action to perform"
            },
            "data" => %{
              "type" => "string",
              "description" => "Test data"
            }
          },
          "required" => ["action"]
        }
      }
    end

    @impl true
    def execute(%{"action" => "success"} = args) do
      {:ok, %{result: "success", params: args}}
    end

    def execute(%{"action" => "error"} = args) do
      {:error, %{reason: "test_error", params: args}}
    end

    def execute(%{"action" => "exception"}) do
      raise "test exception"
    end

    def execute(args) do
      {:error, %{reason: "unknown_action", params: args}}
    end
  end

  describe "Tool behaviour" do
    test "defines required callbacks" do
      callbacks = Tool.behaviour_info(:callbacks)
      assert {:definition, 0} in callbacks
      assert {:execute, 1} in callbacks
    end

    test "using Tool sets up default validation" do
      assert function_exported?(TestTool, :validate_arguments, 1)
      assert function_exported?(TestTool, :definition, 0)
      assert function_exported?(TestTool, :execute, 1)
    end
  end

  describe "Tool implementation" do
    test "successful execution returns {:ok, result}" do
      assert {:ok, result} = TestTool.execute(%{"action" => "success", "data" => "test"})
      assert result.result == "success"
      assert result.params["data"] == "test"
    end

    test "error execution returns {:error, reason}" do
      assert {:error, reason} = TestTool.execute(%{"action" => "error", "data" => "test"})
      assert reason.reason == "test_error"
      assert reason.params["data"] == "test"
    end

    test "handles unknown actions gracefully" do
      assert {:error, reason} = TestTool.execute(%{"action" => "unknown"})
      assert reason.reason == "unknown_action"
    end

    test "can handle exceptions (should be caught by caller)" do
      assert_raise RuntimeError, "test exception", fn ->
        TestTool.execute(%{"action" => "exception"})
      end
    end

    test "validates arguments against schema" do
      # Valid arguments
      assert :ok = TestTool.validate_arguments(%{"action" => "test"})

      # Missing required parameter
      assert {:error, reason} = TestTool.validate_arguments(%{})
      assert String.contains?(reason, "Missing required parameters")
    end

    test "handles empty parameters" do
      assert {:error, _reason} = TestTool.validate_arguments(%{})
    end
  end

  describe "Tool definition format" do
    test "returns proper OpenAI function format" do
      definition = TestTool.definition()

      assert is_map(definition)
      assert definition["name"] == "test_tool"
      assert is_binary(definition["description"])
      assert is_map(definition["parameters"])
      assert definition["parameters"]["type"] == "object"
      assert is_map(definition["parameters"]["properties"])
      assert is_list(definition["parameters"]["required"])
    end

    test "includes required parameters list" do
      definition = TestTool.definition()
      required = definition["parameters"]["required"]

      assert "action" in required
    end

    test "includes parameter descriptions" do
      definition = TestTool.definition()
      properties = definition["parameters"]["properties"]

      assert Map.has_key?(properties, "action")
      assert is_binary(properties["action"]["description"])
    end
  end
end
