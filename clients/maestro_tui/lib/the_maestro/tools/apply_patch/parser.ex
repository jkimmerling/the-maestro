defmodule TheMaestro.Tools.ApplyPatch.Parser do
  @moduledoc false

  @begin "*** Begin Patch"
  @end "*** End Patch"
  @add "*** Add File: "
  @del "*** Delete File: "
  @upd "*** Update File: "
  @move "*** Move to: "
  @eof "*** End of File"
  @ctx "@@ "
  @ctx_empty "@@"

  @type hunk :: {:add, String.t(), String.t()} | {:delete, String.t()} | {:update, String.t(), String.t() | nil, [chunk()]}
  @type chunk :: %{change_context: String.t() | nil, old_lines: [String.t()], new_lines: [String.t()], is_end_of_file: boolean()}
  @type parsed :: %{patch: String.t(), hunks: [hunk()], workdir: String.t() | nil}

  @spec parse(String.t()) :: {:ok, parsed()} | {:error, String.t()}
  def parse(patch) when is_binary(patch) do
    with {:ok, inner} <- unwrap(patch), {:ok, body} <- validate(inner), {:ok, hunks} <- parse_hunks(body, 2) do
      {:ok, %{patch: inner, hunks: hunks, workdir: nil}}
    end
  end

  defp unwrap(patch) do
    lines = String.split(patch, "\n", trim: false) |> drop_trailing()
    case lines do
      [first | rest] when first in ["<<EOF", "<<'EOF'", "<<\"EOF\""] and rest != [] and List.last(rest) == "EOF" -> {:ok, rest |> Enum.drop(-1) |> Enum.join("\n")}
      _ -> {:ok, patch}
    end
  end

  defp validate(text) do
    lines = text |> String.split("\n", trim: false) |> drop_leading() |> drop_trailing()
    first = lines |> Enum.at(0) |> to_string() |> String.trim()
    last = lines |> Enum.at(-1) |> to_string() |> String.trim()
    cond do
      first != @begin -> {:error, "invalid patch: The first line of the patch must be '#{@begin}'"}
      last != @end -> {:error, "invalid patch: The last line of the patch must be '#{@end}'"}
      true -> {:ok, Enum.slice(lines, 1, length(lines) - 2)}
    end
  end

  defp drop_leading(ls), do: Enum.drop_while(ls, fn l -> String.trim(to_string(l)) == "" end)
  defp drop_trailing(ls), do: Enum.reverse(ls) |> drop_leading() |> Enum.reverse()

  defp parse_hunks(lines, ln), do: do_parse(lines, ln, [])
  defp do_parse([], _ln, acc), do: {:ok, Enum.reverse(acc)}
  defp do_parse([line | rest], ln, acc) do
    trimmed = String.trim(line)
    cond do
      trimmed == "" -> do_parse(rest, ln + 1, acc)
      String.starts_with?(trimmed, @add) ->
        path = String.trim_leading(trimmed, @add)
        {add_lines, remaining, used} = take_prefixed(rest, ?+, [])
        contents = add_lines |> Enum.map(&String.trim_leading(&1, "+")) |> Enum.join("\n") |> Kernel.<>("\n")
        do_parse(remaining, ln + 1 + used, [{:add, path, contents} | acc])
      String.starts_with?(trimmed, @del) ->
        path = String.trim_leading(trimmed, @del)
        do_parse(rest, ln + 1, [{:delete, path} | acc])
      String.starts_with?(trimmed, @upd) ->
        path = String.trim_leading(trimmed, @upd)
        {move_to, after_move, mv_used} = extract_move(rest)
        {chunks, remaining, ch_used} = parse_update_chunks(after_move, ln + 1 + mv_used)
        case chunks do
          [] -> {:error, "invalid hunk at line #{ln}: Update file hunk for path '#{path}' is empty"}
          _ -> do_parse(remaining, ln + 1 + mv_used + ch_used, [{:update, path, move_to, chunks} | acc])
        end
      true ->
        {:error, "invalid hunk at line #{ln}, '#{trimmed}' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'"}
    end
  end

  defp extract_move([line | rest]) do
    if String.starts_with?(line, @move), do: {String.trim_leading(line, @move), rest, 1}, else: {nil, [line | rest], 0}
  end
  defp extract_move([]), do: {nil, [], 0}

  defp parse_update_chunks(lines, ln), do: collect_chunks(lines, ln, true, [], 0)
  defp collect_chunks([], _ln, _allow, acc, used), do: {Enum.reverse(acc), [], used}
  defp collect_chunks([line | rest] = all, ln, allow_missing, acc, used) do
    case classify_chunk_line(line) do
      :blank -> collect_chunks(rest, ln + 1, allow_missing, acc, used + 1)
      :header -> {Enum.reverse(acc), all, used}
      :content -> collect_chunk_content(all, ln, allow_missing, acc, used)
    end
  end

  defp classify_chunk_line(line) do
    t = String.trim(line)
    cond do
      t == "" -> :blank
      String.starts_with?(t, "***") -> :header
      true -> :content
    end
  end

  defp collect_chunk_content(lines, ln, allow_missing, acc, used) do
    case parse_one_chunk(lines, ln, allow_missing) do
      {:ok, chunk, consumed} -> collect_chunks(Enum.drop(lines, consumed), ln + consumed, false, [chunk | acc], used + consumed)
      {:error, _} -> collect_fallback_chunk(lines, ln, acc, used)
    end
  end

  defp collect_fallback_chunk(lines, ln, acc, used) do
    case parse_fallback_chunk(lines) do
      {:ok, chunk, consumed} when consumed > 0 -> collect_chunks(Enum.drop(lines, consumed), ln + consumed, false, [chunk | acc], used + consumed)
      _ -> {Enum.reverse(acc), lines, used}
    end
  end

  defp parse_one_chunk(lines, ln, allow_missing) do
    [first | _] = lines
    {ctx, start_idx} =
      cond do
        first == @ctx_empty -> {nil, 1}
        String.starts_with?(first, @ctx) -> {String.trim_leading(first, @ctx), 1}
        allow_missing -> {nil, 0}
        true -> {:error, "invalid hunk at line #{ln}, Expected update hunk to start with a @@ context marker, got: '#{first}'"}
      end

    if start_idx >= length(lines), do: {:error, "invalid hunk at line #{ln + 1}, Update hunk does not contain any lines"}, else: take_update_lines(Enum.drop(lines, start_idx), ln + start_idx, ctx)
  end

  defp take_update_lines(lines, ln, ctx) do
    {collected, consumed, eof?} = Enum.reduce_while(lines, {[], 0, false}, fn line, {acc, n, eof?} -> reduce_update_line(line, {acc, n, eof?}, ln) end)
    case consumed do
      :error -> {:error, eof?}
      _ -> build_update_result(collected, consumed, ctx, eof?)
    end
  end

  defp reduce_update_line(line, {acc, n, eof?}, ln) do
    case classify_update_line(line) do
      :eof -> {:halt, {acc, n + 1, true}}
      :header -> {:halt, {acc, n, false}}
      {:content, nil} -> {:cont, {[{:both, ""} | acc], n + 1, eof?}}
      {:content, " "} -> {:cont, {[{:both, String.trim_leading(line, " ")} | acc], n + 1, eof?}}
      {:content, "+"} -> {:cont, {[{:add, String.trim_leading(line, "+")} | acc], n + 1, eof?}}
      {:content, "-"} -> {:cont, {[{:del, String.trim_leading(line, "-")} | acc], n + 1, eof?}}
      {:content, _} when n == 0 -> {:halt, {acc, :error, "invalid hunk at line #{ln + 1}, Unexpected line found in update hunk: '#{line}'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)"}}
      {:content, _} -> {:halt, {acc, n, eof?}}
    end
  end

  defp classify_update_line(line) do
    cond do
      line == @eof -> :eof
      String.starts_with?(line, @add) or String.starts_with?(line, @del) or String.starts_with?(line, @upd) -> :header
      true -> {:content, String.first(line)}
    end
  end

  defp build_update_result(collected, consumed, ctx, eof?) do
    {old_lines, new_lines} =
      collected
      |> Enum.reverse()
      |> Enum.reduce({[], []}, fn
        {:both, s}, {o, n} -> {o ++ [s], n ++ [s]}
        {:add, s}, {o, n} -> {o, n ++ [s]}
        {:del, s}, {o, n} -> {o ++ [s], n}
      end)

    {:ok, %{change_context: (is_binary(ctx) && ctx) || nil, old_lines: old_lines, new_lines: new_lines, is_end_of_file: eof?}, consumed + if(ctx == nil, do: 0, else: 1)}
  end

  defp parse_fallback_chunk(lines) do
    {collected, used} = Enum.reduce_while(lines, {[], 0}, fn line, {acc, n} ->
      if String.starts_with?(line, @add) or String.starts_with?(line, @del) or String.starts_with?(line, @upd) do
        {:halt, {acc, n}}
      else
        case String.first(line) do
          " " -> {:cont, {[{:both, String.trim_leading(line, " ")} | acc], n + 1}}
          "+" -> {:cont, {[{:add, String.trim_leading(line, "+")} | acc], n + 1}}
          "-" -> {:cont, {[{:del, String.trim_leading(line, "-")} | acc], n + 1}}
          _ -> {:halt, {acc, n}}
        end
      end
    end)

    if used == 0 do
      {:error, :empty}
    else
      {old_lines, new_lines} =
        collected
        |> Enum.reverse()
        |> Enum.reduce({[], []}, fn
          {:both, s}, {o, n} -> {o ++ [s], n ++ [s]}
          {:add, s}, {o, n} -> {o, n ++ [s]}
          {:del, s}, {o, n} -> {o ++ [s], n}
        end)

      {:ok, %{change_context: nil, old_lines: old_lines, new_lines: new_lines, is_end_of_file: false}, used}
    end
  end

  defp take_prefixed(lines, _mark, acc) do
    case lines do
      [line | rest] -> if String.starts_with?(line, "+"), do: take_prefixed(rest, :same, [line | acc]), else: {Enum.reverse(acc), lines, length(acc)}
      _ -> {Enum.reverse(acc), lines, length(acc)}
    end
  end
end

