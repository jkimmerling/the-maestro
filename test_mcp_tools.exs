alias TheMaestro.MCP
alias TheMaestro.MCP.Client

server = MCP.get_server!("feebab31-1314-4327-af94-9b4ab224cd82")

# Start the client manually
case TheMaestro.MCP.Client.start_server_client(server) do
  {:ok, sup, client} ->
    IO.puts("Client started successfully")

    # Try to list tools directly
    case Hermes.Client.Base.list_tools(client) do
      {:ok, resp} ->
        IO.inspect(resp, label: "Raw tools response")
        unwrapped = Hermes.MCP.Response.unwrap(resp)
        IO.inspect(unwrapped, label: "Unwrapped response")

      error ->
        IO.inspect(error, label: "Error listing tools")
    end

    # Stop the supervisor
    Supervisor.stop(sup)

  error ->
    IO.inspect(error, label: "Failed to start client")
end
