defmodule TheMaestro.Tools.UpdatePlanTest do
  use TheMaestro.DataCase, async: true

  alias TheMaestro.{Auth, Conversations}
  alias TheMaestro.Plans
  alias TheMaestro.Tools.UpdatePlan

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "openai-plan-test",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Plan Tool Test",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    {:ok, %{session: session}}
  end

  test "stores plan in redis and enforces single in_progress", %{session: session} do
    args = %{
      "explanation" => "initial",
      "plan" => [
        %{"step" => "Add tools", "status" => "in_progress"},
        %{"step" => "Write tests", "status" => "pending"}
      ]
    }

    assert {:ok, _} =
             UpdatePlan.run(args, session_id: session.id)

    stored = Plans.list(session.id)
    assert Enum.any?(stored, &(&1["step"] == "Add tools" or &1[:step] == "Add tools"))

    bad = put_in(args, ["plan", Access.at(1), "status"], "in_progress")

    assert {:error, "multiple in_progress steps"} =
             UpdatePlan.run(bad, session_id: session.id)
  end
end
