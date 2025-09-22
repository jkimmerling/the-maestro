defmodule TheMaestro.Tools.ApplyPatch.Parser do
  @moduledoc """
  Parser for the `apply_patch` mini-language compatible with Codex.

  Produces a list of hunks which can be applied by the Runner.
  """

  @begin_marker "*** Begin Patch"
  @end_marker "*** End Patch"
  @add_marker "*** Add File: "
  @del_marker "*** Delete File: "
  @upd_marker "*** Update File: "
  @move_marker "*** Move to: "
  @eof_marker "*** End of File"
  @ctx_marker "@@ "
  @ctx_empty "@@"

  @type hunk ::
          {:add, String.t(), String.t()}
          | {:delete, String.t()}
          | {:update, String.t(), String.t() | nil, [chunk()]}

  @type chunk :: %{
          change_context: String.t() | nil,
          old_lines: [String.t()],
          new_lines: [String.t()],
          is_end_of_file: boolean()
        }

  @type parsed :: %{patch: String.t(), hunks: [hunk()], workdir: String.t() | nil}

  @spec parse(String.t()) :: {:ok, parsed()} | {:error, String.t()}
  def parse(patch) when is_binary(patch) do
    # Support lenient heredoc wrappers: <<EOF ... EOF
    with {:ok, inner} <- unwrap_if_heredoc(patch),
         {:ok, body_lines} <- validate_envelope(inner),
         {:ok, hunks} <- parse_hunks(body_lines, 2) do
      {:ok, %{patch: inner, hunks: hunks, workdir: nil}}
    end
  end

  defp unwrap_if_heredoc(patch) do
    lines0 = String.split(patch, "\n", trim: false)
    lines = drop_trailing_blanks(lines0)

    case lines do
      [first | rest] ->
        if first in ["<<EOF", "<<'EOF'", "<<\"EOF\""] and
             (rest != [] and List.last(rest) == "EOF") do
          inner = rest |> Enum.drop(-1) |> Enum.join("\n")
          {:ok, inner}
        else
          {:ok, patch}
        end

      _ ->
        {:ok, patch}
    end
  end

  defp validate_envelope(patch_text) do
    lines = String.split(patch_text, "\n", trim: false)
    lines = drop_leading_blanks(lines)
    lines = drop_trailing_blanks(lines)
    first = Enum.at(lines, 0) |> to_string() |> String.trim()
    last = Enum.at(lines, -1) |> to_string() |> String.trim()

    cond do
      first != @begin_marker ->
        {:error, "invalid patch: The first line of the patch must be '#{@begin_marker}'"}

      last != @end_marker ->
        {:error, "invalid patch: The last line of the patch must be '#{@end_marker}'"}

      true ->
        # strip markers
        {:ok, Enum.slice(lines, 1, length(lines) - 2)}
    end
  end

  defp drop_leading_blanks(lines),
    do: Enum.drop_while(lines, fn l -> String.trim(to_string(l)) == "" end)

  defp drop_trailing_blanks(lines),
    do: Enum.reverse(lines) |> drop_leading_blanks() |> Enum.reverse()

  defp parse_hunks(lines, line_no_start) do
    do_parse_hunks(lines, line_no_start, [])
  end

  defp do_parse_hunks([], _ln, acc), do: {:ok, Enum.reverse(acc)}

  defp do_parse_hunks([line | rest], ln, acc) do
    line
    |> String.trim()
    |> handle_hunk_line(line, rest, ln, acc)
  end

  defp handle_hunk_line("", _line, rest, ln, acc), do: do_parse_hunks(rest, ln + 1, acc)

  defp handle_hunk_line(trimmed, _line, rest, ln, acc) do
    cond do
      String.starts_with?(trimmed, @add_marker) ->
        path = String.trim_leading(trimmed, @add_marker)
        {add_lines, remaining, consumed} = take_prefixed(rest, ?+, [])
        joined = add_lines |> Enum.map(&String.trim_leading(&1, "+")) |> Enum.join("\n")
        contents = joined <> "\n"
        do_parse_hunks(remaining, ln + 1 + consumed, [{:add, path, contents} | acc])

      String.starts_with?(trimmed, @del_marker) ->
        path = String.trim_leading(trimmed, @del_marker)
        do_parse_hunks(rest, ln + 1, [{:delete, path} | acc])

      String.starts_with?(trimmed, @upd_marker) ->
        path = String.trim_leading(trimmed, @upd_marker)
        {move_to, after_move, move_consumed} = extract_move_target(rest)

        {chunks, remaining, chunk_consumed} =
          parse_update_chunks(after_move, ln + 1 + move_consumed)

        case chunks do
          [] ->
            {:error, "invalid hunk at line #{ln}: Update file hunk for path '#{path}' is empty"}

          _ ->
            do_parse_hunks(remaining, ln + 1 + move_consumed + chunk_consumed, [
              {:update, path, move_to, chunks} | acc
            ])
        end

      true ->
        {:error,
         "invalid hunk at line #{ln}, '#{trimmed}' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'"}
    end
  end

  defp extract_move_target([line | rest]) do
    if String.starts_with?(line, @move_marker) do
      {String.trim_leading(line, @move_marker), rest, 1}
    else
      {nil, [line | rest], 0}
    end
  end

  defp extract_move_target([]), do: {nil, [], 0}

  defp parse_update_chunks(lines, ln), do: collect_chunks(lines, ln, true, [], 0)

  defp collect_chunks([], _ln, _allow_missing, acc, consumed),
    do: {Enum.reverse(acc), [], consumed}

  defp collect_chunks([line | rest] = all, ln, allow_missing, acc, consumed) do
    case classify_chunk_line(line) do
      :blank -> collect_chunks(rest, ln + 1, allow_missing, acc, consumed + 1)
      :header -> {Enum.reverse(acc), all, consumed}
      :content -> collect_chunk_content(all, ln, allow_missing, acc, consumed)
    end
  end

  defp classify_chunk_line(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" -> :blank
      String.starts_with?(trimmed, "***") -> :header
      true -> :content
    end
  end

  defp collect_chunk_content(lines, ln, allow_missing, acc, consumed) do
    case parse_one_chunk(lines, ln, allow_missing) do
      {:ok, chunk, used} ->
        updated_lines = Enum.drop(lines, used)
        collect_chunks(updated_lines, ln + used, false, [chunk | acc], consumed + used)

      {:error, _} ->
        collect_fallback_chunk(lines, ln, acc, consumed)
    end
  end

  defp collect_fallback_chunk(lines, ln, acc, consumed) do
    case parse_fallback_chunk(lines) do
      {:ok, chunk, used} when used > 0 ->
        updated_lines = Enum.drop(lines, used)
        collect_chunks(updated_lines, ln + used, false, [chunk | acc], consumed + used)

      _ ->
        {Enum.reverse(acc), lines, consumed}
    end
  end

  defp parse_one_chunk(lines, ln, allow_missing) do
    [first | _] = lines

    {change_context, start_idx} =
      cond do
        first == @ctx_empty ->
          {nil, 1}

        String.starts_with?(first, @ctx_marker) ->
          {String.trim_leading(first, @ctx_marker), 1}

        allow_missing ->
          {nil, 0}

        true ->
          {:error,
           "invalid hunk at line #{ln}, Expected update hunk to start with a @@ context marker, got: '#{first}'"}
      end

    if start_idx >= length(lines) do
      {:error, "invalid hunk at line #{ln + 1}, Update hunk does not contain any lines"}
    else
      take_update_lines(Enum.drop(lines, start_idx), ln + start_idx, change_context)
    end
  end

  defp take_update_lines(lines, ln, change_context) do
    {collected, consumed, eof?} =
      Enum.reduce_while(lines, {[], 0, false}, fn line, {acc, n, eof?} ->
        reduce_update_line(line, {acc, n, eof?}, ln)
      end)

    case consumed do
      :error -> {:error, eof?}
      _ -> build_update_result(collected, consumed, change_context, eof?)
    end
  end

  defp reduce_update_line(line, {acc, n, eof?}, ln) do
    case classify_update_line(line) do
      :eof ->
        {:halt, {acc, n + 1, true}}

      :header ->
        {:halt, {acc, n, false}}

      {:content, nil} ->
        {:cont, {[{:both, ""} | acc], n + 1, eof?}}

      {:content, " "} ->
        {:cont, {[{:both, String.trim_leading(line, " ")} | acc], n + 1, eof?}}

      {:content, "+"} ->
        {:cont, {[{:add, String.trim_leading(line, "+")} | acc], n + 1, eof?}}

      {:content, "-"} ->
        {:cont, {[{:del, String.trim_leading(line, "-")} | acc], n + 1, eof?}}

      {:content, _other} when n == 0 ->
        {:halt,
         {acc, :error,
          "invalid hunk at line #{ln + 1}, Unexpected line found in update hunk: '#{line}'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)"}}

      {:content, _} ->
        {:halt, {acc, n, eof?}}
    end
  end

  defp classify_update_line(line) do
    cond do
      line == @eof_marker ->
        :eof

      String.starts_with?(line, @add_marker) or String.starts_with?(line, @del_marker) or
          String.starts_with?(line, @upd_marker) ->
        :header

      true ->
        {:content, String.first(line)}
    end
  end

  defp build_update_result(collected, consumed, change_context, eof?) do
    {old_lines, new_lines} =
      collected
      |> Enum.reverse()
      |> Enum.reduce({[], []}, fn
        {:both, s}, {o, n} -> {o ++ [s], n ++ [s]}
        {:add, s}, {o, n} -> {o, n ++ [s]}
        {:del, s}, {o, n} -> {o ++ [s], n}
      end)

    {:ok,
     %{
       change_context: (is_binary(change_context) && change_context) || nil,
       old_lines: old_lines,
       new_lines: new_lines,
       is_end_of_file: eof?
     }, consumed + if(change_context == nil, do: 0, else: 1)}
  end

  defp parse_fallback_chunk(lines) do
    {collected, used} = Enum.reduce_while(lines, {[], 0}, &reduce_fallback_line/2)

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

      {:ok,
       %{
         change_context: nil,
         old_lines: old_lines,
         new_lines: new_lines,
         is_end_of_file: false
       }, used}
    end
  end

  defp reduce_fallback_line(line, {acc, n}) do
    if String.starts_with?(line, @add_marker) or String.starts_with?(line, @del_marker) or
         String.starts_with?(line, @upd_marker) do
      {:halt, {acc, n}}
    else
      case String.first(line) do
        " " -> {:cont, {[{:both, String.trim_leading(line, " ")} | acc], n + 1}}
        "+" -> {:cont, {[{:add, String.trim_leading(line, "+")} | acc], n + 1}}
        "-" -> {:cont, {[{:del, String.trim_leading(line, "-")} | acc], n + 1}}
        _ -> {:halt, {acc, n}}
      end
    end
  end

  defp take_prefixed(lines, _mark, acc) do
    case lines do
      [line | rest] ->
        if String.starts_with?(line, "+") do
          take_prefixed(rest, :same, [line | acc])
        else
          {Enum.reverse(acc), lines, length(acc)}
        end

      _ ->
        {Enum.reverse(acc), lines, length(acc)}
    end
  end
end
