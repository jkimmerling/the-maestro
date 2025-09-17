#!/usr/bin/env elixir
# E2E: Create a new Gemini OAuth session + Agent in the dev DB and stream a turn.

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.{SavedAuthentication, Agents, Conversations}
alias TheMaestro.Agents.Agent
alias TheMaestro.AgentLoop

repo_started = Application.ensure_all_started(TheMaestro.Repo)

source_session = System.get_env("GEMINI_SOURCE_SESSION") || "personal_oauth_gemini"
new_session =
  System.get_env("NEW_SESSION_NAME") || ("gemini_e2e_" <> String.slice(Ecto.UUID.generate(), 0, 8))

agent_name = System.get_env("AGENT_NAME") || ("GeminiAgent_" <> String.slice(Ecto.UUID.generate(), 0, 6))
model = System.get_env("GEMINI_MODEL") || "gemini-2.5-pro"

IO.puts("Source session: #{source_session}")
IO.puts("New session:    #{new_session}")
IO.puts("Agent name:     #{agent_name}")
IO.puts("Model:          #{model}")

source = SavedAuthentication.get_by_provider_and_name(:gemini, :oauth, source_session)
if is_nil(source) do
  IO.puts("❌ Source OAuth session not found: #{source_session}")
  System.halt(2)
end

# Clean up any prior run with same new_session/agent_name
case SavedAuthentication.get_by_provider_and_name(:gemini, :oauth, new_session) do
  %SavedAuthentication{} ->
    :ok = SavedAuthentication.delete_named_session(:gemini, :oauth, new_session)
  _ -> :ok
end

# Clone the OAuth session so we truly create a NEW named session
case SavedAuthentication.clone_named_session(:gemini, :oauth, source_session, new_session) do
  {:ok, _} -> IO.puts("✅ Cloned OAuth session to '#{new_session}'")
  {:error, reason} ->
    IO.puts("❌ Failed to clone session: #{inspect(reason)}")
    System.halt(3)
end

new_auth = SavedAuthentication.get_by_provider_and_name(:gemini, :oauth, new_session)
if is_nil(new_auth) do
  IO.puts("❌ Failed to load new saved auth '#{new_session}' after clone")
  System.halt(4)
end

# Create Agent linked to the new saved auth
{:ok, %Agent{} = agent} =
  Agents.create_agent(%{
    name: agent_name,
    model_id: model,
    auth_id: new_auth.id,
    tools: %{},
    memory: %{}
  })

IO.puts("✅ Created agent '#{agent.name}' (id=#{agent.id}) linked to auth '#{new_session}'")

# Create a Session referencing the agent (for UI completeness)
{:ok, session} =
  Conversations.create_session(%{
    name: "sess_" <> String.slice(Ecto.UUID.generate(), 0, 8),
    agent_id: agent.id,
    working_dir: File.cwd!()
  })

{:ok, {_session, _entry}} = Conversations.ensure_seeded_snapshot(session)
IO.puts("✅ Created chat session #{session.id} for agent #{agent.name}")

# Now run an AgentLoop turn using the NEW session name (saved_auth name)
prompt = "Say 'gemini-ok' and nothing else."
messages = [%{"role" => "user", "content" => prompt}]

IO.puts("\n🚀 Streaming turn via AgentLoop (Gemini OAuth)…")
case AgentLoop.run_turn(:gemini, new_session, model, messages) do
  {:ok, res} ->
    IO.puts("\nFinal text:\n" <> (res.final_text || ""))
    IO.puts("Usage: " <> inspect(res.usage))
    if String.contains?(res.final_text || "", "gemini-ok") do
      IO.puts("\n✅ PASS: received expected output")
      System.halt(0)
    else
      IO.puts("\n⚠️  Output did not contain 'gemini-ok'")
      System.halt(5)
    end

  {:error, reason} ->
    IO.puts("\n❌ Streaming failed: #{inspect(reason)}")
    System.halt(6)
end
