defmodule TheMaestro.Providers.TestProvider do
  @moduledoc """
  Test LLM Provider for use in tests and development.
  This provider returns hardcoded responses instead of calling actual LLM APIs,
  making it useful for testing and development scenarios where you don't want
  to make real API calls.
  """

  @behaviour TheMaestro.Providers.LLMProvider

  alias TheMaestro.Providers.LLMProvider

  @impl LLMProvider
  def initialize_auth(_config \\ %{}) do
    {:ok,
     %{
       type: :test,
       credentials: %{test: true},
       config: %{}
     }}
  end

  @impl LLMProvider
  def complete_text(_auth_context, messages, opts \\ %{}) do
    # Return a hardcoded response that echoes the last user message
    last_user_message =
      messages
      |> Enum.reverse()
      |> Enum.find(fn msg -> msg.role == :user end)

    response_content =
      case last_user_message do
        %{content: content} ->
          "I received your message: \"#{content}\". This is a test response."

        _ ->
          "This is a test response."
      end

    # If streaming callback is provided, simulate streaming
    if stream_callback = Map.get(opts, :stream_callback) do
      simulate_streaming(response_content, stream_callback)
    end

    {:ok,
     %{
       content: response_content,
       model: "test-model",
       usage: %{
         prompt_tokens: 10,
         completion_tokens: 20,
         total_tokens: 30
       }
     }}
  end

  @impl LLMProvider
  def complete_with_tools(auth_context, messages, opts \\ %{}) do
    # Check if the message contains tool-related keywords to simulate tool calls
    last_user_message =
      messages
      |> Enum.reverse()
      |> Enum.find(fn msg -> msg.role == :user end)

    should_use_tool =
      case last_user_message do
        %{content: content} -> String.contains?(content, "read_file")
        _ -> false
      end

    if should_use_tool do
      # Simulate a tool call
      tool_calls = [
        %{
          "id" => "test_tool_call_1",
          "name" => "read_file",
          "arguments" => %{"path" => "test_file.txt"}
        }
      ]

      {:ok,
       %{
         content: "I need to read the file for you.",
         tool_calls: tool_calls,
         model: "test-model",
         usage: %{
           prompt_tokens: 10,
           completion_tokens: 20,
           total_tokens: 30
         }
       }}
    else
      # No tool calls, just return text content
      case complete_text(auth_context, messages, opts) do
        {:ok, response} ->
          {:ok,
           %{
             content: response.content,
             tool_calls: [],
             model: response.model,
             usage: response.usage
           }}
      end
    end
  end

  @impl LLMProvider
  def refresh_auth(auth_context) do
    # Test provider doesn't need refresh
    {:ok, auth_context}
  end

  @impl LLMProvider
  def validate_auth(%{type: :test}) do
    :ok
  end

  def validate_auth(_) do
    {:error, :invalid_test_auth}
  end

  @impl LLMProvider
  def list_models(_auth_context) do
    {:ok, [
      %{
        id: "test-model-1",
        name: "Test Model 1",
        description: "A test model for development",
        context_length: 4096,
        multimodal: false,
        function_calling: true,
        cost_tier: "free"
      },
      %{
        id: "test-model-2",
        name: "Test Model 2", 
        description: "Another test model for development",
        context_length: 8192,
        multimodal: true,
        function_calling: true,
        cost_tier: "free"
      }
    ]}
  end

  # Helper function to simulate streaming
  defp simulate_streaming(content, stream_callback) do
    # Split content into words and stream them
    words = String.split(content, " ")

    Enum.each(words, fn word ->
      # Small delay to simulate real streaming
      Process.sleep(50)
      stream_callback.({:chunk, word <> " "})
    end)

    # Send completion signal
    stream_callback.(:complete)
  end
end
