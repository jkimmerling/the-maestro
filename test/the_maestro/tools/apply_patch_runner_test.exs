defmodule TheMaestro.Tools.ApplyPatch.RunnerTest do
  use ExUnit.Case, async: true
  alias TheMaestro.Tools.ApplyPatch.Runner

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "apply_patch_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf(tmp) end)
    {:ok, %{root: tmp}}
  end

  test "add and update and delete", %{root: root} do
    path_b = Path.join(root, "b.txt")
    File.write!(path_b, " world\nold\n\n")

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

    assert {:ok, res} = Runner.apply(patch, base_cwd: root)
    assert res.added |> Enum.any?(fn p -> String.ends_with?(p, "/a.txt") end)
    assert res.modified |> Enum.any?(fn p -> String.ends_with?(p, "/b.txt") end)
    # delete non-existent is tolerated
    assert File.read!(Path.join(root, "a.txt")) == "hello\n"
    b = File.read!(Path.join(root, "b.txt"))
    assert String.contains?(b, "world\n")
    assert String.contains?(b, "new\n")
    refute String.contains?(b, "old\n")
  end
end
