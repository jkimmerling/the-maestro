defmodule TheMaestro.Cache.RedisCacheTest do
  use TheMaestro.DataCase, async: false

  alias TheMaestro.Cache.Redis, as: RedisCache

  test "invalidate_prompt_cache deletes cached keys" do
    # Ensure Redis connection is available; otherwise skip
    conn = TheMaestro.Redis
    case :erlang.function_exported(Redix, :command, 2) do
      true ->
        key = RedisCache.key_for({:list_system_prompts, :openai, false, true, false})
        payload = Jason.encode!(%{"v" => [%{}], "at_ms" => System.monotonic_time(:millisecond)})

        assert {:ok, "OK"} = Redix.command(conn, ["SET", key, payload])
        assert {:ok, ^payload} = Redix.command(conn, ["GET", key])
        :ok = TheMaestro.SuppliedContext.invalidate_prompt_cache()

        assert {:ok, nil} = Redix.command(conn, ["GET", key])

      false ->
        # Redix not available (deps not installed); skip deterministically
        :ok
    end
  end
end
