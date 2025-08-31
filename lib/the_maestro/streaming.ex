defmodule TheMaestro.Streaming do
  @moduledoc """
  Generic streaming parser for multiple AI providers (OpenAI, Anthropic, Gemini).

  This module provides a unified interface for parsing streaming responses from different
  AI providers, handling Server-Sent Events (SSE) and converting provider-specific
  streaming formats to a common message format.

  ## Supported Providers

  - **OpenAI**: ChatGPT API streaming with SSE events
  - **Anthropic**: Claude streaming with MessageStreamEvent format
  - **Gemini**: Google AI streaming with generateContentStream format

  ## Usage

      stream = TheMaestro.Streaming.parse_stream(response_stream, :openai)

      for message <- stream do
        case message do
          %{type: :content, content: text} -> IO.write(text)
          %{type: :function_call, function_call: call} -> handle_function_call(call)
          %{type: :usage, usage: usage} -> handle_usage(usage)
          %{type: :error, error: error} -> handle_error(error)
        end
      end

  ## Message Format

  All providers return messages in a standardized format:

      %{
        type: :content | :function_call | :usage | :error | :done,
        content: String.t() | nil,
        function_call: map() | nil,
        usage: map() | nil,
        error: String.t() | nil,
        metadata: map()
      }

  ## Provider-Specific Handlers

  Each provider has its own handler module that implements the `StreamHandler` behaviour:

  - `TheMaestro.Streaming.OpenAIHandler`
  - `TheMaestro.Streaming.AnthropicHandler`
  - `TheMaestro.Streaming.GeminiHandler`

  ## Error Handling

  Stream parsing errors are yielded as error messages rather than raising exceptions,
  allowing the stream consumer to handle errors gracefully while continuing to process
  subsequent events.
  """

  require Logger

  @type provider :: :openai | :anthropic | :gemini
  @type message_type :: :content | :function_call | :usage | :error | :done

  @type stream_message :: %{
          type: message_type(),
          content: String.t() | nil,
          function_call: map() | nil,
          usage: map() | nil,
          error: String.t() | nil,
          metadata: map()
        }

  @doc """
  Parse a streaming response from the specified provider.

  ## Parameters

    * `stream` - ReadableStream or Finch stream response
    * `provider` - Provider identifier (:openai, :anthropic, :gemini)
    * `opts` - Optional configuration (default: [])

  ## Options

    * `:buffer_size` - Size of internal buffer for SSE parsing (default: 8192)
    * `:timeout` - Timeout for stream operations (default: :infinity)
    * `:include_raw` - Include raw event data in metadata (default: false)

  ## Returns

    * Stream of `stream_message()` structs

  ## Examples

      # Parse OpenAI streaming response
      stream = TheMaestro.Streaming.parse_stream(finch_response, :openai)

      # Parse with custom buffer size
      stream = TheMaestro.Streaming.parse_stream(response, :anthropic, buffer_size: 16384)

  """
  @spec parse_stream(term(), provider(), keyword()) :: Enumerable.t()
  def parse_stream(stream, provider, opts \\ []) do
    handler = get_handler(provider)

    stream
    |> parse_sse_stream(opts)
    |> Stream.flat_map(&handler.handle_event(&1, opts))
  rescue
    error ->
      Logger.error("Stream parsing failed for #{provider}: #{inspect(error)}")

      [
        %{
          type: :error,
          error: "Stream parsing failed: #{inspect(error)}",
          content: nil,
          function_call: nil,
          usage: nil,
          metadata: %{}
        }
      ]
  end

  @doc """
  Parse raw Server-Sent Events (SSE) from a stream.

  Handles the low-level SSE parsing that's common across providers,
  extracting event types and data payloads.

  ## Parameters

    * `stream` - Raw stream to parse
    * `opts` - Parsing options

  ## Returns

    * Stream of parsed SSE events as maps with :event_type and :data keys

  """
  @spec parse_sse_stream(term(), keyword()) :: Enumerable.t()
  def parse_sse_stream(stream, opts \\ []) do
    buffer_size = Keyword.get(opts, :buffer_size, 8192)

    Stream.resource(
      fn ->
        {stream, "", %{}}
      end,
      fn {stream, buffer, state} ->
        case read_stream_chunk(stream, buffer_size) do
          {:ok, chunk} ->
            new_buffer = buffer <> chunk
            {events, remaining_buffer} = parse_sse_buffer(new_buffer)
            {events, {stream, remaining_buffer, state}}

          {:done} ->
            {events, _} = parse_sse_buffer(buffer)
            {events ++ [%{event_type: "done", data: "[DONE]"}], nil}

          {:error, reason} ->
            Logger.error("Stream read error: #{inspect(reason)}")
            {[%{event_type: "error", data: "Stream error: #{inspect(reason)}"}], nil}
        end
      end,
      fn state ->
        # Cleanup function
        if state, do: cleanup_stream(state)
      end
    )
  end

  # Private helper functions

  # Get the appropriate handler module for the provider
  defp get_handler(:openai), do: TheMaestro.Streaming.OpenAIHandler
  defp get_handler(:anthropic), do: TheMaestro.Streaming.AnthropicHandler
  defp get_handler(:gemini), do: TheMaestro.Streaming.GeminiHandler

  defp get_handler(provider) do
    raise ArgumentError, "Unsupported provider: #{inspect(provider)}"
  end

  # Parse SSE buffer into events
  defp parse_sse_buffer(buffer) do
    # Split on double newlines to separate events
    parts = String.split(buffer, "\n\n")
    {complete_events, remaining} = Enum.split(parts, length(parts) - 1)

    events =
      complete_events
      |> Enum.map(&parse_sse_event/1)
      |> Enum.filter(&(&1 != nil))

    remaining_buffer = List.first(remaining) || ""
    {events, remaining_buffer}
  end

  # Parse a single SSE event
  defp parse_sse_event(event_text) do
    lines = String.split(event_text, "\n")

    event = %{event_type: "message", data: ""}

    Enum.reduce(lines, event, fn line, acc ->
      cond do
        String.starts_with?(line, "event: ") ->
          %{acc | event_type: String.trim_leading(line, "event: ")}

        String.starts_with?(line, "data: ") ->
          data = String.trim_leading(line, "data: ")
          existing_data = Map.get(acc, :data, "")
          new_data = (existing_data == "" && data) || existing_data <> "\n" <> data
          %{acc | data: new_data}

        String.trim(line) == "" ->
          acc

        true ->
          # Ignore other fields like id:, retry:, etc.
          acc
      end
    end)
  end

  # Read a chunk from the stream (implementation depends on stream type)
  @spec read_stream_chunk(term(), non_neg_integer()) ::
          {:ok, binary()} | {:done} | {:error, term()}
  defp read_stream_chunk(stream, _buffer_size) do
    cond do
      is_binary(stream) -> {:ok, stream}
      match?({:chunk, _}, stream) -> {:ok, elem(stream, 1)}
      match?({:error, _}, stream) -> stream
      true -> {:error, :unsupported_stream}
    end
  end

  # Cleanup stream resources
  defp cleanup_stream(_state) do
    # Cleanup any stream resources if needed
    :ok
  end
end
