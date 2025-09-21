defmodule TheMaestro.Tools.UnifiedDiff do
  @moduledoc """
  Simple unified diff generator and summary for small files.
  """

  @type summary :: %{additions: non_neg_integer(), deletions: non_neg_integer()}

  @spec diff(String.t(), String.t()) :: {String.t(), summary()}
  def diff(a, b) do
    a_lines = String.split(a, "\n", trim: false)
    b_lines = String.split(b, "\n", trim: false)
    ops = lcs_ops(a_lines, b_lines)

    {add, del, body} =
      Enum.reduce(ops, {0, 0, []}, fn
        {:eq, line}, {a, d, acc} -> {a, d, [" " <> line | acc]}
        {:del, line}, {a, d, acc} -> {a, d + 1, ["-" <> line | acc]}
        {:add, line}, {a, d, acc} -> {a + 1, d, ["+" <> line | acc]}
      end)

    header = "@@ -1,#{length(a_lines)} +1,#{length(b_lines)} @@\n"
    text = header <> (body |> Enum.reverse() |> Enum.join("\n"))
    {text, %{additions: add, deletions: del}}
  end

  defp lcs_ops(a, b) do
    {m, n} = {length(a), length(b)}

    table =
      Enum.reduce(0..(m - 1), %{}, fn i, t ->
        Enum.reduce(0..(n - 1), t, fn j, t2 ->
          ai = Enum.at(a, i)
          bj = Enum.at(b, j)

          v =
            if ai == bj do
              get(t2, i, j) + 1
            else
              max(get(t2, i + 1, j), get(t2, i, j + 1))
            end

          put(t2, i + 1, j + 1, v)
        end)
      end)

    backtrack(a, b, table, m, n)
  end

  defp backtrack(a, b, table, i, j) do
    cond do
      i > 0 and j > 0 and Enum.at(a, i - 1) == Enum.at(b, j - 1) ->
        backtrack(a, b, table, i - 1, j - 1) ++ [{:eq, Enum.at(a, i - 1)}]

      j > 0 and (i == 0 or get(table, i, j - 1) >= get(table, i - 1, j)) ->
        backtrack(a, b, table, i, j - 1) ++ [{:add, Enum.at(b, j - 1)}]

      i > 0 and (j == 0 or get(table, i, j - 1) < get(table, i - 1, j)) ->
        backtrack(a, b, table, i - 1, j) ++ [{:del, Enum.at(a, i - 1)}]

      true ->
        []
    end
  end

  defp get(t, i, j), do: Map.get(t, {i, j}, 0)
  defp put(t, i, j, v), do: Map.put(t, {i, j}, v)
end
