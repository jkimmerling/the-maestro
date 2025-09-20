ExUnit.start()

# Start Redis mock for tests before application starts
{:ok, _redis_mock} = TheMaestro.RedisMock.start_link()

# Ensure application is started for tests
{:ok, _} = Application.ensure_all_started(:the_maestro)

# Default to sandboxed tests that rollback all DB writes.
if System.get_env("USE_REAL_DB") != "1" do
  Ecto.Adapters.SQL.Sandbox.mode(TheMaestro.Repo, :manual)
end

# Configure Req request injection function for tests as needed per test case
# Tests can set `Application.put_env(:the_maestro, :req_request_fun, fun)`
