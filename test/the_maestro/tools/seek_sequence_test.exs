defmodule TheMaestro.Tools.SeekSequenceTest do
  use ExUnit.Case, async: true
  alias TheMaestro.Tools.SeekSequence

  test "finds exact" do
    lines = ["a", "b", "c"]
    assert SeekSequence.seek_sequence(lines, ["b", "c"], 0, false) == 1
  end

  test "trims whitespace" do
    lines = ["  a  ", " b\t"]
    assert SeekSequence.seek_sequence(lines, ["a", "b"], 0, false) == 0
  end

  test "normalizes punctuation" do
    lines = ["foo – bar", "baz"]
    assert SeekSequence.seek_sequence(lines, ["foo - bar"], 0, false) == 0
  end
end
