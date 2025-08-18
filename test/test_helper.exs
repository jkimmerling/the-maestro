ExUnit.start()

# Only configure Ecto if the repo is available
if Code.ensure_loaded?(TheMaestro.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(TheMaestro.Repo, :manual)
end
