ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TheMaestro.Repo, :manual)

# Setup Mox for HTTP mocking
Mox.defmock(HTTPoisonMock, for: HTTPoison.Base)

# Configure the mock in test environment
Application.put_env(:the_maestro, :http_client, HTTPoisonMock)
