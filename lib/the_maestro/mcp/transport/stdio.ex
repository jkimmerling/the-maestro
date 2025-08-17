defmodule TheMaestro.MCP.Transport.Stdio do
  @moduledoc """
  Stdio transport implementation for MCP servers.

  This transport communicates with MCP servers by spawning a subprocess
  and communicating via stdin/stdout using JSON-RPC messages.
  """

  use GenServer
  require Logger

  @behaviour TheMaestro.MCP.Transport

  @type state :: %{
          config: map(),
          port: port() | nil,
          process_state: :starting | :running | :terminated | :dead,
          buffer: binary(),
          pending_responses: list(),
          parent_pid: pid() | nil
        }

  # Client API

  @impl TheMaestro.MCP.Transport
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, [])
  end

  @doc """
  Start a stdio transport without linking to the calling process.
  
  This is useful when you want to handle failures gracefully without
  the calling process being terminated.
  """
  def start(config) do
    GenServer.start(__MODULE__, config, [])
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
      port: nil,
      process_state: :starting,
      buffer: "",
      pending_responses: [],
      parent_pid: Map.get(config, :parent_pid)
    }

    case start_subprocess(config) do
      {:ok, port} ->
        {:ok, %{state | port: port, process_state: :running}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:send_message, _message}, _from, %{port: nil} = state) do
    {:reply, {:error, :process_dead}, state}
  end

  def handle_call({:send_message, message}, _from, %{port: port} = state) do
    json_message = Jason.encode!(message)
    data = json_message <> "\n"

    Port.command(port, data)
    {:reply, :ok, state}
  rescue
    error ->
      Logger.error("Failed to send message: #{inspect(error)}")
      {:reply, {:error, :send_failed}, state}
  catch
    :exit, reason ->
      Logger.error("Port died while sending: #{inspect(reason)}")
      {:reply, {:error, :process_dead}, %{state | port: nil, process_state: :dead}}
  end

  def handle_call(:close, _from, %{port: port} = state) when not is_nil(port) do
    Port.close(port)
    {:reply, :ok, %{state | port: nil, process_state: :terminated}}
  end

  def handle_call(:close, _from, state) do
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Handle data received from subprocess stdout
    new_buffer = state.buffer <> data
    {processed_buffer, responses} = process_messages(new_buffer)

    # Send responses to parent process if configured, otherwise log
    Enum.each(responses, fn response ->
      if state.parent_pid && Process.alive?(state.parent_pid) do
        send(state.parent_pid, {:mcp_response, self(), response})
      else
        Logger.debug("Received MCP response: #{inspect(response)}")
      end
    end)

    {:noreply, %{state | buffer: processed_buffer}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("MCP subprocess exited with status: #{status}")
    {:noreply, %{state | port: nil, process_state: :terminated}}
  end

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.warning("MCP subprocess port died: #{inspect(reason)}")
    {:noreply, %{state | port: nil, process_state: :dead}}
  end

  def handle_info(msg, state) do
    Logger.debug("Unexpected message in stdio transport: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %{port: port}) when not is_nil(port) do
    Port.close(port)
    :ok
  end

  def terminate(_reason, _state) do
    :ok
  end

  # Private functions

  defp start_subprocess(config) do
    command = Map.get(config, :command)
    args = Map.get(config, :args, [])
    cwd = Map.get(config, :cwd, File.cwd!())
    env = Map.get(config, :env, %{})

    if command do
      # Convert env map to list of tuples
      env_list = Enum.map(env, fn {k, v} -> {to_string(k), to_string(v)} end)

      port_opts = [
        :binary,
        :exit_status,
        {:cd, cwd},
        {:env, env_list},
        {:args, args}
      ]

      try do
        # Try to resolve the command if it's not an absolute path
        resolved_command =
          if String.starts_with?(command, "/") do
            command
          else
            System.find_executable(command) || command
          end

        port = Port.open({:spawn_executable, resolved_command}, port_opts)
        {:ok, port}
      rescue
        error ->
          Logger.error("Failed to start MCP subprocess: #{inspect(error)}")
          {:error, :spawn_failed}
      catch
        kind, reason ->
          Logger.error("Failed to spawn MCP subprocess: #{kind} - #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :missing_command}
    end
  end

  defp process_messages(buffer) do
    process_messages(buffer, [])
  end

  defp process_messages(buffer, acc) do
    case String.split(buffer, "\n", parts: 2) do
      [line, rest] when line != "" ->
        case Jason.decode(line) do
          {:ok, message} ->
            process_messages(rest, [message | acc])

          {:error, _} ->
            # Invalid JSON, skip this line
            Logger.warning("Received invalid JSON from MCP server: #{line}")
            process_messages(rest, acc)
        end

      _ ->
        # No complete message in buffer
        {buffer, Enum.reverse(acc)}
    end
  end
end
