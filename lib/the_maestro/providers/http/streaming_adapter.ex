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
    req = maybe_debug_request(req, method, path_or_url, body, json)
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
        maybe_debug_response_headers(status, resp.headers)
        forward_body_chunks(resp.body, parent)
        send(parent, :done)

      {:ok, %Req.Response{status: status, body: body} = resp} ->
        # For non-2xx/3xx, body may still be an async stream; drain it if possible
        error_text =
          if enumerable?(body) do
            drain_async_body(body)
          else
            safe_body_text(body)
          end

        maybe_debug_error_response(status, resp.headers, error_text)

        send(
          parent,
          {:data,
           error_event_payload(%{http_error: status, body: error_text, headers: resp.headers})}
        )

        send(parent, :done)

      {:error, reason} ->
        maybe_debug_transport_error(reason)
        send(parent, {:data, error_event_payload(%{request_error: inspect(reason)})})
        send(parent, :done)
    end
  end

  defp forward_body_chunks(enum, parent) do
    Enum.each(enum, fn chunk ->
      maybe_debug_chunk(chunk)
      send(parent, {:data, chunk})
    end)
  end

  defp enumerable?(term) do
    function_exported?(Enumerable, :impl_for, 1) and not is_nil(Enumerable.impl_for(term))
  end

  defp drain_async_body(enum) do
    enum
    |> Enum.into([])
    |> IO.iodata_to_binary()
    |> safe_binary()
  end

  defp error_event_payload(map) do
    # Ensure the error payload is always JSON-encodable by sanitizing values
    safe_map = sanitize_for_json(map)
    "event: error\ndata: " <> Jason.encode!(safe_map) <> "\n\n"
  end

  defp safe_body_text(body) when is_binary(body), do: safe_binary(body)
  defp safe_body_text(body) when is_list(body), do: body |> IO.iodata_to_binary() |> safe_binary()

  defp safe_body_text(%{} = body) do
    # Best-effort JSON for maps; fallback to inspect if encoding fails
    case Jason.encode(body) do
      {:ok, json} -> json
      _ -> inspect(body)
    end
  end

  defp safe_body_text(body) do
    if function_exported?(Enumerable, :impl_for, 1) and not is_nil(Enumerable.impl_for(body)) do
      body |> Enum.into([]) |> IO.iodata_to_binary() |> safe_binary()
    else
      inspect(body)
    end
  end

  defp safe_binary(bin) when is_binary(bin) do
    cond do
      String.valid?(bin) ->
        bin

      gzipped?(bin) ->
        try do
          ungz = :zlib.gunzip(bin)
          if String.valid?(ungz), do: ungz, else: "base64:gzip:" <> Base.encode64(ungz)
        rescue
          _ -> "base64:gzip:" <> Base.encode64(bin)
        end

      true ->
        # Not UTF-8 and not gzip; return base64 so JSON encoding won't fail
        "base64:" <> Base.encode64(bin)
    end
  end

  defp gzipped?(<<0x1F, 0x8B, _rest::binary>>), do: true
  defp gzipped?(_), do: false

  defp sanitize_for_json(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {k, sanitize_value(v)} end)
    |> Enum.into(%{})
  end

  defp sanitize_value(v) when is_binary(v),
    do: if(String.valid?(v), do: v, else: "base64:" <> Base.encode64(v))

  defp sanitize_value(v) when is_list(v), do: v |> IO.iodata_to_binary() |> sanitize_value()
  defp sanitize_value(%{} = v), do: sanitize_for_json(v)
  defp sanitize_value(v), do: v

  defp next_events(state) do
    # Pass through raw chunks; central SSE parsing happens in TheMaestro.Streaming
    if state.done do
      {:halt, state}
    else
      receive do
        {:data, data} when is_binary(data) ->
          # Already logged raw chunks in forward_body_chunks
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

  # ===== Debug helpers =====
  defp maybe_debug_request(req, method, url, body, json) do
    if TheMaestro.DebugLog.enabled?() do
      lvl = TheMaestro.DebugLog.level()
      headers = TheMaestro.DebugLog.sanitize_headers(req.headers)

      TheMaestro.DebugLog.puts("\n[HTTP] #{String.upcase(to_string(method))} #{url}")

      if TheMaestro.DebugLog.level_at_least?(lvl) do
        TheMaestro.DebugLog.print_kv("Headers", Map.new(headers))
      end

      cond do
        is_map(json) -> TheMaestro.DebugLog.dump("Body", Jason.encode!(json))
        is_binary(body) -> TheMaestro.DebugLog.dump("Body", body)
        true -> :ok
      end
    end

    req
  end

  defp maybe_debug_response_headers(status, headers) do
    if TheMaestro.DebugLog.enabled?() do
      h = headers |> Enum.into(%{})
      TheMaestro.DebugLog.puts("[HTTP] Status: #{status}")
      TheMaestro.DebugLog.print_kv("RespHeaders", h)
    end
  end

  defp maybe_debug_error_response(status, headers, body) do
    if TheMaestro.DebugLog.enabled?() do
      TheMaestro.DebugLog.puts("[HTTP ERROR] Status: #{status}")
      TheMaestro.DebugLog.print_kv("RespHeaders", Enum.into(headers, %{}))
      TheMaestro.DebugLog.dump("Body", body)
    end
  end

  defp maybe_debug_transport_error(reason) do
    if TheMaestro.DebugLog.enabled?() do
      TheMaestro.DebugLog.puts("[HTTP TRANSPORT ERROR] #{inspect(reason)}")
    end
  end

  defp maybe_debug_chunk(chunk) do
    if TheMaestro.DebugLog.enabled?() and TheMaestro.DebugLog.level_at_least?("everything") do
      bin = IO.iodata_to_binary(chunk)
      # Emit raw chunk + pretty, controlled by HTTP_DEBUG_SSE_PRETTY
      TheMaestro.DebugLog.sse_dump("[SSE CHUNK]", bin)
    end
  end
end
