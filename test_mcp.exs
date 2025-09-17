alias TheMaestro.MCP
alias TheMaestro.MCP.Client

server = MCP.get_server!("feebab31-1314-4327-af94-9b4ab224cd82")

IO.inspect(server, label: "Server")

result = Client.discover_server(server)

IO.inspect(result, label: "Test Result")
