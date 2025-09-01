#!/usr/bin/env elixir
# Completes OpenAI OAuth by exchanging code using stored PKCE, persists session, exports tokens

alias TheMaestro.Auth

args = System.argv()
code = Enum.at(args, 0) || raise "Usage: mix run scripts/openai_oauth_finish.exs CODE [SESSION_NAME]"
session = Enum.at(args, 1) || System.get_env("OPENAI_OAUTH_SESSION") || "personal_chatgpt"

pkce_path = System.get_env("MAESTRO_OPENAI_PKCE_PATH") || "/tmp/maestro_openai_pkce.json"

pkce_json = File.read!(pkce_path) |> Jason.decode!()
pkce = %Auth.PKCEParams{
  code_verifier: pkce_json["code_verifier"],
  code_challenge: pkce_json["code_challenge"],
  code_challenge_method: pkce_json["code_challenge_method"]
}

case Auth.finish_openai_oauth(code, pkce, session) do
  {:ok, _token} ->
    IO.puts("✅ OpenAI OAuth tokens saved for session: #{session}")
    # Export to /tmp for conversation test script
    Mix.Task.run("run", ["scripts/write_openai_tokens_to_tmp.exs", session])
  {:error, reason} ->
    IO.puts("❌ Token exchange failed: #{inspect(reason)}")
    System.halt(1)
end

