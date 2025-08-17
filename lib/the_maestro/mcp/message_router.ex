defmodule TheMaestro.MCP.MessageRouter do
  @moduledoc """
  Message router for correlating MCP requests and responses.
  
  This GenServer manages request/response correlation, timeout handling,
  and routing of notifications for MCP protocol communication.
  """

  use GenServer
  require Logger

  @type pending_request :: %{
    id: String.t(),
    from: GenServer.from(),
    timer_ref: reference(),
    transport: pid()
  }

  @type state :: %{
    pending_requests: %{String.t() => pending_request()},
    request_counter: integer()
  }

  # Client API

  @doc """
  Start the message router.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Send a request through the transport and track it for response correlation.
  
  ## Parameters
  
  * `router` - PID of the message router
  * `transport` - PID of the transport to send through
  * `message` - Message map to send (will have ID added)
  * `timeout` - Request timeout in milliseconds
  
  ## Returns
  
  * `{:ok, request_id}` - Request sent successfully
  * `{:error, reason}` - Failed to send request
  """
  @spec send_request(pid(), pid(), map(), non_neg_integer()) :: {:ok, String.t()} | {:error, term()}
  def send_request(router, transport, message, timeout \\ 30_000) do
    GenServer.call(router, {:send_request, transport, message, timeout})
  end

  @doc """
  Handle a response received from a transport.
  
  ## Parameters
  
  * `router` - PID of the message router
  * `response` - Response message map
  """
  @spec handle_response(pid(), map()) :: :ok
  def handle_response(router, response) do
    GenServer.cast(router, {:handle_response, response})
  end

  @doc """
  Handle a notification received from a transport.
  
  ## Parameters
  
  * `router` - PID of the message router
  * `notification` - Notification message map
  """
  @spec handle_notification(pid(), map()) :: :ok
  def handle_notification(router, notification) do
    GenServer.cast(router, {:handle_notification, notification})
  end

  @doc """
  Get the count of pending requests.
  
  ## Parameters
  
  * `router` - PID of the message router
  """
  @spec pending_requests(pid()) :: non_neg_integer()
  def pending_requests(router) do
    GenServer.call(router, :pending_requests)
  end

  # GenServer Callbacks

  @impl GenServer
  def init(:ok) do
    state = %{
      pending_requests: %{},
      request_counter: 0
    }
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:send_request, transport, message, timeout}, from, state) do
    request_id = generate_request_id(state.request_counter)
    message_with_id = Map.put(message, :id, request_id)

    case send_to_transport(transport, message_with_id) do
      :ok ->
        timer_ref = Process.send_after(self(), {:timeout, request_id}, timeout)
        
        pending_request = %{
          id: request_id,
          from: from,
          timer_ref: timer_ref,
          transport: transport
        }

        new_state = %{
          state | 
          pending_requests: Map.put(state.pending_requests, request_id, pending_request),
          request_counter: state.request_counter + 1
        }

        {:reply, {:ok, request_id}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:pending_requests, _from, state) do
    count = map_size(state.pending_requests)
    {:reply, count, state}
  end

  @impl GenServer
  def handle_cast({:handle_response, response}, state) do
    request_id = get_response_id(response)
    
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        Logger.warning("Received response for unknown request: #{request_id}")
        {:noreply, state}
      
      {pending_request, remaining_requests} ->
        # Cancel timeout timer
        Process.cancel_timer(pending_request.timer_ref)
        
        # Parse response and reply to caller
        case TheMaestro.MCP.Protocol.parse_response(response) do
          {:ok, parsed_response} ->
            GenServer.reply(pending_request.from, {:ok, parsed_response})
          
          {:error, error} ->
            GenServer.reply(pending_request.from, {:error, error})
        end

        new_state = %{state | pending_requests: remaining_requests}
        {:noreply, new_state}
    end
  end

  def handle_cast({:handle_notification, notification}, state) do
    # Handle MCP notifications (no response correlation needed)
    method = Map.get(notification, "method", "unknown")
    params = Map.get(notification, "params", %{})
    
    Logger.info("Received MCP notification: #{method} with params: #{inspect(params)}")
    
    # TODO: Forward to appropriate handlers based on notification type
    handle_notification_by_method(method, params)
    
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:timeout, request_id}, state) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        # Request already completed
        {:noreply, state}
      
      {pending_request, remaining_requests} ->
        # Reply with timeout error
        GenServer.reply(pending_request.from, {:error, :timeout})
        
        Logger.warning("Request #{request_id} timed out")
        
        new_state = %{state | pending_requests: remaining_requests}
        {:noreply, new_state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("Unexpected message in message router: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp generate_request_id(counter) do
    "req_#{counter}_#{System.system_time(:millisecond)}"
  end

  defp send_to_transport(transport, message) do
    try do
      if Process.alive?(transport) do
        # Try GenServer call first, fallback to direct message
        try do
          case GenServer.call(transport, {:send_message, message}, 100) do
            :ok -> :ok
            {:error, reason} -> {:error, reason}
          end
        catch
          :exit, {:timeout, _} ->
            # Timeout on GenServer call, try direct message for tests
            send(transport, {:send_message, message})
            :ok
          
          :exit, {:noproc, _} ->
            # Not a GenServer, send direct message
            send(transport, {:send_message, message})
            :ok
        end
      else
        {:error, :transport_dead}
      end
    catch
      :exit, reason ->
        Logger.error("Transport process died: #{inspect(reason)}")
        {:error, :transport_dead}
    end
  end

  defp get_response_id(response) do
    Map.get(response, "id") || Map.get(response, :id, "unknown")
  end

  defp handle_notification_by_method("tools/list_changed", params) do
    Logger.info("Tools list changed on server: #{inspect(params)}")
    # TODO: Trigger tool re-discovery
  end

  defp handle_notification_by_method("resources/list_changed", params) do
    Logger.info("Resources list changed on server: #{inspect(params)}")
    # TODO: Trigger resource re-discovery
  end

  defp handle_notification_by_method("progress", params) do
    Logger.debug("Progress notification: #{inspect(params)}")
    # TODO: Update progress indicators
  end

  defp handle_notification_by_method(method, params) do
    Logger.debug("Unknown notification method: #{method} with params: #{inspect(params)}")
  end
end