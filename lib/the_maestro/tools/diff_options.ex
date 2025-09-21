defmodule TheMaestro.Tools.DiffOptions do
  @moduledoc """
  Summarizes diff operations for confirmation prompts and logging.
  """

  @type hunk_stat :: %{additions: non_neg_integer(), deletions: non_neg_integer()}
  @type summary :: %{
          additions: non_neg_integer(),
          deletions: non_neg_integer(),
          hunks: [hunk_stat()]
        }

  @doc """
  Summarize a list of hunk lines where each line starts with one of
  " ", "+", "-".
  """
  @spec summarize_hunks([[String.t()]]) :: summary()
  def summarize_hunks(hunks) when is_list(hunks) do
    {h_stats, total_add, total_del} =
      Enum.reduce(hunks, {[], 0, 0}, fn h, {acc, a, d} ->
        {ha, hd} = count_hunk(h)
        {[%{additions: ha, deletions: hd} | acc], a + ha, d + hd}
      end)

    %{
      additions: total_add,
      deletions: total_del,
      hunks: Enum.reverse(h_stats)
    }
  end

  defp count_hunk(hunk_lines) do
    Enum.reduce(hunk_lines, {0, 0}, fn line, {a, d} ->
      cond do
        String.starts_with?(line, "+") -> {a + 1, d}
        String.starts_with?(line, "-") -> {a, d + 1}
        true -> {a, d}
      end
    end)
  end
end
