defmodule TheMaestro.Providers.Http.StreamingAdapter do
  @moduledoc """
  Req streaming adapter helpers.

  Uses Req's `into: :self` asynchronous streaming to consume response body
  chunks and converts them into SSE-like event maps. SSE parsing logic is
  centralized in `TheMaestro.Streaming` to avoid duplication.
  """

  alias TheMaestro.Types

  @typedoc "Parsed SSE-like event"
  @type sse_event :: %{event_type: String.t(), data: String.t()}

  @spec stream_request(Req.Request.t(), Types.request_opts()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_request(req, opts \\ []) do
    method = Keyword.get(opts, :method, :get)
    path_or_url = Keyword.get(opts, :url)
    body = Keyword.get(opts, :body)
    json = Keyword.get(opts, :json)
    timeout = Keyword.get(opts, :timeout, 60_000)

    if is_nil(path_or_url) do
      {:error, :missing_url}
    else
      do_stream_request(req, method, path_or_url, body, json, timeout)
    end
  end

  @spec parse_sse_events(Enumerable.t()) :: Enumerable.t()
  def parse_sse_events(enum) do
    # Delegate to centralized SSE parser
    TheMaestro.Streaming.parse_sse_stream(enum)
  end

  @spec handle_streaming_interruption(term()) :: :retry | :abort | {:error, term()}
  def handle_streaming_interruption(_reason), do: :retry

  # ===== Internal Req streaming integration =====
  defp do_stream_request(req, method, path_or_url, body, json, timeout) do
    # Ensure SSE-friendly headers are present
    req =
      req
      |> Req.Request.put_header("accept", "text/event-stream")
      |> Req.Request.put_header("cache-control", "no-cache")

    req =
      if json || body do
        Req.Request.put_header(req, "content-type", "application/json")
      else
        req
      end

    stream =
      Stream.resource(
        fn -> start_req_streaming(req, method, path_or_url, body, json, timeout) end,
        fn state -> next_events(state) end,
        fn _state -> :ok end
      )

    {:ok, stream}
  end

  defp start_req_streaming(req, method, url, body, json, timeout) do
    parent = self()

    {:ok, task} =
      Task.start_link(fn ->
        # Use Req's async streaming into this Task process, then forward chunks to parent
        req_opts =
          [
            method: method,
            url: url,
            into: :self,
            receive_timeout: timeout
          ] ++
            if(json != nil, do: [json: json], else: []) ++
            if json == nil and body != nil, do: [body: body], else: []

        resp = Req.request!(req, req_opts)

        # Enumerate async body in the same Task (required by Req) and forward to parent
        Enum.each(resp.body, fn chunk ->
          send(parent, {:data, chunk})
        end)

        send(parent, :done)
      end)

    %{task: task, buffer: "", done: false, timeout: timeout}
  end

  defp next_events(state) do
    # If marked done, halt the stream to avoid emitting duplicate events/timeouts
    if state.done do
      {:halt, state}
    else
      receive do
        {:data, data} when is_binary(data) ->
          buffer = state.buffer <> data
          {events, remaining} = TheMaestro.Streaming.parse_sse_buffer(buffer)
          {events, %{state | buffer: remaining}}

        :done ->
          {final_events, _} = TheMaestro.Streaming.parse_sse_buffer(state.buffer)
          # Emit any remaining events, then halt on next invocation
          {final_events, %{state | done: true}}
      after
        state.timeout ->
          # Emit a single timeout error and mark done so we terminate
          error = [%{event_type: "error", data: "stream_timeout"}]
          {error, %{state | done: true}}
      end
    end
  end
end
