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
  def complete_text(_auth_context, messages, _opts \\ %{}) do
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
    # For tool completions, just return text content (no tool calls)
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
end
