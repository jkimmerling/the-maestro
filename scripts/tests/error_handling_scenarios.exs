#!/usr/bin/env elixir
# Error handling and recovery scenarios across providers

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

defmodule ErrorScenarios do
  def simulate_timeout(provider, session, model) do
    case Provider.stream_chat(provider, session, [%{"role" => "user", "content" => "ping"}], model: model, timeout: 1) do
      {:error, reason} -> {:ok, {:timeout_scenario, reason}}
      other -> {:error, {:expected_timeout, other}}
    end
  end

  def invalid_session(provider) do
    case Provider.stream_chat(provider, "__nonexistent__", [%{"role" => "user", "content" => "ping"}], []) do
      {:error, :session_not_found} -> {:ok, :session_not_found}
      other -> {:error, {:expected_session_not_found, other}}
    end
  end
end

cases = [
  {:openai, System.get_env("OPENAI_OAUTH_SESSION"), System.get_env("OPENAI_MODEL") || "gpt-4o"},
  {:anthropic, System.get_env("ANTHROPIC_OAUTH_SESSION"), System.get_env("ANTHROPIC_MODEL") || "claude-3-5-sonnet-20241022"},
  {:gemini, System.get_env("GEMINI_OAUTH_SESSION"), System.get_env("GEMINI_MODEL") || "gemini-2.0-flash-exp"}
]

results =
  Enum.flat_map(cases, fn {prov, sess, model} ->
    [
      {:timeout, prov, ErrorScenarios.simulate_timeout(prov, sess, model)},
      {:invalid_session, prov, ErrorScenarios.invalid_session(prov)}
    ]
  end)

IO.inspect(results, label: "error_handling_results")

