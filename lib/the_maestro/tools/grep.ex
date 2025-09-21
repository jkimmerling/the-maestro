defmodule TheMaestro.Tools.Grep do
  @moduledoc """
  Grep files for a pattern (string or regex).
  """

  alias TheMaestro.Tools.PathResolver

  @max_hits 500

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ []) when is_map(args) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())
    pattern = Map.get(args, "pattern") || Map.get(args, :pattern)
    path_like = Map.get(args, "path") || Map.get(args, :path)

    cond do
      !is_binary(pattern) or String.trim(pattern) == "" ->
        {:error, "missing pattern"}

      true ->
        with {:ok, dir} <- PathResolver.resolve_dir(path_like, base) do
          {matcher, is_regex} =
            case Regex.compile(pattern) do
              {:ok, re} -> {re, true}
              _ -> {pattern, false}
            end

          files = collect_files(dir, base, 10_000)

          hits =
            Enum.reduce_while(files, {[], 0}, fn file, {acc, c} ->
              if c >= @max_hits,
                do: {:halt, {acc, c}},
                else:
                  {:cont,
                   {acc ++ grep_file(file, matcher, is_regex, base, @max_hits - c),
                    c + length(grep_file(file, matcher, is_regex, base, @max_hits - c))}}
            end)
            |> elem(0)

          payload =
            hits
            |> Enum.map(fn %{path: p, line: ln, text: t} -> "#{p}:#{ln}: #{t}" end)
            |> Enum.join("\n")

          {:ok, payload}
        else
          {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
          {:error, :not_found} -> {:error, "directory not found"}
          {:error, :invalid} -> {:error, "invalid directory"}
          _ -> {:error, "invalid arguments"}
        end
    end
  end

  def run(_, _), do: {:error, "invalid arguments"}

  defp collect_files(dir, base_root, max_count),
    do: do_collect_files([dir], base_root, [], 0, max_count)

  defp do_collect_files([], _b, acc, _n, _m), do: Enum.reverse(acc)

  defp do_collect_files([d | rest], base, acc, n, max) when n < max do
    if PathResolver.under_workspace?(d, base) do
      case File.ls(d) do
        {:ok, entries} ->
          {files, dirs} =
            entries |> Enum.map(&Path.join(d, &1)) |> Enum.split_with(&File.regular?/1)

          do_collect_files(rest ++ dirs, base, files ++ acc, n + length(files), max)

        _ ->
          do_collect_files(rest, base, acc, n, max)
      end
    else
      do_collect_files(rest, base, acc, n, max)
    end
  end

  defp grep_file(file, matcher, true, base_root, limit) do
    stream = File.stream!(file, :line, [])
    rel = Path.relative_to(file, base_root)

    stream
    |> Stream.with_index(1)
    |> Stream.filter(fn {line, _} -> Regex.match?(matcher, line) end)
    |> Enum.take(limit)
    |> Enum.map(fn {line, i} -> %{path: rel, line: i, text: String.trim_trailing(line)} end)
  end

  defp grep_file(file, matcher, false, base_root, limit) when is_binary(matcher) do
    stream = File.stream!(file, :line, [])
    rel = Path.relative_to(file, base_root)

    stream
    |> Stream.with_index(1)
    |> Stream.filter(fn {line, _} -> String.contains?(line, matcher) end)
    |> Enum.take(limit)
    |> Enum.map(fn {line, i} -> %{path: rel, line: i, text: String.trim_trailing(line)} end)
  end
end
