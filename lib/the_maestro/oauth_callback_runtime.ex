defmodule TheMaestro.OAuthCallbackRuntime do
  @moduledoc """
  Runtime manager for the OpenAI OAuth callback HTTP server.

  This GenServer stays running under supervision but only starts the HTTP
  server when requested via `ensure_started/1`. It automatically stops the
  server after either:
  - a successful OAuth completion (`notify_success/0`), or
  - a timeout (default 180_000 ms)

  It can be started again for subsequent auth flows.
  """

  use GenServer

  @name __MODULE__
  @default_timeout_ms 180_000

  # Public API
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @spec ensure_started(keyword()) :: {:ok, %{port: pos_integer()}} | {:error, term()}
  def ensure_started(opts \\ []) do
    GenServer.call(@name, {:ensure_started, opts}, 5_000)
  end

  @spec notify_success() :: :ok
  def notify_success do
    GenServer.cast(@name, :oauth_success)
  end

  @spec stop() :: :ok
  def stop do
    GenServer.call(@name, :stop)
  end

  @spec alive?() :: boolean()
  def alive? do
    GenServer.call(@name, :alive?)
  end

  @spec current_port() :: pos_integer() | nil
  def current_port do
    GenServer.call(@name, :current_port)
  end

  # GenServer callbacks
  @impl true
  def init(_), do: {:ok, %{server_pid: nil, timer_ref: nil, port: port_from_env()}}

  @impl true
  def handle_call({:ensure_started, opts}, _from, state) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    port = Keyword.get(opts, :port, state.port || port_from_env())

    if is_pid(state.server_pid) and Process.alive?(state.server_pid) do
      {:reply, {:ok, %{port: port}}, %{state | port: port}}
    else
      case Bandit.start_link(
             plug: TheMaestro.OAuthCallbackPlug,
             scheme: :http,
             port: port,
             thousand_island_options: [num_acceptors: 2]
           ) do
        {:ok, pid} ->
          tref = Process.send_after(self(), :timeout, timeout_ms)
          {:reply, {:ok, %{port: port}}, %{server_pid: pid, timer_ref: tref, port: port}}

        {:error, reason} ->
          {:reply, {:error, reason}, %{state | port: port}}
      end
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    state = stop_server(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:alive?, _from, state) do
    {:reply, is_pid(state.server_pid) and Process.alive?(state.server_pid), state}
  end

  @impl true
  def handle_call(:current_port, _from, state), do: {:reply, state.port, state}

  @impl true
  def handle_cast(:oauth_success, state) do
    state = stop_server(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:timeout, state) do
    state = stop_server(state)
    {:noreply, state}
  end

  defp stop_server(%{server_pid: pid, timer_ref: tref} = state) do
    if is_reference(tref), do: Process.cancel_timer(tref)
    if is_pid(pid) do
      # Graceful shutdown
      ref = Process.monitor(pid)
      Process.exit(pid, :normal)
      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        2_000 -> :ok
      end
    end

    %{server_pid: nil, timer_ref: nil, port: state.port}
  end

  defp port_from_env do
    case System.get_env("OPENAI_REDIRECT_PORT") do
      nil -> 1455
      s ->
        case Integer.parse(s) do
          {p, _} -> p
          _ -> 1455
        end
    end
  end
end
