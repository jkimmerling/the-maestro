defmodule TheMaestro.MCP.Transport.HTTP do
  @moduledoc """
  HTTP streaming transport implementation for MCP servers.

  This transport communicates with MCP servers using HTTP streaming,
  where requests are sent via HTTP POST and responses are received
  via streaming HTTP responses.
  """

  use GenServer
  require Logger

  @behaviour TheMaestro.MCP.Transport

  @type state :: %{
          config: map(),
          base_url: String.t(),
          headers: list(),
          connection_state: :disconnected | :connected | :error,
          http_client: atom(),
          active_requests: map()
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
      base_url: Map.get(config, :http_url),
      headers: Map.get(config, :headers, []),
      connection_state: :disconnected,
      http_client: Map.get(config, :http_client, Finch),
      active_requests: %{}
    }

    if state.base_url do
      # Test connection
      send(self(), :test_connection)
      {:ok, state}
    else
      {:stop, {:error, :missing_http_url}}
    end
  end

  @impl GenServer
  def handle_call({:send_message, message}, from, state) do
    case send_streaming_request(state, message, from) do
      {:ok, request_id} ->
        new_state = %{state | active_requests: Map.put(state.active_requests, request_id, from)}
        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:close, _from, state) do
    # Cancel all active requests
    Enum.each(state.active_requests, fn {_id, from} ->
      GenServer.reply(from, {:error, :connection_closed})
    end)

    new_state = %{state | connection_state: :disconnected, active_requests: %{}}

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info(:test_connection, state) do
    case test_http_connection(state) do
      :ok ->
        Logger.info("HTTP transport connected to #{state.base_url}")
        {:noreply, %{state | connection_state: :connected}}

      {:error, reason} ->
        Logger.error("Failed to connect to HTTP transport: #{inspect(reason)}")
        # Retry connection after delay
        Process.send_after(self(), :test_connection, 5_000)
        {:noreply, %{state | connection_state: :error}}
    end
  end

  def handle_info({:http_response, request_id, response}, state) do
    case Map.pop(state.active_requests, request_id) do
      {nil, _} ->
        Logger.warning("Received response for unknown request: #{request_id}")
        {:noreply, state}

      {from, remaining_requests} ->
        GenServer.reply(from, response)
        new_state = %{state | active_requests: remaining_requests}
        {:noreply, new_state}
    end
  end

  def handle_info({:http_error, request_id, error}, state) do
    case Map.pop(state.active_requests, request_id) do
      {nil, _} ->
        Logger.warning("Received error for unknown request: #{request_id}")
        {:noreply, state}

      {from, remaining_requests} ->
        GenServer.reply(from, {:error, error})
        new_state = %{state | active_requests: remaining_requests}
        {:noreply, new_state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("Unexpected message in HTTP transport: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    # Reply to any pending requests with error
    Enum.each(state.active_requests, fn {_id, from} ->
      GenServer.reply(from, {:error, :transport_terminated})
    end)

    :ok
  end

  # Private functions

  defp test_http_connection(state) do
    # Test connection with a simple HEAD request
    headers = [
      {"User-Agent", "TheMaestro-MCP/1.0"}
      | state.headers
    ]

    case HTTPoison.head(state.base_url, headers) do
      {:ok, %HTTPoison.Response{status_code: code}} when code in 200..299 ->
        :ok

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, {:http_status, code}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_streaming_request(state, message, from) do
    request_id = generate_request_id()
    json_body = Jason.encode!(message)

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Connection", "keep-alive"}
      | state.headers
    ]

    parent = self()

    # Spawn a process to handle the streaming request
    spawn_link(fn ->
      handle_streaming_request(parent, request_id, state.base_url, json_body, headers)
    end)

    {:ok, request_id}
  end

  defp handle_streaming_request(parent, request_id, url, body, headers) do
    try do
      case HTTPoison.post(url, body, headers, stream_to: self(), async: :once) do
        {:ok, %HTTPoison.AsyncResponse{id: id}} ->
          receive_streaming_response(parent, request_id, id, "")

        {:error, reason} ->
          send(parent, {:http_error, request_id, reason})
      end
    rescue
      error ->
        send(parent, {:http_error, request_id, error})
    end
  end

  defp receive_streaming_response(parent, request_id, id, buffer) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: 200} ->
        HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: id})
        receive_streaming_response(parent, request_id, id, buffer)

      %HTTPoison.AsyncStatus{id: ^id, code: code} ->
        send(parent, {:http_error, request_id, {:http_status, code}})

      %HTTPoison.AsyncHeaders{id: ^id} ->
        HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: id})
        receive_streaming_response(parent, request_id, id, buffer)

      %HTTPoison.AsyncChunk{id: ^id, chunk: chunk} ->
        new_buffer = buffer <> chunk
        {remaining_buffer, responses} = parse_json_responses(new_buffer)

        # Send completed responses
        Enum.each(responses, fn response ->
          send(parent, {:http_response, request_id, {:ok, response}})
        end)

        HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: id})
        receive_streaming_response(parent, request_id, id, remaining_buffer)

      %HTTPoison.AsyncEnd{id: ^id} ->
        # Process any remaining data in buffer
        case String.trim(buffer) do
          "" ->
            :ok

          remaining ->
            case Jason.decode(remaining) do
              {:ok, response} ->
                send(parent, {:http_response, request_id, {:ok, response}})

              {:error, _} ->
                Logger.warning("Invalid JSON in final buffer: #{remaining}")
            end
        end

      %HTTPoison.Error{id: ^id, reason: reason} ->
        send(parent, {:http_error, request_id, reason})
    after
      60_000 ->
        send(parent, {:http_error, request_id, :timeout})
    end
  end

  defp parse_json_responses(buffer) do
    parse_json_responses(buffer, [])
  end

  defp parse_json_responses(buffer, acc) do
    case String.split(buffer, "\n", parts: 2) do
      [line, rest] when line != "" ->
        case Jason.decode(line) do
          {:ok, response} ->
            parse_json_responses(rest, [response | acc])

          {:error, _} ->
            # Try to find complete JSON objects in the buffer
            find_complete_json(buffer, acc)
        end

      _ ->
        # No complete line, return buffer and accumulated responses
        {buffer, Enum.reverse(acc)}
    end
  end

  defp find_complete_json(buffer, acc) do
    # Simple heuristic: try to find balanced braces
    case find_balanced_json(buffer) do
      {json_str, remaining} ->
        case Jason.decode(json_str) do
          {:ok, response} ->
            parse_json_responses(remaining, [response | acc])

          {:error, _} ->
            {buffer, Enum.reverse(acc)}
        end

      nil ->
        {buffer, Enum.reverse(acc)}
    end
  end

  defp find_balanced_json(buffer) do
    find_balanced_json(buffer, 0, 0, "")
  end

  defp find_balanced_json("", _brace_count, _pos, _acc), do: nil

  defp find_balanced_json(<<"{", rest::binary>>, brace_count, pos, acc) do
    find_balanced_json(rest, brace_count + 1, pos + 1, acc <> "{")
  end

  defp find_balanced_json(<<"}", rest::binary>>, 1, pos, acc) do
    # Found complete JSON object
    json_str = acc <> "}"
    {json_str, rest}
  end

  defp find_balanced_json(<<"}", rest::binary>>, brace_count, pos, acc) when brace_count > 1 do
    find_balanced_json(rest, brace_count - 1, pos + 1, acc <> "}")
  end

  defp find_balanced_json(<<char::utf8, rest::binary>>, brace_count, pos, acc)
       when brace_count > 0 do
    find_balanced_json(rest, brace_count, pos + 1, acc <> <<char::utf8>>)
  end

  defp find_balanced_json(<<_char::utf8, rest::binary>>, 0, pos, acc) do
    # Haven't started a JSON object yet
    find_balanced_json(rest, 0, pos + 1, acc)
  end

  defp generate_request_id do
    "http_req_#{System.system_time(:millisecond)}_#{:rand.uniform(1000)}"
  end
end
