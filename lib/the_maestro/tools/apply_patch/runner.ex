defmodule TheMaestro.Tools.ApplyPatch.Runner do
  @moduledoc """
  Applies parsed `apply_patch` hunks to the filesystem safely.
  """

  alias TheMaestro.Tools.ApplyPatch.Parser
  alias TheMaestro.Tools.SeekSequence
  alias TheMaestro.Tools.UnifiedDiff

  @type result ::
          {:ok,
           %{
             added: [String.t()],
             modified: [String.t()],
             deleted: [String.t()],
             details: [map()]
           }}
          | {:error, String.t()}

  @spec apply(String.t(), keyword()) :: result
  def apply(patch_text, opts \\ []) do
    base = Keyword.get(opts, :base_cwd, File.cwd!()) |> Path.expand()
    patch_text |> Parser.parse() |> do_apply(base)
  end

  defp do_apply({:ok, %{hunks: hunks}}, base), do: apply_hunks(hunks, base)
  defp do_apply({:error, _} = e, _), do: e

  defp apply_hunks(hunks, base) do
    Enum.reduce_while(hunks, {:ok, %{added: [], modified: [], deleted: [], details: []}}, fn h,
                                                                                             {:ok,
                                                                                              acc} ->
      handle_hunk(h, acc, base)
    end)
  end

  defp handle_hunk({:add, path, contents}, acc, base) do
    abs = safe_join(base, path)
    :ok = File.mkdir_p!(Path.dirname(abs))
    :ok = File.write!(abs, contents)
    {udiff, sum} = UnifiedDiff.diff("", contents)
    det = %{file_path: abs, change_type: "add", diff: udiff, summary: sum}

    {:cont,
     {:ok, acc |> Map.update!(:added, &(&1 ++ [abs])) |> Map.update!(:details, &(&1 ++ [det]))}}
  end

  defp handle_hunk({:delete, path}, acc, base) do
    abs = safe_join(base, path)
    prev = if File.exists?(abs), do: File.read!(abs), else: ""
    if File.exists?(abs), do: File.rm!(abs)
    {udiff, sum} = UnifiedDiff.diff(prev, "")
    det = %{file_path: abs, change_type: "delete", diff: udiff, summary: sum}

    {:cont,
     {:ok, acc |> Map.update!(:deleted, &(&1 ++ [abs])) |> Map.update!(:details, &(&1 ++ [det]))}}
  end

  defp handle_hunk({:update, path, move_to, chunks}, acc, base) do
    src = safe_join(base, path)
    dst = if move_to, do: safe_join(base, move_to), else: src

    case apply_update(src, dst, chunks) do
      {:ok, prev, newc} ->
        {udiff, sum} = UnifiedDiff.diff(prev, newc)

        det = %{
          file_path: dst,
          change_type: "update",
          diff: udiff,
          summary: sum,
          move_to: if(move_to, do: dst, else: nil)
        }

        {:cont,
         {:ok,
          acc
          |> Map.update!(:modified, &(&1 ++ [dst]))
          |> Map.update!(:details, &(&1 ++ [det]))}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp safe_join(base, path) do
    abs = Path.expand(path, base)
    if String.starts_with?(abs, base), do: abs, else: raise("apply_patch: path escapes base")
  end

  defp apply_update(src, dst, chunks) do
    if move?(src, dst) do
      :ok = File.mkdir_p!(Path.dirname(dst))
      if File.exists?(src), do: File.rename!(src, dst)
    end

    with {:ok, original} <- read_or_empty(dst),
         {:ok, new_content} <- compute_new_contents(original, chunks) do
      :ok = File.write!(dst, new_content)
      {:ok, original, new_content}
    else
      {:error, r} -> {:error, r}
    end
  end

  defp move?(a, b), do: a != b

  defp read_or_empty(path) do
    case File.read(path) do
      {:ok, bin} -> {:ok, bin}
      {:error, :enoent} -> {:ok, ""}
      {:error, reason} -> {:error, :file.format_error(reason) |> List.to_string()}
    end
  end

  defp compute_new_contents(original, chunks) do
    lines = String.split(original, "\n", trim: false)
    lines = if lines == [], do: [""], else: lines

    {final_lines, status} =
      Enum.reduce_while(chunks, {lines, :ok}, fn ch, {cur, :ok} ->
        case replace_chunk(cur, ch) do
          {:ok, cur2} -> {:cont, {cur2, :ok}}
          {:error, reason} -> {:halt, {cur, {:error, reason}}}
        end
      end)

    case status do
      :ok -> {:ok, Enum.join(final_lines, "\n")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replace_chunk(lines, %{
         change_context: ctx,
         old_lines: olds,
         new_lines: news,
         is_end_of_file: eof?
       }) do
    start_pos =
      case ctx do
        nil -> 0
        ctx_line -> SeekSequence.seek_sequence(lines, [ctx_line], 0, false) || 0
      end

    pattern = olds
    news = news

    pos = SeekSequence.seek_sequence(Enum.drop(lines, start_pos), pattern, 0, eof?)

    case pos do
      nil ->
        {:error, "context mismatch"}

      idx ->
        i = start_pos + idx
        {head, rest} = Enum.split(lines, i)
        {_, tail} = Enum.split(rest, length(pattern))
        {:ok, head ++ news ++ tail}
    end
  end

  @spec format_summary(
          %{added: [String.t()], modified: [String.t()], deleted: [String.t()]},
          base :: String.t()
        ) :: String.t()
  def format_summary(%{added: a, modified: m, deleted: d}, base) do
    rel = fn p ->
      case Path.relative_to(p, base) do
        ^p -> p
        r -> r
      end
    end

    io = ["Success. Updated the following files:\n"]
    io = io ++ Enum.map(a, fn p -> "A #{rel.(p)}\n" end)
    io = io ++ Enum.map(m, fn p -> "M #{rel.(p)}\n" end)
    io = io ++ Enum.map(d, fn p -> "D #{rel.(p)}\n" end)
    IO.iodata_to_binary(io)
  end
end
