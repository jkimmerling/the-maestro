# Test real OAuth API call with actual Bearer token authentication

IO.puts("🚀 TESTING REAL OAUTH API CALL")
IO.puts("📁 Using: lib/the_maestro/providers/client.ex")
IO.puts("🎯 Function: Client.build_client(:anthropic, :oauth)")
IO.puts("")

# OAuth token from successful exchange
access_token =
  "sk-ant-oat01-qri6p6A6Kp9fMqEywV9nLIlO3oTVgTRTKJRAd4GNGNqb6QC_4WJeEEeG6rOWQj9e1aeOlSE4HXZSoxH7zFXsZw"

refresh_token =
  "sk-ant-ort01-vV-T-uug0Arp3cjGKgm8NzEhvRyqNMT4SLI6u4FmJdK9k2XQlH5hc1UYLsJEsB2dIUWWOhWVLQnYGOGi1BFDZnC"

# 1 hour from now
expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

IO.puts("🔑 Using OAuth token:")
IO.puts("   Access Token: #{String.slice(access_token, 0, 30)}...")
IO.puts("   Expires: #{expires_at}")
IO.puts("")

# Insert token into database for Client module to use
import Ecto.Query, warn: false
alias TheMaestro.{Repo, SavedAuthentication}

# Clean up any existing OAuth tokens
Repo.delete_all(
  from sa in SavedAuthentication, where: sa.provider == :anthropic and sa.auth_type == :oauth
)

# Insert the real OAuth token
{:ok, saved_auth} =
  %SavedAuthentication{}
  |> SavedAuthentication.changeset(%{
    provider: :anthropic,
    auth_type: :oauth,
    credentials: %{
      "access_token" => access_token,
      "refresh_token" => refresh_token,
      "token_type" => "Bearer",
      "scope" => "user:inference user:profile"
    },
    expires_at: expires_at
  })
  |> Repo.insert()

IO.puts("✅ OAuth token inserted into database (ID: #{saved_auth.id})")
IO.puts("")

# Test OAuth client creation
IO.puts("🔧 Creating OAuth client...")
client = TheMaestro.Providers.Client.build_client(:anthropic, :oauth)

case client do
  %Tesla.Client{} ->
    IO.puts("✅ OAuth client created successfully!")
    IO.puts("")

    # Test actual API call with system prompt requirement
    IO.puts("📡 Testing real API call with OAuth Bearer authentication...")

    request_body = %{
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 50,
      system: "You are Claude Code, Anthropic's official CLI for Claude.",
      messages: [
        %{
          role: "user",
          content: "What is the capital of France? Answer in one sentence."
        }
      ]
    }

    case Tesla.post(client, "/v1/messages", request_body) do
      {:ok, %Tesla.Env{status: 200, body: response}} ->
        IO.puts("🎉 SUCCESS! OAuth API call worked!")
        IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        IO.puts("📊 Status: 200 OK")
        IO.puts("🤖 Response: #{inspect(response, limit: :infinity, pretty: true)}")
        IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

      {:ok, %Tesla.Env{status: status, body: response}} ->
        IO.puts("⚠️  API call returned status #{status}")
        IO.puts("📄 Response: #{inspect(response)}")

      {:error, reason} ->
        IO.puts("❌ API call failed: #{inspect(reason)}")
    end

  {:error, reason} ->
    IO.puts("❌ OAuth client creation failed: #{inspect(reason)}")
end
