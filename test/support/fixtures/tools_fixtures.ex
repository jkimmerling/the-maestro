defmodule TheMaestro.ToolsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.Tools` context.
  """

  @doc """
  Generate a tool_run.
  """
  def tool_run_fixture(attrs \\ %{}) do
    {:ok, tool_run} =
      attrs
      |> Enum.into(%{
        args: %{},
        bytes_read: 42,
        bytes_written: 42,
        call_request: %{},
        call_response: %{},
        cwd: "some cwd",
        exit_code: 42,
        finished_at: ~U[2025-09-02 13:31:00Z],
        name: "some name",
        provider: %{},
        started_at: ~U[2025-09-02 13:31:00Z],
        status: "some status",
        stderr: "some stderr",
        stdout: "some stdout"
      })
      |> TheMaestro.Tools.create_tool_run()

    tool_run
  end
end
