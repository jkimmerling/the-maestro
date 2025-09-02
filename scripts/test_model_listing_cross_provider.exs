#!/usr/bin/env elixir
# Cross-provider model listing across auth modes

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

cases = [
  {:openai, :oauth, System.get_env("OPENAI_OAUTH_SESSION") || "oauth_test_openai"},
  {:openai, :api_key, System.get_env("OPENAI_API_SESSION") || "enterprise_test"},
  {:anthropic, :oauth, System.get_env("ANTHROPIC_OAUTH_SESSION") || "oauth_test_anthropic"},
  {:anthropic, :api_key, System.get_env("ANTHROPIC_API_SESSION") || "anthropic_api_test"},
  {:gemini, :oauth, System.get_env("GEMINI_OAUTH_SESSION") || "oauth_test_gemini"}
]

results =
  Enum.map(cases, fn {prov, auth, sess} ->
    case Provider.list_models(prov, auth, sess) do
      {:ok, models} when is_list(models) -> {prov, auth, :ok, length(models)}
      other -> {prov, auth, other}
    end
  end)

IO.inspect(results, label: "model_listing_cross_provider")

