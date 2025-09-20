defmodule Mix.Tasks.E2e.Openai.Tools do
  use Mix.Task
  @shortdoc "E2E: OpenAI tools allowlist gating"

  @moduledoc """
  Validates that the OpenAI provider respects the per-provider tools allowlist.

  Flow:
    1) Disallow all tools and assert no function calls occur
    2) Allow one tool (shell) and assert a function call occurs

  Usage:
      OPENAI_SESSION_NAME=<name> mix e2e.openai.tools
  """

  alias TheMaestro.{Chat, Conversations}

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    session_name = System.get_env("OPENAI_SESSION_NAME")

    unless is_binary(session_name) and session_name != "" do
      Mix.raise("Provide OPENAI_SESSION_NAME env var (saved auth name)")
    end

    {:ok, session_id} = ensure_session(session_name)

    Chat.subscribe(session_id)
    {:ok, cap} = Agent.start_link(fn -> nil end)
    handler = attach_openai_handler(cap)

    # 1) Disallow all
    {:ok, _} =
      Conversations.update_session(Conversations.get_session!(session_id), %{
        tools: %{"allowed" => %{"openai" => []}}
      })

    no_fc = run_turn_and_collect(session_id, "list files in the current directory using tools")

    unless no_fc.saw_fc? == false,
      do: Mix.raise("Expected no function calls when tools disallowed")

    meta0 = wait_for_meta(cap)

    unless Map.get(meta0, :tools_count) == 0,
      do: Mix.raise("Expected tools_count=0 when tools are disallowed")

    # 2) Allow shell
    {:ok, _} =
      Conversations.update_session(Conversations.get_session!(session_id), %{
        tools: %{"allowed" => %{"openai" => ["shell"]}}
      })

    yes_fc = run_turn_and_collect(session_id, "list files in the current directory using tools")
    unless yes_fc.saw_fc? == true, do: Mix.raise("Expected a function call when shell is allowed")

    meta1 = wait_for_meta(cap)

    unless Map.get(meta1, :tools_count) == 1,
      do: Mix.raise("Expected tools_count=1 when only shell is allowed")

    :telemetry.detach(handler)
    Mix.shell().info("E2E OK: OpenAI tools gating (telemetry counts + behavior) ✅")
  end

  defp ensure_session(session_name) do
    sa =
      TheMaestro.Auth.get_by_provider_and_name(:openai, :oauth, session_name) ||
        TheMaestro.Auth.get_by_provider_and_name(:openai, :api_key, session_name)

    unless sa, do: Mix.raise("No saved_authentication for openai name=#{session_name}")

    s = Conversations.latest_session_for_auth_id(sa.id)
    if is_nil(s), do: create_session_via_auth(session_name), else: {:ok, s.id}
  end

  defp create_session_via_auth(session_name) do
    sa =
      TheMaestro.Auth.get_by_provider_and_name(:openai, :oauth, session_name) ||
        TheMaestro.Auth.get_by_provider_and_name(:openai, :api_key, session_name)

    unless sa, do: Mix.raise("No saved_authentication for openai name=#{session_name}")

    {:ok, s} =
      Conversations.create_session(%{
        auth_id: sa.id,
        model_id: "gpt-5",
        working_dir: File.cwd!()
      })

    {:ok, s.id}
  end

  defp run_turn_and_collect(session_id, prompt) do
    {:ok, %{stream_id: stream_id}} = Chat.start_turn(session_id, nil, prompt)
    collect_turn_outcome(session_id, stream_id)
  end

  defp collect_turn_outcome(session_id, stream_id) do
    deadline = System.monotonic_time(:millisecond) + 60_000
    state = %{finalized?: false, saw_fc?: false}
    wait(session_id, stream_id, state, deadline)
  end

  defp wait(session_id, stream_id, state, deadline) do
    now = System.monotonic_time(:millisecond)
    if now >= deadline, do: state, else: do_wait(session_id, stream_id, state, deadline)
  end

  defp do_wait(session_id, stream_id, state, deadline) do
    receive do
      {:session_stream,
       %TheMaestro.Domain.StreamEnvelope{
         session_id: ^session_id,
         stream_id: ^stream_id,
         event: ev
       }} ->
        state2 =
          case ev do
            %{type: :function_call, tool_calls: calls} when is_list(calls) ->
              %{state | saw_fc?: state.saw_fc? or calls != []}

            %{type: :done} ->
              %{state | finalized?: true}

            _ ->
              state
          end

        if state2.finalized?, do: state2, else: wait(session_id, stream_id, state2, deadline)

      _ ->
        wait(session_id, stream_id, state, deadline)
    after
      1000 -> wait(session_id, stream_id, state, deadline)
    end
  end

  # Telemetry helpers (parity with other tasks)
  defp attach_openai_handler(agent) do
    id = "e2e-openai-tools-" <> Integer.to_string(System.unique_integer([:positive]))

    :telemetry.attach(
      id,
      [:providers, :openai, :request_built],
      fn _e, _m, meta, a -> Agent.update(a, fn _ -> meta end) end,
      agent
    )

    id
  end

  defp wait_for_meta(agent, deadline_ms \\ 10_000) do
    t0 = System.monotonic_time(:millisecond)
    do_wait_meta(agent, t0 + deadline_ms)
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
