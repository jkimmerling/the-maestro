defmodule TheMaestro.Providers.Http.StreamingAdapter do
  @moduledoc """
  Req streaming adapter helpers.

  Converts Req streaming responses to SSE-like event maps for consumption by
  `TheMaestro.Streaming` and provider handlers.
  """

  @typedoc "Parsed SSE-like event"
  @type sse_event :: %{event_type: String.t(), data: String.t()}

  @spec stream_request(Req.Request.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_request(_req, _opts \\ []) do
    # Placeholder: the actual integration with Req.stream!/3 should be wired
    # when real HTTP endpoints are connected.
    {:error, :not_implemented}
  end

  @spec parse_sse_events(Enumerable.t()) :: Enumerable.t()
  def parse_sse_events(enum) do
    enum
    |> Stream.map(&to_string/1)
    |> Stream.flat_map(&chunk_to_events/1)
  end

  @spec handle_streaming_interruption(term()) :: :retry | :abort | {:error, term()}
  def handle_streaming_interruption(_reason), do: :retry

  defp chunk_to_events(chunk) when is_binary(chunk) do
    # Split on double newlines for individual events
    chunk
    |> String.split("\n\n", trim: true)
    |> Enum.map(&parse_event/1)
    |> Enum.filter(& &1)
  end

  defp parse_event(text) do
    lines = String.split(text, "\n", trim: true)

    {event, data} =
      Enum.reduce(lines, {"message", ""}, fn line, {ev, acc} ->
        cond do
          String.starts_with?(line, "event: ") -> {String.trim_leading(line, "event: "), acc}
          String.starts_with?(line, "data: ") -> {ev, append_data(acc, String.trim_leading(line, "data: "))}
          true -> {ev, acc}
        end
      end)

    %{event_type: event, data: data}
  end

  defp append_data("", d), do: d
  defp append_data(acc, d), do: acc <> "\n" <> d
end
