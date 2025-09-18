defmodule TheMaestro.Tools.WriteFileTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Tools.WriteFile

  setup do
    tmp_root =
      Path.join([System.tmp_dir!(), "maestro_write_tool_#{System.unique_integer([:positive])}"])

    File.rm_rf!(tmp_root)
    File.mkdir_p!(tmp_root)

    on_exit(fn -> File.rm_rf(tmp_root) end)

    {:ok, %{root: tmp_root}}
  end

  test "creates new file with relative path", %{root: root} do
    params = %{"path" => "poems.txt", "content" => "Roses are red"}

    assert {:ok, payload} = WriteFile.run(params, base_cwd: root)
    assert File.read!(Path.join(root, "poems.txt")) == "Roses are red"

    assert {:ok, decoded} = Jason.decode(payload)
    assert decoded["metadata"]["exit_code"] == 0
    assert decoded["output"] =~ "poems.txt"
  end

  test "errors when path escapes workspace", %{root: root} do
    outside = Path.join(Path.dirname(root), "escape.txt")
    params = %{"file_path" => outside, "content" => "oops"}

    assert {:error, reason} = WriteFile.run(params, base_cwd: root)
    assert reason == "requested path outside workspace"
  end

  test "errors when content missing", %{root: root} do
    params = %{"path" => "missing.txt"}
    assert {:error, "missing content"} = WriteFile.run(params, base_cwd: root)
  end
end
