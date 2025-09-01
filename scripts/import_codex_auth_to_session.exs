#!/usr/bin/env elixir
# Imports tokens from $CODEX_HOME/auth.json into a named :openai, :oauth session

alias TheMaestro.SavedAuthentication

Application.ensure_all_started(:logger)
Application.ensure_all_started(:jason)

session = List.first(System.argv()) || System.get_env("OPENAI_OAUTH_SESSION") || "personal_chatgpt"

home = System.get_env("CODEX_HOME") || Path.join(System.user_home!(), ".codex")
auth_path = Path.join(home, "auth.json")

unless File.exists?(auth_path) do
  IO.puts("❌ Codex auth file not found at #{auth_path}")
  System.halt(1)
end

auth = auth_path |> File.read!() |> Jason.decode!()

tokens = auth["tokens"] || %{}
access_token = tokens["access_token"]
refresh_token = tokens["refresh_token"]
id_token = tokens["id_token"]

if is_nil(access_token) or is_nil(id_token) do
  IO.puts("❌ Missing access_token or id_token in Codex auth.json")
  System.halt(1)
end

expires_at = DateTime.add(DateTime.utc_now(), 60 * 60, :second) # unknown exact, set +1h

attrs = %{
  credentials: %{
    "access_token" => access_token,
    "refresh_token" => refresh_token,
    "id_token" => id_token,
    "token_type" => "Bearer"
  },
  expires_at: expires_at
}

case SavedAuthentication.upsert_named_session(:openai, :oauth, session, attrs) do
  {:ok, _sa} -> IO.puts("✅ Imported Codex tokens into session '#{session}'")
  {:error, err} -> IO.puts("❌ Failed to import session: #{inspect(err)}")
end

