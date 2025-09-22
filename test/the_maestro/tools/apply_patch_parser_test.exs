defmodule TheMaestro.Tools.ApplyPatch.ParserTest do
  use ExUnit.Case, async: true
  alias TheMaestro.Tools.ApplyPatch.Parser

  test "parses add/delete/update envelope" do
    patch = """
    *** Begin Patch
    *** Add File: a.txt
    +hello
    *** Update File: b.txt
    @@
     world
    -old
    +new
    *** Delete File: c.txt
    *** End Patch
    """

    assert {:ok, %{hunks: hunks}} = Parser.parse(patch)
    assert {:add, "a.txt", _} = Enum.at(hunks, 0)
    assert {:update, "b.txt", nil, chunks} = Enum.at(hunks, 1)
    assert is_list(chunks) and chunks != []
    assert {:delete, "c.txt"} = Enum.at(hunks, 2)
  end

  test "lenient heredoc wrapper" do
    inner = "*** Begin Patch\n*** Add File: a\n+z\n*** End Patch\n"
    patch = "<<'EOF'\n" <> inner <> "EOF\n"
    assert {:ok, %{hunks: [{:add, "a", _}]}} = Parser.parse(patch)
  end
end
