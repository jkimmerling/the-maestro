defmodule TheMaestro.RedisMock do
  @moduledoc """
  A Redis mock for testing that implements the Redis commands used by the application.

  Uses ETS for in-memory storage with TTL support.
  """

  use GenServer
  require Logger

  @table_name :redis_mock_storage

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: TheMaestro.Redis)
  end

  def command(conn, args) when conn == TheMaestro.Redis do
    GenServer.call(TheMaestro.Redis, {:command, args})
  end

  def pipeline(conn, commands, caller, timeout) when conn == TheMaestro.Redis do
    GenServer.cast(TheMaestro.Redis, {:pipeline, commands, caller, timeout})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:set, :named_table, :public])
    # Start a process to clean up expired keys periodically
    Process.send_after(self(), :cleanup_expired, 60_000)
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:command, ["GET", key]}, _from, state) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:reply, {:ok, value}, state}
        else
          :ets.delete(@table_name, key)
          {:reply, {:ok, nil}, state}
        end

      [] ->
        {:reply, {:ok, nil}, state}
    end
  end

  @impl true
  def handle_call({:command, ["SET", key, value]}, _from, state) do
    # 1 hour default
    expires_at = System.monotonic_time(:millisecond) + 3_600_000
    :ets.insert(@table_name, {key, value, expires_at})
    {:reply, {:ok, "OK"}, state}
  end

  @impl true
  def handle_call({:command, ["SETEX", key, ttl_str, value]}, _from, state) do
    ttl_seconds = String.to_integer(ttl_str)
    expires_at = System.monotonic_time(:millisecond) + ttl_seconds * 1000
    :ets.insert(@table_name, {key, value, expires_at})
    {:reply, {:ok, "OK"}, state}
  end

  @impl true
  def handle_call({:command, ["DEL" | keys]}, _from, state) do
    deleted_count =
      Enum.reduce(keys, 0, fn key, acc ->
        case :ets.lookup(@table_name, key) do
          [{^key, _, _}] ->
            :ets.delete(@table_name, key)
            acc + 1

          [] ->
            acc
        end
      end)

    {:reply, {:ok, deleted_count}, state}
  end

  @impl true
  def handle_call({:command, ["SCAN", _cursor, "MATCH", pattern, "COUNT", _count]}, _from, state) do
    # Simple implementation - get all keys matching pattern
    all_keys =
      :ets.foldl(
        fn {key, _value, expires_at}, acc ->
          if System.monotonic_time(:millisecond) < expires_at do
            [key | acc]
          else
            acc
          end
        end,
        [],
        @table_name
      )

    # Simple pattern matching (only supports basic * wildcards)
    pattern_regex =
      pattern
      |> String.replace("*", ".*")
      |> Regex.compile!()

    matching_keys = Enum.filter(all_keys, &Regex.match?(pattern_regex, &1))

    # For simplicity, return all matching keys in one scan
    {:reply, {:ok, ["0", matching_keys]}, state}
  end

  @impl true
  def handle_call({:command, args}, _from, state) do
    Logger.warning("RedisMock: Unhandled command: #{inspect(args)}")
    {:reply, {:error, "Command not implemented in mock"}, state}
  end

  @impl true
  def handle_cast({:pipeline, commands, {caller_pid, ref}, _timeout}, state) do
    # Execute all commands in the pipeline
    results =
      Enum.map(commands, fn cmd ->
        case handle_command(cmd, state) do
          # Return just the result, not wrapped in :ok
          {:ok, result} -> result
          {:error, reason} -> {:error, reason}
        end
      end)

    # Send response back to caller - Redix expects the results directly
    send(caller_pid, {ref, {:ok, results}})
    {:noreply, state}
  end

  # Helper function to handle individual commands (reuse logic from handle_call)
  defp handle_command(["GET", key], _state) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, value}
        else
          :ets.delete(@table_name, key)
          {:ok, nil}
        end

      [] ->
        {:ok, nil}
    end
  end

  defp handle_command(["SET", key, value], _state) do
    # 1 hour default
    expires_at = System.monotonic_time(:millisecond) + 3_600_000
    :ets.insert(@table_name, {key, value, expires_at})
    {:ok, "OK"}
  end

  defp handle_command(["SETEX", key, ttl_str, value], _state) do
    ttl_seconds = String.to_integer(ttl_str)
    expires_at = System.monotonic_time(:millisecond) + ttl_seconds * 1000
    :ets.insert(@table_name, {key, value, expires_at})
    {:ok, "OK"}
  end

  defp handle_command(["DEL" | keys], _state) do
    deleted_count =
      Enum.reduce(keys, 0, fn key, acc ->
        case :ets.lookup(@table_name, key) do
          [{^key, _, _}] ->
            :ets.delete(@table_name, key)
            acc + 1

          [] ->
            acc
        end
      end)

    {:ok, deleted_count}
  end

  defp handle_command(["SCAN", _cursor, "MATCH", pattern, "COUNT", _count], _state) do
    # Simple implementation - get all keys matching pattern
    all_keys =
      :ets.foldl(
        fn {key, _value, expires_at}, acc ->
          if System.monotonic_time(:millisecond) < expires_at do
            [key | acc]
          else
            acc
          end
        end,
        [],
        @table_name
      )

    # Simple pattern matching (only supports basic * wildcards)
    pattern_regex =
      pattern
      |> String.replace("*", ".*")
      |> Regex.compile!()

    matching_keys = Enum.filter(all_keys, &Regex.match?(pattern_regex, &1))

    # For simplicity, return all matching keys in one scan
    {:ok, ["0", matching_keys]}
  end

  defp handle_command(cmd, _state) do
    Logger.warning("RedisMock: Unhandled pipeline command: #{inspect(cmd)}")
    {:error, "Command not implemented in mock"}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    now = System.monotonic_time(:millisecond)

    expired_keys =
      :ets.foldl(
        fn {key, _value, expires_at}, acc ->
          if now >= expires_at do
            [key | acc]
          else
            acc
          end
        end,
        [],
        @table_name
      )

    Enum.each(expired_keys, &:ets.delete(@table_name, &1))

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_expired, 60_000)
    {:noreply, state}
  end
end
