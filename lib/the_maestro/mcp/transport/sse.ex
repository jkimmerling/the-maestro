defmodule TheMaestro.MCP.Transport.SSE do
  @moduledoc """
  Server-Sent Events (SSE) transport implementation for MCP servers.

  This transport communicates with MCP servers over HTTP using Server-Sent Events
  for receiving messages and HTTP POST for sending messages.
  """

  use GenServer
  require Logger

  @behaviour TheMaestro.MCP.Transport

  @type state :: %{
          config: map(),
          stream_pid: pid() | nil,
          connection_state: :disconnected | :connecting | :connected | :error,
          base_url: String.t(),
          headers: list(),
          http_client: atom()
        }

  # Client API

  @impl TheMaestro.MCP.Transport
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, [])
  end

  @impl TheMaestro.MCP.Transport
  def send_message(transport, message) do
    GenServer.call(transport, {:send_message, message})
  end

  @impl TheMaestro.MCP.Transport
  def close(transport) do
    GenServer.call(transport, :close)
  end

  # GenServer Callbacks

  @impl GenServer
  def init(config) do
    state = %{
      config: config,
      stream_pid: nil,
      connection_state: :disconnected,
      base_url: Map.get(config, :url),
      headers: Map.get(config, :headers, []),
      http_client: Map.get(config, :http_client, Finch)
    }

    if state.base_url do
      # Start connection process
      send(self(), :connect)
      {:ok, state}
    else
      {:stop, {:error, :missing_url}}
    end
  end

  @impl GenServer
  def handle_call({:send_message, message}, _from, %{connection_state: :connected} = state) do
    case send_http_message(state, message) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.error("Failed to send SSE message: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_message, _message}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:close, _from, state) do
    new_state = disconnect(state)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info(:connect, state) do
    {:ok, stream_pid} = start_sse_stream(state)
    new_state = %{state | stream_pid: stream_pid, connection_state: :connected}
    Logger.info("SSE transport connected to #{state.base_url}")
    {:noreply, new_state}
  end

  def handle_info({:sse_message, data}, state) do
    case Jason.decode(data) do
      {:ok, message} ->
        # Forward to message router
        Logger.debug("Received SSE message: #{inspect(message)}")
        handle_received_message(message)
        {:noreply, state}

      {:error, _} ->
        Logger.warning("Received invalid JSON from SSE: #{data}")
        {:noreply, state}
    end
  end

  def handle_info({:sse_error, reason}, state) do
    Logger.error("SSE stream error: #{inspect(reason)}")
    new_state = %{state | connection_state: :error, stream_pid: nil}

    # Attempt reconnection
    Process.send_after(self(), :connect, 5_000)
    {:noreply, new_state}
  end

  def handle_info({:sse_closed}, state) do
    Logger.info("SSE stream closed")
    new_state = %{state | connection_state: :disconnected, stream_pid: nil}

    # Attempt reconnection
    Process.send_after(self(), :connect, 2_000)
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("Unexpected message in SSE transport: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    disconnect(state)
    :ok
  end

  # Private functions

  defp start_sse_stream(state) do
    # Start a process to handle SSE streaming
    parent = self()

    stream_pid =
      spawn_link(fn ->
        stream_sse(parent, state.base_url, state.headers)
      end)

    {:ok, stream_pid}
  end

  defp stream_sse(parent, url, headers) do
    request_headers = [
      {"Accept", "text/event-stream"},
      {"Cache-Control", "no-cache"}
      | headers
    ]

    try do
      # This is a simplified SSE implementation
      # In a real implementation, you'd use a proper HTTP client with streaming support
      case HTTPoison.get(url, request_headers, stream_to: self(), async: :once) do
        {:ok, %HTTPoison.AsyncResponse{id: id}} ->
          receive_sse_data(parent, id)

        {:error, reason} ->
          send(parent, {:sse_error, reason})
      end
    rescue
      error ->
        send(parent, {:sse_error, error})
    end
  end

  defp receive_sse_data(parent, id) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: 200} ->
        HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: id})
        receive_sse_data(parent, id)

      %HTTPoison.AsyncHeaders{id: ^id} ->
        HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: id})
        receive_sse_data(parent, id)

      %HTTPoison.AsyncChunk{id: ^id, chunk: chunk} ->
        parse_sse_chunk(parent, chunk)
        HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: id})
        receive_sse_data(parent, id)

      %HTTPoison.AsyncEnd{id: ^id} ->
        send(parent, {:sse_closed})

      %HTTPoison.Error{id: ^id, reason: reason} ->
        send(parent, {:sse_error, reason})
    after
      30_000 ->
        send(parent, {:sse_error, :timeout})
    end
  end

  defp parse_sse_chunk(parent, chunk) do
    # Simple SSE parsing - split by lines and look for data: lines
    lines = String.split(chunk, "\n")

    Enum.each(lines, fn line ->
      case String.trim(line) do
        "data: " <> data ->
          send(parent, {:sse_message, data})

        _ ->
          :ignore
      end
    end)
  end

  defp send_http_message(state, message) do
    post_url = build_post_url(state.base_url)
    json_body = Jason.encode!(message)

    headers = [
      {"Content-Type", "application/json"}
      | state.headers
    ]

    case HTTPoison.post(post_url, json_body, headers) do
      {:ok, %HTTPoison.Response{status_code: code}} when code in 200..299 ->
        :ok

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        {:error, {:http_error, code, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_post_url(sse_url) do
    # Convert SSE URL to POST URL (this is server-specific)
    # For example: http://server/sse -> http://server/message
    String.replace(sse_url, "/sse", "/message")
  end

  defp disconnect(%{stream_pid: nil} = state), do: state

  defp disconnect(%{stream_pid: stream_pid} = state) do
    Process.unlink(stream_pid)
    Process.exit(stream_pid, :normal)
    %{state | stream_pid: nil, connection_state: :disconnected}
  end

  defp handle_received_message(message) do
    # Forward to message router or parent process
    # This would need to be connected to the actual message routing system
    Logger.debug("Handling received SSE message: #{inspect(message)}")
  end
end
