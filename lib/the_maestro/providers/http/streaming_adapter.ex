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
        req_opts = build_req_opts(method, url, body, json, timeout)
        run_request_and_forward(req, req_opts, parent)
      end)

    %{task: task, buffer: "", done: false, timeout: timeout}
  end

  defp build_req_opts(method, url, body, json, timeout) do
    base = [method: method, url: url, into: :self, receive_timeout: timeout]
    json_opt = if json != nil, do: [json: json], else: []
    body_opt = if json == nil and body != nil, do: [body: body], else: []
    base ++ json_opt ++ body_opt
  end

  defp run_request_and_forward(req, req_opts, parent) do
    case Req.request(req, req_opts) do
      {:ok, %Req.Response{status: status} = resp} when status < 400 ->
        forward_body_chunks(resp.body, parent)
        send(parent, :done)

      {:ok, %Req.Response{status: status, body: body}} ->
        send(
          parent,
          {:data, error_event_payload(%{http_error: status, body: safe_body_text(body)})}
        )

        send(parent, :done)

      {:error, reason} ->
        send(parent, {:data, error_event_payload(%{request_error: inspect(reason)})})
        send(parent, :done)
    end
  end

  defp forward_body_chunks(enum, parent) do
    Enum.each(enum, fn chunk -> send(parent, {:data, chunk}) end)
  end

  defp error_event_payload(map) do
    "event: error\ndata: " <> Jason.encode!(map) <> "\n\n"
  end

  defp safe_body_text(body) when is_binary(body), do: body
  defp safe_body_text(body) when is_list(body), do: IO.iodata_to_binary(body)
  defp safe_body_text(body), do: inspect(body)

  defp next_events(state) do
    # Pass through raw chunks; central SSE parsing happens in TheMaestro.Streaming
    if state.done do
      {:halt, state}
    else
      receive do
        {:data, data} when is_binary(data) ->
          {[data], state}

        :done ->
          {:halt, %{state | done: true}}
      after
        state.timeout ->
          # Emit a synthetic SSE error event as raw text, then halt
          timeout_event = "event: error\ndata: stream_timeout\n\n"
          {[timeout_event], %{state | done: true}}
      end
    end
  end
end
