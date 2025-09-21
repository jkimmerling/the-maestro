defmodule TheMaestro.TestStreamingAdapter do
  @moduledoc "Test streaming adapter that returns a caller-supplied SSE stream."

  @type sse_event :: %{event_type: String.t(), data: String.t()}

  @spec stream_request(Req.Request.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_request(_req, opts \\ []) do
    case Keyword.get(opts, :test_events) do
      events when is_list(events) ->
        {:ok, build_enum(events)}

      fun when is_function(fun, 0) ->
        {:ok, build_enum(fun.())}

      _ ->
        {:ok, Stream.iterate(0, & &1) |> Stream.take(0)}
    end
  end

  defp build_enum(events) do
    chunks =
      Enum.map(events, fn
        %{event_type: et, data: data} when is_binary(et) and is_binary(data) ->
          "event: #{et}\ndata: #{data}\n\n"

        bin when is_binary(bin) ->
          # Allow raw SSE blocks
          bin

        %{} = map ->
          "data: " <> Jason.encode!(map) <> "\n\n"
      end)

    Stream.concat(chunks)
  end

  @spec parse_sse_events(Enumerable.t()) :: Enumerable.t()
  def parse_sse_events(enum),
    do: TheMaestro.Providers.Http.StreamingAdapter.parse_sse_events(enum)
end
