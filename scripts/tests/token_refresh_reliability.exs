#!/usr/bin/env elixir
# Background token refresh reliability check using TokenRefreshWorker

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Workers.TokenRefreshWorker

providers = ["anthropic"] # Extend as support is implemented

results =
  Enum.map(providers, fn p ->
    res = TokenRefreshWorker.refresh_token_for_provider(p, "unused")
    {p, res}
  end)

IO.inspect(results, label: "token_refresh_reliability")

