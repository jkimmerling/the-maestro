defmodule TheMaestro.ToolsTest do
  use TheMaestro.DataCase

  alias TheMaestro.Tools

  describe "tool_runs" do
    alias TheMaestro.Tools.ToolRun

    import TheMaestro.ToolsFixtures

    @invalid_attrs %{
      args: nil,
      name: nil,
      status: nil,
      stdout: nil,
      stderr: nil,
      started_at: nil,
      cwd: nil,
      exit_code: nil,
      provider: nil,
      bytes_read: nil,
      bytes_written: nil,
      finished_at: nil,
      call_request: nil,
      call_response: nil
    }

    test "list_tool_runs/0 returns all tool_runs" do
      tool_run = tool_run_fixture()
      assert Tools.list_tool_runs() == [tool_run]
    end

    test "get_tool_run!/1 returns the tool_run with given id" do
      tool_run = tool_run_fixture()
      assert Tools.get_tool_run!(tool_run.id) == tool_run
    end

    test "create_tool_run/1 with valid data creates a tool_run" do
      valid_attrs = %{
        args: %{},
        name: "some name",
        status: "some status",
        stdout: "some stdout",
        stderr: "some stderr",
        started_at: ~U[2025-09-02 13:31:00Z],
        cwd: "some cwd",
        exit_code: 42,
        provider: %{},
        bytes_read: 42,
        bytes_written: 42,
        finished_at: ~U[2025-09-02 13:31:00Z],
        call_request: %{},
        call_response: %{}
      }

      assert {:ok, %ToolRun{} = tool_run} = Tools.create_tool_run(valid_attrs)
      assert tool_run.args == %{}
      assert tool_run.name == "some name"
      assert tool_run.status == "some status"
      assert tool_run.stdout == "some stdout"
      assert tool_run.stderr == "some stderr"
      assert tool_run.started_at == ~U[2025-09-02 13:31:00Z]
      assert tool_run.cwd == "some cwd"
      assert tool_run.exit_code == 42
      assert tool_run.provider == %{}
      assert tool_run.bytes_read == 42
      assert tool_run.bytes_written == 42
      assert tool_run.finished_at == ~U[2025-09-02 13:31:00Z]
      assert tool_run.call_request == %{}
      assert tool_run.call_response == %{}
    end

    test "create_tool_run/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Tools.create_tool_run(@invalid_attrs)
    end

    test "update_tool_run/2 with valid data updates the tool_run" do
      tool_run = tool_run_fixture()
      update_attrs = %{
        args: %{},
        name: "some updated name",
        status: "some updated status",
        stdout: "some updated stdout",
        stderr: "some updated stderr",
        started_at: ~U[2025-09-03 13:31:00Z],
        cwd: "some updated cwd",
        exit_code: 43,
        provider: %{},
        bytes_read: 43,
        bytes_written: 43,
        finished_at: ~U[2025-09-03 13:31:00Z],
        call_request: %{},
        call_response: %{}
      }

      assert {:ok, %ToolRun{} = tool_run} = Tools.update_tool_run(tool_run, update_attrs)
      assert tool_run.args == %{}
      assert tool_run.name == "some updated name"
      assert tool_run.status == "some updated status"
      assert tool_run.stdout == "some updated stdout"
      assert tool_run.stderr == "some updated stderr"
      assert tool_run.started_at == ~U[2025-09-03 13:31:00Z]
      assert tool_run.cwd == "some updated cwd"
      assert tool_run.exit_code == 43
      assert tool_run.provider == %{}
      assert tool_run.bytes_read == 43
      assert tool_run.bytes_written == 43
      assert tool_run.finished_at == ~U[2025-09-03 13:31:00Z]
      assert tool_run.call_request == %{}
      assert tool_run.call_response == %{}
    end

    test "update_tool_run/2 with invalid data returns error changeset" do
      tool_run = tool_run_fixture()
      assert {:error, %Ecto.Changeset{}} = Tools.update_tool_run(tool_run, @invalid_attrs)
      assert tool_run == Tools.get_tool_run!(tool_run.id)
    end

    test "delete_tool_run/1 deletes the tool_run" do
      tool_run = tool_run_fixture()
      assert {:ok, %ToolRun{}} = Tools.delete_tool_run(tool_run)
      assert_raise Ecto.NoResultsError, fn -> Tools.get_tool_run!(tool_run.id) end
    end

    test "change_tool_run/1 returns a tool_run changeset" do
      tool_run = tool_run_fixture()
      assert %Ecto.Changeset{} = Tools.change_tool_run(tool_run)
    end
  end
end
