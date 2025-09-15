defmodule TheMaestro.MCP.HermesDynamicClient do
  @moduledoc false
  use Hermes.Client,
    name: "the-maestro-mcp-client",
    version: "0.0.1",
    protocol_version: "2025-06-18",
    capabilities: [:roots]
end

