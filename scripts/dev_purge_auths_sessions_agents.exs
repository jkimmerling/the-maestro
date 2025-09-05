Mix.Task.run("app.start")

alias TheMaestro.Repo
alias TheMaestro.SavedAuthentication
alias TheMaestro.Agents.Agent
alias TheMaestro.Conversations.Session

if Mix.env() != :dev do
  IO.puts("Refusing to purge: not in :dev environment (current: #{Mix.env()})")
  System.halt(1)
end

IO.puts("Purging Sessions -> Agents -> SavedAuthentications in dev DB…")

{:ok, _} = Repo.transaction(fn ->
  deleted_sessions = Repo.delete_all(Session)
  deleted_agents = Repo.delete_all(Agent)
  deleted_auths = Repo.delete_all(SavedAuthentication)

  IO.puts("Deleted sessions: #{elem(deleted_sessions, 0)}")
  IO.puts("Deleted agents: #{elem(deleted_agents, 0)}")
  IO.puts("Deleted auths: #{elem(deleted_auths, 0)}")
end)

IO.puts("Done.")

