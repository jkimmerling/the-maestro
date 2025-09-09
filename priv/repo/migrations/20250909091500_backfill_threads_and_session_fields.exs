defmodule TheMaestro.Repo.Migrations.BackfillThreadsAndSessionFields do
  use Ecto.Migration

  def up do
    # Backfill a single thread_id per existing session and label from session name
    repo = repo()
    result = Ecto.Adapters.SQL.query!(repo, "SELECT id, name FROM sessions", [])

    Enum.each(result.rows, fn [session_id, name] ->
      thread_id = Ecto.UUID.generate()
      {:ok, thread_bin} = Ecto.UUID.dump(thread_id)

      label =
        name ||
          ("session-" <> Base.encode16(:crypto.hash(:sha256, session_id))) |> String.slice(0, 8)

      Ecto.Adapters.SQL.query!(
        repo,
        "UPDATE chat_history SET thread_id = $1, thread_label = $2 WHERE session_id = $3 AND thread_id IS NULL",
        [thread_bin, label, session_id]
      )
    end)

    # Mirror Agent fields onto Session for convenience going forward
    # auth_id, model_id, memory, tools, mcps straight from agents
    execute("""
    UPDATE sessions AS s
    SET auth_id = a.auth_id,
        model_id = COALESCE(a.model_id, s.model_id),
        memory = COALESCE(a.memory, s.memory),
        tools  = COALESCE(a.tools,  s.tools),
        mcps   = COALESCE(a.mcps,   s.mcps)
    FROM agents AS a
    WHERE s.agent_id = a.id
      AND (
            s.auth_id IS NULL OR s.model_id IS NULL
         OR s.memory = '{}'::jsonb OR s.tools = '{}'::jsonb OR s.mcps = '{}'::jsonb
      )
    """)

    # Build a persona jsonb using Persona or BaseSystemPrompt if present
    execute("""
    UPDATE sessions AS s
    SET persona = jsonb_build_object(
        'name', COALESCE(p.name, 'default'),
        'version', 1,
        'persona_text', COALESCE(p.prompt_text, bsp.prompt_text, '')
      )
    FROM agents AS a
    LEFT JOIN personas AS p ON a.persona_id = p.id
    LEFT JOIN base_system_prompts AS bsp ON a.base_system_prompt_id = bsp.id
    WHERE s.agent_id = a.id
      AND (s.persona IS NULL OR s.persona = '{}'::jsonb)
    """)
  end

  def down do
    # Revert backfill cautiously: clear thread_id/thread_label where they match the single-thread pattern
    execute("""
    UPDATE chat_history SET thread_id = NULL, thread_label = NULL
    WHERE parent_thread_id IS NULL AND fork_from_entry_id IS NULL
    """)

    # Do not attempt to reverse session field mirroring; leave data in place
    :ok
  end
end
