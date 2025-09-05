ExUnit.start()

# Default to sandboxed tests that rollback all DB writes.
if System.get_env("USE_REAL_DB") != "1" do
  Ecto.Adapters.SQL.Sandbox.mode(TheMaestro.Repo, :manual)
end

# Configure Req request injection function for tests as needed per test case
# Tests can set `Application.put_env(:the_maestro, :req_request_fun, fun)`
