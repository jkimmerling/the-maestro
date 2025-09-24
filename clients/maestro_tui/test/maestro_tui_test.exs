defmodule MaestroTuiTest do
  use ExUnit.Case
  doctest MaestroTui

  test "greets the world" do
    assert MaestroTui.hello() == :world
  end
end
