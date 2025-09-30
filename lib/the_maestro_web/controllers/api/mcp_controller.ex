defmodule TheMaestroWeb.Api.MCPController do
  use TheMaestroWeb, :controller
  alias TheMaestro.MCP

  def options(conn, _params) do
    opts = MCP.server_options(include_disabled?: true)

    json(conn, %{
      servers:
        Enum.map(opts, fn {label, id} ->
          %{id: id, label: label}
        end)
    })
  end
end
