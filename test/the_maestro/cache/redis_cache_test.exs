defmodule TheMaestro.Cache.RedisCacheTest do
  use TheMaestro.DataCase, async: false

  alias TheMaestro.Cache.Redis, as: RedisCache
  alias TheMaestro.Cache.RedisClient, as: RedisClient
  alias TheMaestro.SuppliedContext

  test "invalidate_prompt_cache deletes cached keys" do
    conn = TheMaestro.Redis
    key = RedisCache.key_for({:list_system_prompts, :openai, false, true, false})
    payload = Jason.encode!(%{"v" => [%{}], "at_ms" => System.monotonic_time(:millisecond)})

    assert {:ok, "OK"} = RedisClient.command(conn, ["SET", key, payload])
    assert {:ok, ^payload} = RedisClient.command(conn, ["GET", key])
    :ok = SuppliedContext.invalidate_prompt_cache()

    assert {:ok, nil} = RedisClient.command(conn, ["GET", key])
  end
end
