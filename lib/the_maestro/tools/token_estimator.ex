defmodule TheMaestro.Tools.TokenEstimator do
  @moduledoc """
  Simple token estimator and clamp for tool outputs.

  We approximate tokens by characters / 4 and clamp by desired token cap.
  """

  @spec clamp_to_tokens(String.t(), non_neg_integer()) :: String.t()
  def clamp_to_tokens(text, cap) when is_binary(text) and is_integer(cap) and cap > 0 do
    # Approximation: 1 token ~ 4 chars
    max_chars = cap * 4
    if String.length(text) <= max_chars, do: text, else: String.slice(text, 0, max_chars)
  end

  def clamp_to_tokens(_text, _cap), do: ""
end
