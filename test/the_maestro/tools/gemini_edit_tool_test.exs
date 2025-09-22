defmodule TheMaestro.Tools.GeminiEditToolTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Tools.GeminiEdit

  setup do
    base = Path.join(File.cwd!(), "tmp/gemini_edit_test")
    File.rm_rf!(base)
    File.mkdir_p!(base)
    {:ok, base: base}
  end

  test "create new file when old_string empty and file missing", %{base: base} do
    rel = "a.txt"
    abs = Path.join(base, rel)
    args = %{"file_path" => abs, "old_string" => "", "new_string" => "hi"}
    assert {:ok, _payload, %{new: "hi"}} = GeminiEdit.run(args, base_cwd: base)
    assert File.read!(abs) == "hi"
  end

  test "error when old_string empty and file exists", %{base: base} do
    abs = Path.join(base, "b.txt")
    File.write!(abs, "x")
    args = %{"file_path" => abs, "old_string" => "", "new_string" => "hi"}
    assert {:error, msg} = GeminiEdit.run(args, base_cwd: base)
    assert String.downcase(msg) =~ "attempted to create a file that already exists"
  end

  test "expected_replacements enforced", %{base: base} do
    abs = Path.join(base, "c.txt")
    File.write!(abs, "a\na\n")
    # Mismatch
    args = %{
      "file_path" => abs,
      "old_string" => "a",
      "new_string" => "b",
      "expected_replacements" => 1
    }

    assert {:error, msg} = GeminiEdit.run(args, base_cwd: base)
    assert msg =~ "expected 1 occurrence but found 2" |> String.downcase()

    # Match all
    args2 = %{args | "expected_replacements" => 2}
    assert {:ok, _payload, %{new: newc}} = GeminiEdit.run(args2, base_cwd: base)
    assert newc == "b\nb\n"
  end
end
