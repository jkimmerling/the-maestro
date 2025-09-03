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
  @spec parse_sse_stream(Enumerable.t(), keyword()) :: Enumerable.t()
  def parse_sse_stream(enum, _opts \\ []) do
    # Accept any enumerable of iodata/binaries and turn it into SSE events.
    Stream.transform(
      enum,
      fn -> "" end,
      fn chunk, buffer ->
        data = IO.iodata_to_binary(chunk)
        new_buffer = buffer <> data
        {events, remaining} = parse_sse_buffer(new_buffer)
        {events, remaining}
      end,
      fn
        buffer when is_binary(buffer) and buffer != "" ->
          {events, _} = parse_sse_buffer(buffer)
          events

        _ ->
          []
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
  @doc """
  Parse an accumulated SSE buffer into a list of events and remaining buffer.

  Splits on double newlines to yield complete SSE events and returns the
  remaining (possibly partial) buffer to be used on the next chunk.
  """
  @spec parse_sse_buffer(binary()) :: {[map()], binary()}
  def parse_sse_buffer(buffer) do
    # Split on blank-line separators, tolerate CRLF
    parts = Regex.split(~r/\r?\n\r?\n/, buffer)
    {complete_events, remaining} = Enum.split(parts, length(parts) - 1)

    events =
      complete_events
      |> Enum.map(&parse_sse_event/1)
      |> Enum.filter(&(&1 != nil))

    remaining_buffer = List.first(remaining) || ""
    {events, remaining_buffer}
  end

  # Parse a single SSE event
  @doc """
  Parse a single SSE event text block into an event map.
  Default event_type is "message" if none provided.
  """
  @spec parse_sse_event(binary()) :: %{event_type: binary(), data: binary()} | nil
  def parse_sse_event(event_text) do
    lines = Regex.split(~r/\r?\n/, event_text)

    lines
    |> Enum.reduce(%{event_type: "message", data: ""}, &accumulate_line/2)
    |> ensure_data_fallback(event_text)
  end

  defp accumulate_line(line, acc) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        acc

      String.starts_with?(trimmed, "event: ") ->
        %{acc | event_type: String.trim_leading(trimmed, "event: ")}

      String.starts_with?(trimmed, "data: ") ->
        append_data_line(acc, String.trim_leading(trimmed, "data: "))

      looks_like_json?(trimmed) ->
        append_data_line(acc, trimmed)

      true ->
        acc
    end
  end

  defp append_data_line(%{data: ""} = acc, data), do: %{acc | data: data}
  defp append_data_line(acc, data), do: %{acc | data: acc.data <> "\n" <> data}

  defp looks_like_json?(<<"{"::utf8, _::binary>>), do: true
  defp looks_like_json?(<<"["::utf8, _::binary>>), do: true
  defp looks_like_json?(_), do: false

  defp ensure_data_fallback(%{data: ""} = acc, event_text) do
    trimmed = String.trim(event_text)
    if looks_like_json?(trimmed), do: %{acc | data: trimmed}, else: acc
  end

  defp ensure_data_fallback(acc, _event_text), do: acc
end
