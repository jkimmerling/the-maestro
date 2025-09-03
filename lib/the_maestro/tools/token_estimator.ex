defmodule TheMaestro.Tools.TokenEstimator do
  @moduledoc """
  Simple ensemble token estimator for truncation decisions.

  Methods:
  - chars/4 heuristic
  - words * 1.3 heuristic
  - rough BPE-ish: unique chars + words

  The estimator drops outliers and returns mean and median. Use the
  conservative value (min of mean/median) for safety by default.
  """

  @type estimate :: %{mean: non_neg_integer(), median: non_neg_integer(), samples: [non_neg_integer()]}

  @spec estimate(binary()) :: estimate()
  def estimate(text) when is_binary(text) do
    samples =
      [chars_over_four(text), words_times_factor(text), rough_bpe_proxy(text)]
      |> Enum.map(&max(&1, 0))

    cleaned = drop_outliers(samples)
    mean = if cleaned == [], do: 0, else: cleaned |> Enum.sum() |> div(length(cleaned))
    median = median(cleaned)

    %{mean: mean, median: median, samples: samples}
  end
  @doc "Return a conservative cap from the estimate (min of mean/median)."
  @spec conservative_cap(binary()) :: non_neg_integer()
  def conservative_cap(text) do
    est = estimate(text)
    min(est.mean, est.median)
  end

  @spec clamp_to_tokens(binary(), non_neg_integer()) :: binary()
  def clamp_to_tokens(text, limit) when is_binary(text) and is_integer(limit) and limit >= 0 do
    # naive proportional strategy: chars ≈ tokens * 4
    char_cap = limit * 4
    if byte_size(text) <= char_cap, do: text, else: binary_part(text, 0, char_cap)
  end

  defp chars_over_four(text), do: div(byte_size(text), 4)

  defp words_times_factor(text) do
    words = text |> String.split(~r/\s+/, trim: true) |> length()
    round(words * 1.3)
  end

  defp rough_bpe_proxy(text) do
    uniq_chars =
      text
      |> String.graphemes()
      |> MapSet.new()
      |> MapSet.size()

    words = text |> String.split(~r/\s+/, trim: true) |> length()
    uniq_chars + words
  end

  defp median([]), do: 0
  defp median(list) do
    s = Enum.sort(list)
    n = length(s)
    mid = div(n, 2)
    if rem(n, 2) == 1, do: Enum.at(s, mid), else: div(Enum.at(s, mid - 1) + Enum.at(s, mid), 2)
  end

  defp drop_outliers(list) when length(list) < 3, do: list
  defp drop_outliers(list) do
    s = Enum.sort(list)
    tl = tl(s)
    s2 = Enum.reverse(tl) |> tl() |> Enum.reverse()
    if s2 == [], do: s, else: s2
  end
end
