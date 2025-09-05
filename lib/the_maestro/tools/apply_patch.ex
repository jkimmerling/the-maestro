defmodule TheMaestro.Tools.ApplyPatch do
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  # credo:disable-for-this-file Credo.Check.Refactor.NegatedConditions
  @moduledoc """
  Minimal apply_patch engine compatible with Codex' patch envelope for common cases.

  Supported operations per file section:
  - *** Add File: <path>         (lines prefixed with '+')
  - *** Delete File: <path>
  - *** Update File: <path>      (optional '*** Move to: <new>')
    - Hunks with lines starting with ' ', '+', '-' are partially supported:
      We apply changes sequentially assuming hunks are contiguous and context
      lines match exactly. If context mismatches, we abort with an error.

  This is intentionally conservative; it fails fast on ambiguity.
  """

  alias TheMaestro.Tools.ExecOutput

  @type result :: {:ok, String.t()} | {:error, String.t()}

  @spec run(String.t(), keyword()) :: result
  def run(patch, opts \\ [])

  def run(patch, opts) when is_binary(patch) do
    base = Keyword.get(opts, :base_cwd, File.cwd!()) |> Path.expand()

    with :ok <- require_envelope(patch),
         {:ok, ops} <- parse_sections(patch),
         {:ok, changes} <- apply_sections(ops, base) do
      summary = "applied #{length(changes)} change(s)"
      {:ok, ExecOutput.format(summary, 0, 0.0)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def run(_other, _opts), do: {:error, "invalid patch input"}

  defp require_envelope(patch) do
    cond do
      not String.contains?(patch, "*** Begin Patch") -> {:error, "missing begin envelope"}
      not String.contains?(patch, "*** End Patch") -> {:error, "missing end envelope"}
      true -> :ok
    end
  end

  defp parse_sections(patch) do
    lines = String.split(patch, "\n", trim: false)
    {_before, rest} = split_until(lines, fn l -> String.starts_with?(l, "*** Begin Patch") end)

    if rest == [] do
      {:error, "invalid envelope"}
    else
      # rest is guaranteed non-empty here due to the earlier check
      [_ | after_begin] = rest

      {body, _tail} =
        split_until(after_begin, fn l -> String.starts_with?(l, "*** End Patch") end)

      parse_file_sections(body)
    end
  end

  defp parse_file_sections(lines), do: do_parse_file_sections(lines, [])

  defp do_parse_file_sections([], acc), do: {:ok, Enum.reverse(acc)}

  defp do_parse_file_sections([line | rest], acc) do
    cond do
      String.starts_with?(line, "*** Add File: ") ->
        path = String.trim_leading(line, "*** Add File: ")
        {content_lines, rest2} = take_until_header(rest)

        content =
          content_lines
          |> Enum.filter(&String.starts_with?(&1, "+"))
          |> Enum.map(&String.trim_leading(&1, "+"))
          |> Enum.join("\n")

        do_parse_file_sections(rest2, [{:add, path, content} | acc])

      String.starts_with?(line, "*** Delete File: ") ->
        path = String.trim_leading(line, "*** Delete File: ")
        do_parse_file_sections(rest, [{:delete, path} | acc])

      String.starts_with?(line, "*** Update File: ") ->
        original = String.trim_leading(line, "*** Update File: ")
        {section_lines, rest2} = take_until_header(rest)
        {move_to, hunks} = parse_update_section(section_lines)
        do_parse_file_sections(rest2, [{:update, original, move_to, hunks} | acc])

      String.trim(line) == "" ->
        do_parse_file_sections(rest, acc)

      true ->
        # Unknown line between sections; skip
        do_parse_file_sections(rest, acc)
    end
  end

  defp take_until_header(lines) do
    Enum.split_while(lines, fn l ->
      not String.starts_with?(l, "*** Add File:") and
        not String.starts_with?(l, "*** Delete File:") and
        not String.starts_with?(l, "*** Update File:") and
        not String.starts_with?(l, "*** End Patch")
    end)
  end

  defp parse_update_section(lines) do
    {move_to, rest} =
      case lines do
        [mt | tail] ->
          if String.starts_with?(mt, "*** Move to: ") do
            {String.trim_leading(mt, "*** Move to: "), tail}
          else
            {nil, lines}
          end

        _ ->
          {nil, lines}
      end

    hunks =
      rest
      |> Enum.drop_while(&(&1 == ""))
      |> split_on(fn l -> String.starts_with?(l, "@@") end)
      |> Enum.map(fn {_header, hunk_lines} ->
        Enum.take_while(hunk_lines, fn l ->
          not String.starts_with?(l, "@@") and not String.starts_with?(l, "*** ")
        end)
      end)
      |> Enum.reject(&(&1 == []))

    {move_to, hunks}
  end

  defp apply_sections(ops, base) do
    results =
      Enum.map(ops, fn
        {:add, path, content} ->
          abs = safe_join(base, path)
          :ok = File.mkdir_p!(Path.dirname(abs))
          :ok = File.write!(abs, content <> "\n")
          {:ok, {:add, path}}

        {:delete, path} ->
          abs = safe_join(base, path)
          _ = if File.exists?(abs), do: File.rm!(abs)
          {:ok, {:delete, path}}

        {:update, original, move_to, hunks} ->
          src = safe_join(base, original)
          dst = if move_to, do: safe_join(base, move_to), else: src

          if move_to && src != dst do
            :ok = File.mkdir_p!(Path.dirname(dst))
            if File.exists?(src), do: File.rename!(src, dst)
          end

          if hunks == [] do
            {:ok, {:rename, original, move_to || original}}
          else
            case apply_hunks_to_file(dst, hunks) do
              :ok -> {:ok, {:update, dst}}
              {:error, r} -> {:error, r}
            end
          end
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      {:error, reason} -> {:error, reason}
      _ -> {:ok, Enum.map(results, fn {:ok, x} -> x end)}
    end
  end

  defp safe_join(base, path) do
    abs = Path.expand(path, base)
    unless String.starts_with?(abs, base), do: raise("apply_patch: path escapes base")
    abs
  end

  defp apply_hunks_to_file(path, hunks) do
    original = File.read!(path)
    orig_lines = String.split(original, "\n", trim: false)

    {out_lines, idx, ok?} =
      Enum.reduce(hunks, {[], 0, true}, fn hunk, {acc, pos, ok} ->
        if not ok do
          {acc, pos, ok}
        else
          case apply_hunk(hunk, orig_lines, pos, acc) do
            {:ok, new_acc, new_pos} -> {new_acc, new_pos, true}
            {:error, _} = e -> {acc, pos, e}
          end
        end
      end)

    case ok? do
      true ->
        # Copy the remainder of the file
        remainder = Enum.drop(orig_lines, idx)
        final = out_lines ++ remainder
        File.write!(path, Enum.join(final, "\n"))
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Apply a single hunk starting at position `pos` in `orig_lines`,
  # appending to `acc`. Returns {:ok, new_acc, new_pos} or {:error, reason}.
  defp apply_hunk(hunk_lines, orig_lines, pos, acc) do
    Enum.reduce_while(hunk_lines, {acc, pos}, fn line, {a, p} ->
      cond do
        String.starts_with?(line, " ") ->
          want = String.trim_leading(line, " ")
          got = Enum.at(orig_lines, p) || ""

          if want == got do
            {:cont, {a ++ [got], p + 1}}
          else
            {:halt, {:error, "context mismatch"}}
          end

        String.starts_with?(line, "+") ->
          {:cont, {a ++ [String.trim_leading(line, "+")], p}}

        String.starts_with?(line, "-") ->
          want = String.trim_leading(line, "-")
          got = Enum.at(orig_lines, p) || ""

          if want == got do
            {:cont, {a, p + 1}}
          else
            {:halt, {:error, "delete mismatch"}}
          end

        String.starts_with?(line, "*** End of File") ->
          {:cont, {a, p}}

        true ->
          {:halt, {:error, "unsupported hunk line"}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      {a, p} -> {:ok, a, p}
    end
  end

  defp split_until(list, fun) do
    case Enum.split_while(list, fn x -> not fun.(x) end) do
      {before, []} -> {before, []}
      {before, rest} -> {before, rest}
    end
  end

  defp split_on(list, fun) do
    # Returns [{header, lines_after_header}, ...]
    idxs =
      list
      |> Enum.with_index()
      |> Enum.filter(fn {l, _i} -> fun.(l) end)
      |> Enum.map(&elem(&1, 1))

    case idxs do
      [] ->
        []

      [_ | _] ->
        ranges =
          idxs
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [a, b] -> {a, b} end)

        heads = Enum.map(idxs, &{&1, Enum.at(list, &1)})

        tails =
          case ranges do
            [] ->
              [Enum.drop(list, hd(idxs))]

            _ ->
              Enum.map(ranges, fn {a, b} -> Enum.slice(list, a, b - a) end) ++
                [Enum.drop(list, List.last(idxs))]
          end

        Enum.zip(heads, tails)
        |> Enum.map(fn {{_i, h}, t} -> {h, tl(t)} end)
    end
  end
end
