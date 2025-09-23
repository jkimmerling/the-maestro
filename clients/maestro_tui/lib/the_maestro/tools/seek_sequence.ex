defmodule TheMaestro.Tools.SeekSequence do
  @moduledoc false

  @spec seek_sequence([String.t()], [String.t()], non_neg_integer(), boolean()) :: non_neg_integer() | nil
  def seek_sequence(lines, pattern, start, eof?) do
    cond do
      pattern == [] -> start
      length(pattern) > length(lines) -> nil
      true ->
        search_start = if eof? and length(lines) >= length(pattern), do: length(lines) - length(pattern), else: start
        exact(lines, pattern, search_start) || rstrip(lines, pattern, search_start) || trim(lines, pattern, search_start) || normalized(lines, pattern, search_start)
    end
  end

  defp exact(lines, pattern, start) do
    last = length(lines) - length(pattern)
    Enum.find(0..max(last - start, 0), fn off -> Enum.slice(lines, start + off, length(pattern)) == pattern end)
    |> case do nil -> nil; off -> start + off end
  end

  defp rstrip(lines, pattern, start) do
    last = length(lines) - length(pattern)
    Enum.find(0..max(last - start, 0), fn off -> Enum.zip(Enum.slice(lines, start + off, length(pattern)), pattern) |> Enum.all?(fn {a, b} -> String.trim_trailing(a) == String.trim_trailing(b) end) end)
    |> case do nil -> nil; off -> start + off end
  end

  defp trim(lines, pattern, start) do
    last = length(lines) - length(pattern)
    Enum.find(0..max(last - start, 0), fn off -> Enum.zip(Enum.slice(lines, start + off, length(pattern)), pattern) |> Enum.all?(fn {a, b} -> String.trim(a) == String.trim(b) end) end)
    |> case do nil -> nil; off -> start + off end
  end

  defp normalized(lines, pattern, start) do
    norm = fn s ->
      s
      |> String.trim()
      |> String.graphemes()
      |> Enum.map(fn
        <<?–::utf8>> -> "-"
        <<?—::utf8>> -> "-"
        <<?−::utf8>> -> "-"
        <<?‑::utf8>> -> "-"
        <<?‘::utf8>> -> "'"
        <<?’::utf8>> -> "'"
        <<?“::utf8>> -> "\""
        <<?”::utf8>> -> "\""
        <<0xA0>> -> " "
        other -> other
      end)
      |> IO.iodata_to_binary()
    end

    last = length(lines) - length(pattern)
    Enum.find(0..max(last - start, 0), fn off -> Enum.zip(Enum.slice(lines, start + off, length(pattern)), pattern) |> Enum.all?(fn {a, b} -> norm.(a) == norm.(b) end) end)
    |> case do nil -> nil; off -> start + off end
  end
end

