defmodule TheMaestroWeb.ConversationNormalizationTest do
  use TheMaestro.DataCase, async: false

  alias TheMaestro.{Chat, Conversations}
  import TheMaestro.ConversationsFixtures

  describe "no duplicate appends across turns" do
    test "single append per turn; duplicate submit ignored" do
      session = session_fixture()
      {:ok, {session, _snap}} = Conversations.ensure_seeded_snapshot(session)

      base_count = message_count(session.id)

      # Start a user turn
      {:ok, _res} =
        Chat.start_turn(session.id, nil, "hello world",
          sandbox_owner: self(),
          start_stream?: false
        )

      # Duplicate immediate submit should be rejected
      assert {:error, :duplicate_turn} =
               Chat.start_turn(session.id, nil, "hello world",
                 sandbox_owner: self(),
                 start_stream?: false
               )

      # Only one user message appended
      assert base_count + 1 == eventually(fn -> message_count(session.id) end)

      # Dry-run path stops before provider; ensure no second append occurred
      assert base_count + 1 == message_count(session.id)
    end
  end

  defp latest_messages(session_id) do
    case Conversations.latest_snapshot(session_id) do
      %{combined_chat: %{"messages" => msgs}} -> msgs
      _ -> []
    end
  end

  defp message_count(session_id), do: latest_messages(session_id) |> length()

  defp get_text(%{"content" => [%{"text" => t} | _]}), do: t
  defp get_text(_), do: ""

  # Wait/poll helper with small deadline for async finalize
  defp eventually(fun, timeout \\ 1_000, step \\ 50) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_eventually(fun, deadline, step)
  end

  defp do_eventually(fun, deadline, step) do
    val = fun.()
    now = System.monotonic_time(:millisecond)
    if now >= deadline, do: val, else: Process.sleep(step) && do_eventually(fun, deadline, step)
  end
end
