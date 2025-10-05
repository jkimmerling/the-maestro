defmodule TheMaestro.Utils.ApiLogger do
  @moduledoc """
  HTTP API logger for LLM provider debugging.

  Logs full request/response details to a file in a human-readable format
  similar to the mitmproxy logger output.

  Controls (env):
  - API_DEBUG_LOG: "1"/"true" to enable (default: disabled)
  - API_DEBUG_LOG_FILE: absolute path to log file (default: "the_maestro_api_output.json")
  """

  @doc """
  Check if API logging is enabled.
  """
  def enabled? do
    System.get_env("API_DEBUG_LOG")
    |> case do
      nil ->
        false

      value ->
        value
        |> String.trim()
        |> String.downcase()
        |> then(&(&1 in ["1", "true", "yes", "on"]))
    end
  end

  @doc """
  Get the output file path for API logs.
  """
  def output_file do
    System.get_env("API_DEBUG_LOG_FILE")
    |> case do
      nil -> "the_maestro_api_output.json"
      value -> String.trim(value)
    end
  end

  @doc """
  Log a complete HTTP request.

  ## Parameters
  - provider: atom like :anthropic, :openai, :gemini
  - method: HTTP method (POST, GET, etc.)
  - url: request URL
  - headers: request headers (list of tuples or map)
  - body: request body (should be a map for JSON encoding)
  """
  def log_request(provider, method, url, headers, body) do
    if enabled?() do
      request_num = next_request_number()
      timestamp = format_timestamp()
      headers_sanitized = sanitize_headers_for_display(headers)

      lines =
        [
          "┌─ REQUEST ##{request_num} [#{timestamp}]",
          "│ #{String.upcase(to_string(method))} #{url}"
        ] ++ provider_line(provider) ++ ["│ Headers:"]

      header_lines = Enum.map(headers_sanitized, fn {k, v} -> "│   #{k}: #{v}" end)
      body_lines = render_request_body_lines(body)
      footer = ["└─", ""]

      full_output = Enum.join(lines ++ header_lines ++ body_lines ++ footer, "\n")
      write_to_file(full_output)
      request_num
    end
  end

  @doc """
  Log a complete HTTP response.

  ## Parameters
  - request_num: the request number this response corresponds to
  - status: HTTP status code
  - headers: response headers
  - sse_events: list of SSE event chunks (raw strings)
  - method: original request method for display
  - path: request path for display
  """
  def log_response(request_num, status, headers, sse_events, method, path) do
    if enabled?() do
      timestamp = format_timestamp()
      headers_sanitized = sanitize_headers_for_display(headers)

      lines = [
        "┌─ RESPONSE ##{request_num} [#{timestamp}]",
        "│ #{status} for #{String.upcase(to_string(method))} #{path}",
        "│ Headers:"
      ]

      header_lines = Enum.map(headers_sanitized, fn {k, v} -> "│   #{k}: #{v}" end)
      body_lines = render_response_body_lines(headers_sanitized, sse_events)
      footer = ["└─", ""]

      full_output = Enum.join(lines ++ header_lines ++ body_lines ++ footer, "\n")
      write_to_file(full_output)
    end
  end

  # ===== Private helpers =====

  defp next_request_number do
    case :persistent_term.get(:api_logger_request_counter, nil) do
      nil ->
        :persistent_term.put(:api_logger_request_counter, 1)
        1

      n when is_integer(n) ->
        :persistent_term.put(:api_logger_request_counter, n + 1)
        n + 1
    end
  end

  defp format_timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> Calendar.strftime("%H:%M:%S.%f")
    |> String.trim_trailing("000")
  end

  defp provider_line(provider) when is_atom(provider), do: ["│ Provider: #{provider}"]
  defp provider_line(_), do: []

  defp sanitize_headers_for_display(headers) when is_list(headers) do
    Enum.map(headers, fn {k, v} ->
      key = to_string(k)
      value = normalize_header_value(v)
      {key, value}
    end)
  end

  defp sanitize_headers_for_display(%{} = headers) do
    headers
    |> Enum.map(fn {k, v} -> {to_string(k), normalize_header_value(v)} end)
  end

  defp sanitize_headers_for_display(_), do: []

  defp render_request_body_lines(body) when is_map(body) do
    formatted_json = Jason.encode!(body, pretty: true)
    ["│ Body (JSON):"] ++ indent_lines(formatted_json, "│   ")
  end

  defp render_request_body_lines(_), do: []

  defp render_response_body_lines(_headers_sanitized, sse_events) when sse_events == [], do: []

  defp render_response_body_lines(headers_sanitized, sse_events) do
    ct = response_content_type(headers_sanitized)
    if String.contains?(ct, "text/event-stream") do
      ["│ Body (Server-Sent Events):"] ++ format_sse_events(sse_events)
    else
      combined = IO.iodata_to_binary(sse_events)
      render_body_as_json_or_text(combined)
    end
  end

  defp response_content_type(headers_sanitized) do
    headers_sanitized
    |> Enum.find_value(fn {k, v} -> String.downcase(k) == "content-type" && v end)
    |> Kernel.||("")
  end

  defp render_body_as_json_or_text(combined) do
    case Jason.decode(combined) do
      {:ok, json} ->
        formatted = Jason.encode!(json, pretty: true)
        ["│ Body (JSON):"] ++ indent_lines(formatted, "│   ")

      _ ->
        ["│ Body (#{byte_size(combined)} bytes):"] ++ indent_lines(combined, "│   ")
    end
  end

  defp indent_lines(text, prefix) do
    text
    |> String.split("\n")
    |> Enum.map(fn line -> prefix <> line end)
  end

  defp normalize_header_value(v) when is_list(v) do
    v
    |> Enum.map(&to_string/1)
    |> Enum.join(", ")
  end

  defp normalize_header_value(v) when is_binary(v), do: v
  defp normalize_header_value(v), do: to_string(v)

  defp format_sse_events(events) when is_list(events) do
    combined = IO.iodata_to_binary(events)
    event_blocks = parse_sse_blocks(combined)

    event_blocks
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {block, idx} ->
      format_sse_block(block, idx)
    end)
  end

  defp parse_sse_blocks(text) do
    text
    |> String.split("\n\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp format_sse_block(block, idx) do
    lines = String.split(block, "\n")
    event_type = extract_event_type(lines)
    data_lines = extract_data_lines(lines)

    header = ["│   Event #{idx}:"]
    event_line = if event_type, do: ["│     event: #{event_type}"] , else: []
    data_formatted = format_sse_data(data_lines)

    header ++ event_line ++ data_formatted
  end

  defp extract_event_type(lines) do
    Enum.find_value(lines, fn line ->
      if String.starts_with?(line, "event:"), do: String.trim(line |> String.trim_leading("event:"))
    end)
  end

  defp extract_data_lines(lines) do
    lines
    |> Enum.filter(&String.starts_with?(&1, "data:"))
    |> Enum.map(&String.trim(String.trim_leading(&1, "data:")))
  end

  defp format_sse_data([]), do: []

  defp format_sse_data(data_lines) do
    data_text = Enum.join(data_lines, "\n")
    case Jason.decode(data_text) do
      {:ok, json} ->
        formatted = Jason.encode!(json, pretty: true)
        ["│     data: "] ++ indent_lines(formatted, "│       ")

      _ ->
        Enum.map(data_lines, fn line -> "│     data: #{line}" end)
    end
  end

  defp write_to_file(content) do
    path = output_file()
    dir = Path.dirname(path)

    if dir not in ["", "."] do
      File.mkdir_p(dir)
    end

    case File.write(path, content, [:append]) do
      :ok -> :ok
      {:error, reason} -> IO.warn("Failed to write API log to #{path}: #{inspect(reason)}")
    end
  end
end
