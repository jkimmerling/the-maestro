ExUnit.start()

# Start PubSub for tests that need it (if not already started)
unless Process.whereis(TheMaestro.PubSub) do
  {:ok, _} = Supervisor.start_link([{Phoenix.PubSub, name: TheMaestro.PubSub}], strategy: :one_for_one)
end

# Only configure Ecto if the repo is available
if Code.ensure_loaded?(TheMaestro.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(TheMaestro.Repo, :manual)
end
