defmodule TheMaestro.Tools.Filters.EmojiFilter do
  @moduledoc """
  Optional emoji filtering for new_string inputs.

  Modes:
    - :allow  — allow all content (default)
    - :warn   — allow but return {content, warnings}
    - :error  — reject when emojis are present

  Detection uses broad unicode ranges that cover the vast majority of emoji codepoints.
  """

  @emoji_re ~r/[\x{1F300}-\x{1FAFF}\x{1F1E6}-\x{1F1FF}\x{2600}-\x{27BF}\x{FE0F}]/u

  @type mode :: :allow | :warn | :error

  @spec filter(String.t(), mode()) :: {:ok, String.t(), [String.t()]} | {:error, String.t()}
  def filter(text, mode \\ :allow) when is_binary(text) do
    has_emoji? = Regex.match?(@emoji_re, text)

    case {mode, has_emoji?} do
      {:allow, _} -> {:ok, text, []}
      {:warn, false} -> {:ok, text, []}
      {:warn, true} -> {:ok, text, ["emoji characters detected"]}
      {:error, false} -> {:ok, text, []}
      {:error, true} -> {:error, "emoji characters not allowed"}
      {_, _} -> {:ok, text, []}
    end
  end

  @spec mode_from_env() :: mode()
  def mode_from_env do
    case Application.get_env(:the_maestro, :emoji_filter_mode, :allow) do
      :warn -> :warn
      :error -> :error
      _ -> :allow
    end
  end
end
