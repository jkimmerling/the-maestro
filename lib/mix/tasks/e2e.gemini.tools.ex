defmodule Mix.Tasks.E2e.Gemini.Tools do
  use Mix.Task
  @shortdoc "E2E: Gemini tools allowlist telemetry gating"

  @moduledoc """
  Validates via telemetry that Gemini (OAuth) payload tool declarations respect the session allowlist.

  Flow:
    1) Disallow all → expect tools_count=0
    2) Allow one built-in (run_shell_command) → expect tools_count=1

  Usage:
      GEMINI_SESSION_NAME=<name> mix e2e.gemini.tools
  """

  alias TheMaestro.{Auth, Chat, Conversations}

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    session_name = System.get_env("GEMINI_SESSION_NAME")

    unless is_binary(session_name) and session_name != "" do
      Mix.raise("Provide GEMINI_SESSION_NAME env var (saved auth name)")
    end

    sa = Auth.get_by_provider_and_name(:gemini, :oauth, session_name)
    unless sa, do: Mix.raise("No saved_authentication for gemini/oauth name=#{session_name}")

    s = Conversations.latest_session_for_auth_id(sa.id)
    {:ok, session_id} = if s, do: {:ok, s.id}, else: create_session(sa)

    Chat.subscribe(session_id)
    {:ok, cap} = Agent.start_link(fn -> nil end)
    handler = attach_handler(cap)

    # none
    {:ok, _} =
      Conversations.update_session(Conversations.get_session!(session_id), %{
        tools: %{"allowed" => %{"gemini" => []}}
      })

    _ = run_turn_and_collect(session_id, "say hi")
    meta0 = wait_for_meta(cap)

    unless Map.get(meta0, :tools_count) == 0,
      do: Mix.raise("Expected tools_count=0 (Gemini disallowed)")

    # run_shell_command only
    {:ok, _} =
      Conversations.update_session(Conversations.get_session!(session_id), %{
        tools: %{"allowed" => %{"gemini" => ["run_shell_command"]}}
      })

    _ = run_turn_and_collect(session_id, "say hi")
    meta1 = wait_for_meta(cap)

    unless Map.get(meta1, :tools_count) == 1,
      do: Mix.raise("Expected tools_count=1 (Gemini run_shell_command only)")

    :telemetry.detach(handler)
    Mix.shell().info("E2E OK: Gemini tools gating via telemetry counts ✅")
  end

  defp create_session(sa) do
    {:ok, s} =
      Conversations.create_session(%{
        auth_id: sa.id,
        model_id: "gemini-2.5-pro",
        working_dir: File.cwd!()
      })

    {:ok, s.id}
  end

  defp run_turn_and_collect(session_id, prompt) do
    {:ok, %{stream_id: sid}} = Chat.start_turn(session_id, nil, prompt)
    collect(session_id, sid)
  end

  defp collect(session_id, sid) do
    deadline = System.monotonic_time(:millisecond) + 30_000
    wait(session_id, sid, deadline)
  end

  defp wait(session_id, stream_id, deadline) do
    receive do
      {:session_stream,
       %TheMaestro.Domain.StreamEnvelope{
         session_id: ^session_id,
         stream_id: ^stream_id,
         event: %{type: :done}
       }} ->
        :ok

      _ ->
        wait(session_id, stream_id, deadline)
    after
      1000 ->
        if System.monotonic_time(:millisecond) < deadline,
          do: wait(session_id, stream_id, deadline),
          else: :ok
    end
  end

  defp attach_handler(agent) do
    id = "e2e-gem-tools-" <> Integer.to_string(System.unique_integer([:positive]))

    :telemetry.attach(
      id,
      [:providers, :gemini, :request_built],
      fn _e, _m, meta, a -> Agent.update(a, fn _ -> meta end) end,
      agent
    )

    id
  end

  defp wait_for_meta(agent, limit \\ 10_000) do
    t0 = System.monotonic_time(:millisecond)
    do_wait_meta(agent, t0 + limit)
  end

  defp do_wait_meta(agent, deadline) do
    meta = Agent.get(agent, & &1)

    cond do
      is_map(meta) ->
        meta

      System.monotonic_time(:millisecond) >= deadline ->
        %{}

      true ->
        Process.sleep(100)
        do_wait_meta(agent, deadline)
    end
  end
end
