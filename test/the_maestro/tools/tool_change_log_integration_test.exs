defmodule TheMaestro.Tools.ToolChangeLogIntegrationTest do
  use TheMaestro.DataCase, async: true
  alias TheMaestro.Tools.Runtime
  alias TheMaestro.Conversations

  test "apply_patch logs unified diff per file" do
    # Create a fake session id
    session_id = Ecto.UUID.generate()

    root =
      Path.join(
        System.tmp_dir!(),
        "log_patch_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    File.write!(Path.join(root, "b.txt"), "hello\nold\n\n")

    patch = """
    *** Begin Patch
    *** Update File: b.txt
    @@
     hello
    -old
    +new
    *** End Patch
    """

    args = Jason.encode!(%{"input" => patch})
    assert {:ok, _payload} = Runtime.exec(session_id, "apply_patch", args, root)

    logs =
      TheMaestro.Repo.all(
        from l in TheMaestro.Conversations.ToolChangeLog, where: l.session_id == ^session_id
      )

    assert length(logs) == 1
    [log] = logs
    assert log.tool_name == "apply_patch"
    assert log.change_type == "update"
    assert is_binary(log.diff) and log.diff != ""
    assert is_map(log.summary) and (log.summary["additions"] || log.summary[:additions]) >= 1
  end
end
