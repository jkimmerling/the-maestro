defmodule TheMaestro.Streaming.StreamHandler do
  @moduledoc """
  Behaviour for provider-specific streaming event handlers.

  Each AI provider has different streaming event formats and semantics.
  This behaviour defines the interface that each provider handler must implement
  to convert provider-specific events to the unified message format.

  ## Event Processing Flow

  1. Raw SSE events are parsed by the main Streaming module
  2. Events are passed to the provider-specific handler
  3. Handler converts events to standardized message format
  4. Messages are yielded to the consumer

  ## Handler Responsibilities

  - Parse provider-specific event data (JSON, etc.)
  - Track streaming state (function calls, usage, etc.)
  - Convert events to standardized message format
  - Handle provider-specific error conditions
  - Manage state cleanup and resource management

  ## State Management

  Handlers may need to maintain state between events:
  - Accumulating function call arguments across multiple events
  - Tracking usage data that comes in separate events
  - Managing partial content that spans multiple events

  ## Error Handling

  Handlers should be resilient to malformed events and return
  error messages rather than crashing the stream.
  """

  @type sse_event :: %{
    event_type: String.t(),
    data: String.t()
  }

  @type stream_message :: %{
    type: :content | :function_call | :usage | :error | :done,
    content: String.t() | nil,
    function_call: map() | nil,
    usage: map() | nil,
    error: String.t() | nil,
    metadata: map()
  }

  @type handler_state :: term()
  @type handler_options :: keyword()

  @doc """
  Handle a streaming event from the provider.

  Converts provider-specific SSE events to standardized message format.
  May return multiple messages per event or maintain state across events.

  ## Parameters

    * `event` - Parsed SSE event with event_type and data
    * `opts` - Handler options and configuration

  ## Returns

    * List of standardized stream messages

  ## State Management

  Handlers that need to maintain state should store it in the process dictionary
  or use a GenServer/Agent for concurrent safety.

  ## Examples

      # Simple content event
      iex> handle_event(%{event_type: "delta", data: ~s/{"delta": "Hello"}/}, [])
      [%{type: :content, content: "Hello", metadata: %{}}]

      # Function call event (may return empty list while accumulating)
      iex> handle_event(%{event_type: "function_start", data: ~s/{"id": "call_1", "name": "get_weather"}/}, [])
      []

      # Error event
      iex> handle_event(%{event_type: "error", data: ~s/{"error": "Rate limit"}/}, [])
      [%{type: :error, error: "Rate limit", metadata: %{}}]

  """
  @callback handle_event(sse_event(), handler_options()) :: [stream_message()]

  @doc """
  Initialize handler state (optional).

  Called when the stream starts. Handlers can use this to set up
  any required state or configuration.

  ## Parameters

    * `opts` - Handler options and configuration

  ## Returns

    * `:ok` - Handler initialized successfully
    * `{:error, reason}` - Initialization failed

  """
  @callback init(handler_options()) :: :ok | {:error, term()}

  @doc """
  Clean up handler state (optional).

  Called when the stream ends or encounters an error.
  Handlers can use this to clean up resources or state.

  ## Parameters

    * `opts` - Handler options and configuration

  ## Returns

    * `:ok` - Cleanup completed

  """
  @callback cleanup(handler_options()) :: :ok

  # Provide default implementations for optional callbacks
  @optional_callbacks init: 1, cleanup: 1

  defmacro __using__(_opts) do
    quote do
      @behaviour TheMaestro.Streaming.StreamHandler

      # Default implementations
      def init(_opts), do: :ok
      def cleanup(_opts), do: :ok

      defoverridable init: 1, cleanup: 1

      # Helper function to create error messages
      def error_message(error, metadata \\ %{}) do
        %{
          type: :error,
          error: error,
          content: nil,
          function_call: nil,
          usage: nil,
          metadata: metadata
        }
      end

      # Helper function to create content messages
      def content_message(content, metadata \\ %{}) do
        %{
          type: :content,
          content: content,
          function_call: nil,
          usage: nil,
          error: nil,
          metadata: metadata
        }
      end

      # Helper function to create function call messages
      def function_call_message(function_call, metadata \\ %{}) do
        %{
          type: :function_call,
          content: nil,
          function_call: function_call,
          usage: nil,
          error: nil,
          metadata: metadata
        }
      end

      # Helper function to create usage messages
      def usage_message(usage, metadata \\ %{}) do
        %{
          type: :usage,
          content: nil,
          function_call: nil,
          usage: usage,
          error: nil,
          metadata: metadata
        }
      end

      # Helper function to create done messages
      def done_message(metadata \\ %{}) do
        %{
          type: :done,
          content: nil,
          function_call: nil,
          usage: nil,
          error: nil,
          metadata: metadata
        }
      end

      # Helper function to safely parse JSON
      def safe_json_decode(data) do
        case Jason.decode(data) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, "JSON parse error: #{inspect(reason)}"}
        end
      end
    end
  end
end
