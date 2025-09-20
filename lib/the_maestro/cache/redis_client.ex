defmodule TheMaestro.Cache.RedisClient do
  @moduledoc """
  Minimal Redis client indirection to support test-time mocking.

  Picks the adapter module from `:the_maestro, :redis_adapter` (defaults to `Redix`).
  The adapter is expected to export `command/2` compatible with `Redix.command/2`.
  """

  def command(conn, args), do: adapter().command(conn, args)
  defp adapter do
    Application.get_env(:the_maestro, :redis_adapter, Redix)
  end
end
