defmodule TheMaestro.Cache.Redis do
  @moduledoc """
  Redis-backed cache utilities for prompt catalogs and related lookups.

  Keys are computed from arbitrary terms using :erlang.term_to_binary/1, then
  Base64 encoded and prefixed with the configured namespace.
  """

  require Logger
  alias TheMaestro.Cache.RedisClient

  @type key_term :: term()

  def child_spec(_args \\ []) do
    url = Application.get_env(:the_maestro, :redis_url, "redis://localhost:6379/0")

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [url]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(url) when is_binary(url), do: Redix.start_link(url, name: TheMaestro.Redis)

  def fetch(key_term, ttl_ms, fun) when is_function(fun, 0) and is_integer(ttl_ms) do
    key = key_for(key_term)
    conn = TheMaestro.Redis

    case RedisClient.command(conn, ["GET", key]) do
      {:ok, nil} ->
        set_and_return(conn, key, ttl_ms, fun)

      {:ok, bin} when is_binary(bin) ->
        with {:ok, %{:v => value, :at_ms => at_ms}} <- decode_payload(bin),
             true <- fresh?(at_ms, ttl_ms) do
          value
        else
          _ -> set_and_return(conn, key, ttl_ms, fun)
        end

      _ ->
        fun.()
    end
  end

  def delete_all(prefix \\ nil) do
    pfx = prefix || Application.get_env(:the_maestro, :redis_cache_prefix, "the_maestro:prompts")
    conn = TheMaestro.Redis
    scan_delete(conn, "0", pfx)
    :ok
  end

  def key_for(term) do
    prefix = Application.get_env(:the_maestro, :redis_cache_prefix, "the_maestro:prompts")
    encoded = term |> :erlang.term_to_binary() |> Base.encode64()
    prefix <> ":" <> encoded
  end

  defp set_and_return(conn, key, ttl_ms, fun) do
    value = fun.()
    payload = :erlang.term_to_binary(%{v: value, at_ms: now_ms()})
    ttl_sec = max(div(ttl_ms, 1000), 1)
    _ = RedisClient.command(conn, ["SETEX", key, Integer.to_string(ttl_sec), payload])
    value
  end

  defp scan_delete(conn, cursor, prefix) do
    case RedisClient.command(conn, ["SCAN", cursor, "MATCH", prefix <> ":*", "COUNT", "1000"]) do
      {:ok, [next, keys]} when is_list(keys) ->
        if keys != [], do: RedisClient.command(conn, ["DEL" | keys])
        if next == "0", do: :ok, else: scan_delete(conn, next, prefix)

      {:error, reason} ->
        Logger.error("Redis SCAN error: #{inspect(reason)}")
        :ok

      other ->
        Logger.error("Redis SCAN unexpected response: #{inspect(other)}")
        :ok
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
  defp fresh?(at_ms, ttl_ms) when is_integer(at_ms), do: now_ms() - at_ms < ttl_ms
  defp fresh?(_, _), do: false

  defp decode_payload(<<131, _::binary>> = bin), do: {:ok, :erlang.binary_to_term(bin)}

  defp decode_payload(bin) when is_binary(bin) do
    case Jason.decode(bin) do
      {:ok, %{"v" => v, "at_ms" => at}} -> {:ok, %{v: v, at_ms: at}}
      _ -> :error
    end
  end
end
