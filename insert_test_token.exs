#!/usr/bin/env elixir

# Insert OAuth token for testing
IO.puts("🔧 Inserting OAuth token for testing...")

credentials = %{
  "access_token" =>
    "sk-ant-token-VqVhiMqrYD9JyANPEyBWwLLRK8KDKnGHdZBBcQ3z5vLK9LCxfvDjPJRFCZ7mCQg8XKnQJRhw5bFh2dBrY6W9Gg1",
  "token_type" => "Bearer"
}

# Calculate expiry (4 hours from now)
expires_at =
  DateTime.utc_now()
  |> DateTime.add(4, :hour)
  |> DateTime.truncate(:second)

auth = %TheMaestro.SavedAuthentication{
  provider: :anthropic,
  auth_type: :oauth,
  credentials: credentials,
  expires_at: expires_at
}

case TheMaestro.Repo.insert(auth) do
  {:ok, _} ->
    IO.puts("✅ OAuth token inserted successfully")
    token_preview = String.slice(credentials["access_token"], 0, 20) <> "..."
    IO.puts("   Token: #{token_preview}")
    IO.puts("   Expires: #{expires_at}")

  {:error, changeset} ->
    IO.puts("❌ Failed to insert token: #{inspect(changeset.errors)}")
end
