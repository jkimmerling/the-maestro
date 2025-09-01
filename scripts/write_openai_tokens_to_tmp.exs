#!/usr/bin/env elixir
# Writes saved OpenAI OAuth tokens for a named session to /tmp/maestro_oauth_tokens.json

defmodule WriteOpenAITokens do
  def main(args) do
    Application.ensure_all_started(:logger)
    Application.ensure_all_started(:jason)

    session = List.first(args) || System.get_env("OPENAI_OAUTH_SESSION") || "personal_chatgpt"
    path = "/tmp/maestro_oauth_tokens.json"

    case TheMaestro.SavedAuthentication.get_by_provider_and_name(:openai, :oauth, session) do
      %TheMaestro.SavedAuthentication{credentials: creds} ->
        data = %{
          "access_token" => Map.get(creds, "access_token"),
          "id_token" => Map.get(creds, "id_token")
        }

        File.write!(path, Jason.encode!(data))
        IO.puts("✅ Wrote tokens for session '#{session}' to #{path}")

      _ ->
        IO.puts("❌ Could not find OpenAI OAuth session: #{session}")
        System.halt(1)
    end
  end
end

WriteOpenAITokens.main(System.argv())

