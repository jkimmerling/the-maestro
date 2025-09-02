#!/usr/bin/env elixir
# Memory leak detection over extended multi-provider usage

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

iterations = (System.get_env("MEMORY_ITERS") || "200") |> String.to_integer()
threshold = (System.get_env("MEMORY_THRESHOLD_BYTES") || "100000000") |> String.to_integer()

providers = [
  {:openai, System.get_env("OPENAI_OAUTH_SESSION"), System.get_env("OPENAI_MODEL") || "gpt-4o"},
  {:anthropic, System.get_env("ANTHROPIC_OAUTH_SESSION"), System.get_env("ANTHROPIC_MODEL") || "claude-3-5-sonnet-20241022"},
  {:gemini, System.get_env("GEMINI_OAUTH_SESSION"), System.get_env("GEMINI_MODEL") || "gemini-2.0-flash-exp"}
]

def run_cycle(providers) do
  Enum.each(providers, fn {prov, sess, model} ->
    if is_binary(sess) do
      _ = Provider.stream_chat(prov, sess, [%{"role" => "user", "content" => "ping"}], model: model)
    end
  end)
end

initial = :erlang.memory(:total)

for i <- 1..iterations do
  run_cycle(providers)
  if rem(i, 50) == 0 do
    :erlang.garbage_collect()
    current = :erlang.memory(:total)
    growth = current - initial
    IO.puts("iteration=#{i} mem_growth=#{growth}")
    if growth > threshold do
      raise "Memory leak detected at iteration #{i}: #{growth} bytes growth"
    end
  end
end

final = :erlang.memory(:total)
IO.puts("OK: initial=#{initial} final=#{final} growth=#{final - initial}")

