#!/usr/bin/env elixir
# Production readiness orchestrator for manual runs in staging/prod-like envs

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

defmodule ProductionReadiness do
  def run do
    scenarios = [
      {:openai_oauth_streaming, :openai, System.get_env("OPENAI_OAUTH_SESSION"), System.get_env("OPENAI_MODEL") || "gpt-4o"},
      {:openai_api_streaming, :openai, System.get_env("OPENAI_API_SESSION"), System.get_env("OPENAI_MODEL") || "gpt-4o"},
      {:anthropic_oauth_streaming, :anthropic, System.get_env("ANTHROPIC_OAUTH_SESSION"), System.get_env("ANTHROPIC_MODEL") || "claude-3-5-sonnet-20241022"},
      {:anthropic_api_streaming, :anthropic, System.get_env("ANTHROPIC_API_SESSION"), System.get_env("ANTHROPIC_MODEL") || "claude-3-5-sonnet-20241022"},
      {:gemini_oauth_streaming, :gemini, System.get_env("GEMINI_OAUTH_SESSION"), System.get_env("GEMINI_MODEL") || "gemini-2.0-flash-exp"}
    ]

    results =
      Enum.map(scenarios, fn {tag, prov, sess, model} ->
        if is_binary(sess) and sess != "" do
          case Provider.stream_chat(prov, sess, [%{"role" => "user", "content" => "ping"}], model: model) do
            {:ok, stream} ->
              _ = stream |> TheMaestro.Streaming.parse_stream(prov) |> Enum.take(5) |> Enum.to_list()
              {tag, :ok}

            other -> {tag, other}
          end
        else
          {tag, :skipped}
        end
      end)

    IO.inspect(results, label: "production_readiness_results")
  end
end

ProductionReadiness.run()

