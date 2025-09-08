defmodule TheMaestro.DebugLog do
  @moduledoc """
  Lightweight HTTP/debug logger with levels and optional file sink.

  Controls (env):
  - HTTP_DEBUG: "1"/"true" to enable (default: disabled)
  - HTTP_DEBUG_LEVEL: "low" | "medium" | "high" | "everything" (default: "high")
  - HTTP_DEBUG_FILE: absolute path to append logs (default: no file sink)
  - HTTP_DEBUG_SSE_PRETTY: "1"/"true" to pretty-print SSE events (default: disabled)
  """

  @levels %{
    "low" => 1,
    "medium" => 2,
    "high" => 3,
    "everything" => 4
  }

  def enabled? do
    System.get_env("HTTP_DEBUG") in ["1", "true", "TRUE"]
  end

  def level do
    case System.get_env("HTTP_DEBUG_LEVEL") do
      nil ->
        "high"

      l ->
        name = String.downcase(l)
        if Map.has_key?(@levels, name), do: name, else: "high"
    end
  end

  def level_at_least?(name) do
    current = Map.get(@levels, level(), 3)
    target = Map.get(@levels, to_string(name), 3)
    current >= target
  end

  def file_path do
    System.get_env("HTTP_DEBUG_FILE")
  end

  def puts(line) when is_binary(line) do
    IO.puts(line)
    maybe_write_file(line <> "\n")
  end

  def print_kv(label, map) when is_map(map) do
    json = Jason.encode!(map)
    puts("#{label}: #{json}")
  end

  def dump(label, data) do
    puts("#{label}: \n" <> data)
  end

  def sse_pretty? do
    System.get_env("HTTP_DEBUG_SSE_PRETTY") in ["1", "true", "TRUE"]
  end

  def sse_dump(label, chunk) when is_binary(chunk) do
    # Always emit the raw chunk first to guarantee fidelity
    dump(label, chunk)

    if sse_pretty?(), do: pretty_print_sse(chunk)
  end

  defp print_sse_block(%{event: nil, data: []}), do: :ok

  defp print_sse_block(%{event: ev, data: data_lines}) do
    joined = Enum.join(data_lines, "\n")

    pretty =
      case try_decode_json(joined) do
        {:ok, json} -> Jason.encode!(json, pretty: true)
        _ -> joined
      end

    puts("\n[SSE EVENT]")
    if ev, do: puts("event: #{ev}")
    puts("data: #{pretty}")
  end

  defp try_decode_json(str) do
    trimmed = String.trim(str)
    if String.starts_with?(trimmed, ["{", "["]) do
      Jason.decode(str)
    else
      {:error, :not_json}
    end
  end

  defp pretty_print_sse(chunk) do
    lines = String.split(chunk, "\n")

    acc = Enum.reduce(lines, %{event: nil, data: []}, &accumulate_sse_line/2)
    print_sse_block(acc)
  end

  defp accumulate_sse_line(line, acc) do
    cond do
      String.starts_with?(line, "event:") ->
        ev = String.trim_leading(line, "event:") |> String.trim()
        flush_if_needed(acc)
        %{event: ev, data: []}

      String.starts_with?(line, "data:") ->
        d = String.trim_leading(line, "data:") |> String.trim_leading()
        %{acc | data: acc.data ++ [d]}

      line == "" ->
        flush_if_needed(acc)
        %{event: nil, data: []}

      true ->
        %{acc | data: acc.data ++ [line]}
    end
  end

  defp flush_if_needed(%{event: nil, data: []}), do: :ok
  defp flush_if_needed(acc), do: print_sse_block(acc)

  def sanitize_headers(headers) when is_list(headers) do
    headers
    |> Enum.map(fn {k, v} ->
      key = (is_binary(k) && String.downcase(k)) || to_string(k) |> String.downcase()
      value = normalize_header_value(v)

      redacted =
        if key in ["authorization", "cookie", "x-goog-api-key", "x-api-key"] do
          "<redacted>"
        else
          value
        end

      {to_string(k), redacted}
    end)
  end

  def sanitize_headers(%{} = headers_map) do
    headers_map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> sanitize_headers()
  end

  defp normalize_header_value(v) when is_list(v) do
    v
    |> Enum.map(&normalize_header_value/1)
    |> Enum.join(", ")
  end

  defp normalize_header_value(v) when is_binary(v), do: v
  defp normalize_header_value(v), do: to_string(v)

  defp maybe_write_file(data) do
    case file_path() do
      nil -> :ok
      path when is_binary(path) -> File.write(path, data, [:append])
    end
  end
end
