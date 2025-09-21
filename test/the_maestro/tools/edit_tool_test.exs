defmodule TheMaestro.Tools.EditToolTest do
  use TheMaestro.DataCase, async: true
  alias TheMaestro.Tools.Runtime

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "edit_tool_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    {:ok, %{root: root}}
  end

  test "single edit updates file and logs", %{root: root} do
    path = Path.join(root, "a.txt")
    File.write!(path, "alpha\nbeta\n\n")
    session = Ecto.UUID.generate()

    args =
      Jason.encode!(%{"file_path" => path, "old_string" => "beta\n", "new_string" => "BETA\n"})

    assert {:ok, _} = Runtime.exec(session, "edit", args, root)
    assert File.read!(path) =~ "BETA\n"

    logs =
      TheMaestro.Repo.all(
        from l in TheMaestro.Conversations.ToolChangeLog, where: l.session_id == ^session
      )

    assert length(logs) >= 1
  end

  test "multi_edit applies multiple replacements", %{root: root} do
    path = Path.join(root, "b.txt")
    File.write!(path, "one\ntwo\nthree\n\n")
    session = Ecto.UUID.generate()

    args =
      Jason.encode!(%{
        "file_path" => path,
        "edits" => [
          %{"old_string" => "one\n", "new_string" => "ONE\n"},
          %{"old_string" => "three\n", "new_string" => "THREE\n"}
        ]
      })

    assert {:ok, _} = Runtime.exec(session, "multi_edit", args, root)
    txt = File.read!(path)
    assert String.contains?(txt, "ONE\n")
    assert String.contains?(txt, "THREE\n")
  end
end
