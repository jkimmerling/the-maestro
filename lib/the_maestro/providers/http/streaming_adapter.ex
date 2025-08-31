defmodule TheMaestro.Providers.Http.StreamingAdapter do
  @moduledoc """
  Req streaming adapter helpers.

  Converts Req streaming responses to SSE-like event maps for consumption by
  `TheMaestro.Streaming` and provider handlers.
  """

  @typedoc "Parsed SSE-like event"
  @type sse_event :: %{event_type: String.t(), data: String.t()}

  @spec stream_request(Req.Request.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
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
          String.starts_with?(line, "event: ") ->
            {String.trim_leading(line, "event: "), acc}

          String.starts_with?(line, "data: ") ->
            {ev, append_data(acc, String.trim_leading(line, "data: "))}

          true ->
            {ev, acc}
        end
      end)

    %{event_type: event, data: data}
  end

  defp append_data("", d), do: d
  defp append_data(acc, d), do: acc <> "\n" <> d

  # ===== Internal Finch streaming integration =====
  defp do_stream_request(req, method, path_or_url, body, json, timeout) do
    finch = Map.get(req.options, :finch)
    base_url = Map.get(req.options, :base_url, "")
    headers = req.headers |> headers_to_list()
    headers = put_sse_headers(headers, json || body)

    if is_atom(finch) do
      full_url =
        cond do
          is_binary(path_or_url) and String.starts_with?(path_or_url, "http") -> path_or_url
          is_binary(base_url) -> base_url <> path_or_url
        end

      payload =
        cond do
          json != nil -> Jason.encode!(json)
          is_binary(body) -> body
          true -> body
        end

      req_method = method |> to_string() |> String.upcase()
      request = Finch.build(req_method, full_url, headers, payload)

      stream =
        Stream.resource(
          fn -> start_streaming(finch, request, timeout) end,
          fn state -> next_events(state) end,
          fn _state -> :ok end
        )

      {:ok, stream}
    else
      {:error, :missing_finch_pool}
    end
  end

  defp headers_to_list(headers_map) when is_map(headers_map) do
    headers_map
    |> Enum.flat_map(fn {k, vals} -> Enum.map(List.wrap(vals), fn v -> {k, v} end) end)
  end

  defp put_sse_headers(headers, payload) do
    base =
      headers
      |> List.keydelete("accept", 0)
      |> List.keydelete("cache-control", 0)
      |> Kernel.++([
        {"accept", "text/event-stream"},
        {"cache-control", "no-cache"}
      ])

    case payload do
      nil -> base
      _ ->
        base
        |> List.keydelete("content-type", 0)
        |> Kernel.++([{"content-type", "application/json"}])
    end
  end

  defp take_complete_events(buffer) do
    parts = String.split(buffer, "\n\n")
    case parts do
      [] -> {[], ""}
      [_single] -> {[], buffer}
      _ ->
        {complete, [remaining]} = Enum.split(parts, length(parts) - 1)
        events =
          complete
          |> Enum.map(&parse_event/1)
          |> Enum.filter(& &1)

        {events, remaining}
    end
  end

  defp start_streaming(finch, request, timeout) do
    parent = self()
    {:ok, task} =
      Task.start_link(fn ->
        Finch.stream(request, finch, parent, &dispatch_stream_msg/2)
      end)

    %{task: task, buffer: "", done: false, timeout: timeout}
  end

  defp dispatch_stream_msg({:status, status}, dest) do
    send(dest, {:status, status})
    dest
  end

  defp dispatch_stream_msg({:headers, headers}, dest) do
    send(dest, {:headers, headers})
    dest
  end

  defp dispatch_stream_msg({:data, data}, dest) do
    send(dest, {:data, data})
    dest
  end

  defp dispatch_stream_msg(:done, dest) do
    send(dest, :done)
    dest
  end

  defp next_events(state) do
    receive do
      {:data, data} when is_binary(data) ->
        buffer = state.buffer <> data
        {events, remaining} = take_complete_events(buffer)
        {events, %{state | buffer: remaining}}

      {:status, _} -> {[], state}
      {:headers, _} -> {[], state}
      :done ->
        {final_events, _} = take_complete_events(state.buffer)
        {final_events, %{state | done: true}}
    after
      state.timeout ->
        error = [%{event_type: "error", data: "stream_timeout"}]
        {error, %{state | done: true}}
    end
  end
end
