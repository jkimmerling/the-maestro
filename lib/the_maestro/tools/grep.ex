defmodule TheMaestro.Tools.Grep do
  @moduledoc """
  Grep files for a pattern (string or regex).
  """

  alias TheMaestro.Tools.PathResolver

  @max_hits 500

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ [])

  def run(args, opts) when is_map(args) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())
    pattern = Map.get(args, "pattern") || Map.get(args, :pattern)
    path_like = Map.get(args, "path") || Map.get(args, :path)

    if !is_binary(pattern) or String.trim(pattern) == "" do
      {:error, "missing pattern"}
    else
      case PathResolver.resolve_dir(path_like, base) do
        {:ok, dir} -> do_grep(dir, base, pattern)
        {:error, reason} -> map_resolve_error(reason)
      end
    end
  end

  def run(_, _), do: {:error, "invalid arguments"}

  defp do_grep(dir, base, pattern) do
    matcher =
      case Regex.compile(pattern) do
        {:ok, re} -> re
        _ -> pattern
      end

    files = collect_files(dir, base, 10_000)

    hits =
      Enum.reduce_while(files, {[], 0}, fn file, {acc, c} ->
        if c >= @max_hits do
          {:halt, {acc, c}}
        else
          found = grep_file(file, matcher, base, @max_hits - c)
          {:cont, {acc ++ found, c + length(found)}}
        end
      end)
      |> elem(0)

    payload =
      hits
      |> Enum.map(fn %{path: p, line: ln, text: t} -> "#{p}:#{ln}: #{t}" end)
      |> Enum.join("\n")

    {:ok, payload}
  end

  defp map_resolve_error(:outside_workspace), do: {:error, "requested path outside workspace"}
  defp map_resolve_error(:not_found), do: {:error, "directory not found"}
  defp map_resolve_error(:invalid), do: {:error, "invalid directory"}
  defp map_resolve_error(_), do: {:error, "invalid arguments"}

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

  defp grep_file(file, %Regex{} = matcher, base_root, limit) do
    stream = File.stream!(file, :line, [])
    rel = Path.relative_to(file, base_root)

    stream
    |> Stream.with_index(1)
    |> Stream.filter(fn {line, _} -> Regex.match?(matcher, line) end)
    |> Enum.take(limit)
    |> Enum.map(fn {line, i} -> %{path: rel, line: i, text: String.trim_trailing(line)} end)
  end

  defp grep_file(file, matcher, base_root, limit) when is_binary(matcher) do
    stream = File.stream!(file, :line, [])
    rel = Path.relative_to(file, base_root)

    stream
    |> Stream.with_index(1)
    |> Stream.filter(fn {line, _} -> String.contains?(line, matcher) end)
    |> Enum.take(limit)
    |> Enum.map(fn {line, i} -> %{path: rel, line: i, text: String.trim_trailing(line)} end)
  end
end
