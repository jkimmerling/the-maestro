defmodule TheMaestro.MCP.Transport do
  @moduledoc """
  Behaviour definition for MCP transport implementations.
  
  This behaviour defines the contract that all MCP transport mechanisms
  (Stdio, SSE, HTTP) must implement for consistent communication with
  MCP servers.
  """

  @type config :: map()
  @type message :: map()

  @doc """
  Start and link a transport process with the given configuration.
  
  ## Parameters
  
  * `config` - Transport-specific configuration map
  
  ## Returns
  
  * `{:ok, pid()}` - Successfully started transport process
  * `{:error, term()}` - Error starting transport
  """
  @callback start_link(config()) :: {:ok, pid()} | {:error, term()}

  @doc """
  Send a message through the transport.
  
  ## Parameters
  
  * `transport` - PID of the transport process
  * `message` - JSON-RPC message map to send
  
  ## Returns
  
  * `:ok` - Message sent successfully
  * `{:error, term()}` - Error sending message
  """
  @callback send_message(pid(), message()) :: :ok | {:error, term()}

  @doc """
  Close the transport connection and clean up resources.
  
  ## Parameters
  
  * `transport` - PID of the transport process
  
  ## Returns
  
  * `:ok` - Transport closed successfully
  """
  @callback close(pid()) :: :ok
end