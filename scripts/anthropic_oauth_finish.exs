#!/usr/bin/env elixir
# Finishes Anthropic OAuth using saved PKCE and a provided authorization code

alias TheMaestro.Auth

Application.ensure_all_started(:logger)

pkce_path = System.get_env("MAESTRO_ANTHROPIC_PKCE_PATH") || "/tmp/maestro_anthropic_pkce.json"
session = System.get_env("ANTHROPIC_OAUTH_SESSION") || "oauth_test_anthropic"
auth_code = System.get_env("ANTHROPIC_AUTH_CODE") || Enum.at(System.argv(), 0)

if is_nil(auth_code) or auth_code == "" do
  IO.puts("Usage: ANTHROPIC_AUTH_CODE=... mix run scripts/anthropic_oauth_finish.exs [code]")
  System.halt(1)
end

{:ok, json} =
  case File.read(pkce_path) do
    {:ok, contents} -> {:ok, Jason.decode!(contents)}
    {:error, reason} -> {:error, reason}
  end

pkce = %Auth.PKCEParams{
  code_verifier: json["code_verifier"],
  code_challenge: json["code_challenge"],
  code_challenge_method: json["code_challenge_method"]
}

IO.puts("Exchanging code for tokens and saving session '#{session}'...")
case Auth.finish_anthropic_oauth(auth_code, pkce, session) do
  {:ok, _token} -> IO.puts("✅ OAuth tokens saved for session: #{session}")
  {:error, reason} -> IO.puts("❌ OAuth failed: #{inspect(reason)}")
end

