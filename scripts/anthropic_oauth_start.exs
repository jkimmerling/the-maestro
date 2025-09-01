#!/usr/bin/env elixir
# Generates Anthropic OAuth URL + PKCE and stores PKCE in /tmp for later use

alias TheMaestro.Auth

Application.ensure_all_started(:logger)

{:ok, {auth_url, pkce}} = Auth.generate_oauth_url()

pkce_path = System.get_env("MAESTRO_ANTHROPIC_PKCE_PATH") || "/tmp/maestro_anthropic_pkce.json"

data = %{
  "code_verifier" => pkce.code_verifier,
  "code_challenge" => pkce.code_challenge,
  "code_challenge_method" => pkce.code_challenge_method
}

File.write!(pkce_path, Jason.encode!(data))

IO.puts("✅ PKCE saved to: #{pkce_path}")
IO.puts("Open this URL in your browser and authorize:")
IO.puts(auth_url)

