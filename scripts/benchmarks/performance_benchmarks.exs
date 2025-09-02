#!/usr/bin/env elixir
# Performance benchmarking helpers for OAuth, API key, streaming, and model listing

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

defmodule PerformanceBenchmarkSuite do
  @benchmark_iterations (System.get_env("BENCH_ITERATIONS") || "20") |> String.to_integer()
  @streaming_timeout 30_000

  def run_performance_benchmarks do
    IO.puts("Running performance benchmarks (iterations=#{@benchmark_iterations})...")

    oauth_times = benchmark_oauth_flows()
    api_key_times = benchmark_api_key_flows()
    streaming_times = benchmark_streaming_performance()
    model_listing_times = benchmark_model_listing()
    memory_usage = benchmark_memory_usage()

    report = %{
      oauth_ms: oauth_times,
      api_key_ms: api_key_times,
      streaming_ms: streaming_times,
      model_listing_ms: model_listing_times,
      memory_bytes: memory_usage
    }

    IO.inspect(report, label: "performance_report")
    :ok
  end

  def benchmark_oauth_flows do
    # This requires manual OAuth completion and is best measured externally.
    # Provide placeholder to keep structure consistent.
    %{openai: :manual, anthropic: :manual, gemini: :manual}
  end

  def benchmark_api_key_flows do
    provs = [
      {:openai, System.get_env("OPENAI_API_KEY"), System.get_env("OPENAI_API_SESSION") || "perf_openai_api"},
      {:anthropic, System.get_env("ANTHROPIC_API_KEY"), System.get_env("ANTHROPIC_API_SESSION") || "perf_anthropic_api"}
    ]

    Enum.into(provs, %{}, fn {prov, key, session} ->
      if key && key != "" do
        t = time_ms(fn ->
          {:ok, _} = Provider.create_session(prov, :api_key, name: session, credentials: %{api_key: key})
        end)
        {prov, t}
      else
        {prov, :skipped}
      end
    end)
  end

  def benchmark_streaming_performance do
    msg = [%{"role" => "user", "content" => "Say a single word: ping"}]
    cases = [
      {:openai, :oauth, System.get_env("OPENAI_OAUTH_SESSION"), System.get_env("OPENAI_MODEL") || "gpt-4o"},
      {:anthropic, :oauth, System.get_env("ANTHROPIC_OAUTH_SESSION"), System.get_env("ANTHROPIC_MODEL") || "claude-3-5-sonnet-20241022"},
      {:gemini, :oauth, System.get_env("GEMINI_OAUTH_SESSION"), System.get_env("GEMINI_MODEL") || "gemini-2.0-flash-exp"}
    ]

    Enum.into(cases, %{}, fn {prov, auth, sess, model} ->
      if is_binary(sess) do
        t = time_ms(fn ->
          {:ok, stream} = Provider.stream_chat(prov, sess, msg, model: model, timeout: @streaming_timeout)
          stream |> TheMaestro.Streaming.parse_stream(prov) |> Enum.take(10) |> Enum.to_list()
        end)
        {{prov, auth}, t}
      else
        {{prov, auth}, :skipped}
      end
    end)
  end

  def benchmark_model_listing do
    cases = [
      {:openai, :oauth, System.get_env("OPENAI_OAUTH_SESSION")},
      {:openai, :api_key, System.get_env("OPENAI_API_SESSION")},
      {:anthropic, :oauth, System.get_env("ANTHROPIC_OAUTH_SESSION")},
      {:anthropic, :api_key, System.get_env("ANTHROPIC_API_SESSION")}
    ]

    Enum.into(cases, %{}, fn {prov, auth, sess} ->
      if is_binary(sess) do
        t = time_ms(fn -> {:ok, _} = Provider.list_models(prov, auth, sess) end)
        {{prov, auth}, t}
      else
        {{prov, auth}, :skipped}
      end
    end)
  end

  def benchmark_memory_usage do
    :erlang.memory(:total)
  end

  defp time_ms(fun) do
    t0 = System.monotonic_time(:millisecond)
    _ = fun.()
    t1 = System.monotonic_time(:millisecond)
    t1 - t0
  end
end

PerformanceBenchmarkSuite.run_performance_benchmarks()

