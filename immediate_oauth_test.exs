# IMMEDIATE OAuth test - MUST get 200 OK or implementation is BROKEN

IO.puts("🚨 CRITICAL QA TEST: IMMEDIATE OAuth Flow")
IO.puts("🎯 REQUIREMENT: 200 OK response with real API data")
IO.puts("")

# Fresh authorization code
auth_code = "wuKiTenFkCzOKgbAb7oeBPcqg06WaY4DTvSQDBJzVD5YxwAz#rxSQSJ7MKNuAAAccUQhb5yRxe0Py1uoNwWrHvuppLTQ"

# Extract state from auth code (matches the generated PKCE params)
[_code_part, state] = String.split(auth_code, "#", parts: 2)
code_verifier = state
code_challenge = :crypto.hash(:sha256, code_verifier) |> Base.url_encode64(padding: false)

pkce_params = %TheMaestro.Auth.PKCEParams{
  code_verifier: code_verifier,
  code_challenge: code_challenge,
  code_challenge_method: "S256"
}

IO.puts("🔄 STEP 1: Token Exchange...")

# IMMEDIATELY exchange for tokens
case TheMaestro.Auth.exchange_code_for_tokens(auth_code, pkce_params) do
  {:ok, oauth_token} ->
    IO.puts("✅ Token exchange SUCCESS!")
    IO.puts("   Access Token: #{String.slice(oauth_token.access_token, 0, 30)}...")
    IO.puts("   Expires: #{DateTime.from_unix!(oauth_token.expiry)}")
    IO.puts("")
    
    IO.puts("🔄 STEP 2: Database Storage...")
    
    # Store in database for Client module
    import Ecto.Query, warn: false
    alias TheMaestro.{Repo, SavedAuthentication}
    
    # Clean up existing
    Repo.delete_all(from sa in SavedAuthentication, where: sa.provider == :anthropic and sa.auth_type == :oauth)
    
    # Insert fresh token with future expiry
    {:ok, saved_auth} = %SavedAuthentication{}
    |> SavedAuthentication.changeset(%{
      provider: :anthropic,
      auth_type: :oauth,
      credentials: %{
        "access_token" => oauth_token.access_token,
        "refresh_token" => oauth_token.refresh_token,
        "token_type" => "Bearer",
        "scope" => oauth_token.scope
      },
      expires_at: DateTime.from_unix!(oauth_token.expiry)
    })
    |> Repo.insert()
    
    IO.puts("✅ Token stored in database (ID: #{saved_auth.id})")
    IO.puts("")
    
    IO.puts("🔄 STEP 3: IMMEDIATE API Test...")
    
    # Create OAuth client
    client = TheMaestro.Providers.Client.build_client(:anthropic, :oauth)
    
    case client do
      %Tesla.Client{} ->
        IO.puts("✅ OAuth client created")
        
        # IMMEDIATE API call
        request_body = %{
          model: "claude-3-5-sonnet-20241022",
          max_tokens: 100,
          system: "You are Claude Code, Anthropic's official CLI for Claude.",
          messages: [
            %{
              role: "user", 
              content: "What is 2+2? Respond with just the number."
            }
          ]
        }
        
        IO.puts("📡 Making IMMEDIATE API call...")
        
        case Tesla.post(client, "/v1/messages", request_body) do
          {:ok, %Tesla.Env{status: 200, body: response}} ->
            IO.puts("🎉🎉🎉 SUCCESS! 200 OK RESPONSE! 🎉🎉🎉")
            IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            IO.puts("✅ OAuth implementation is WORKING!")
            IO.puts("✅ Bearer token authentication is WORKING!")
            IO.puts("✅ Real API response received!")
            IO.puts("")
            IO.puts("📊 Response details:")
            IO.puts("   Status: 200 OK")
            if response["content"] && is_list(response["content"]) do
              content = response["content"] |> Enum.find(fn item -> item["type"] == "text" end)
              if content do
                IO.puts("   Claude's Answer: \"#{content["text"]}\"")
              end
            end
            IO.puts("   Model: #{response["model"] || "N/A"}")
            IO.puts("   Usage: #{inspect(response["usage"] || %{})}")
            IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
          {:ok, %Tesla.Env{status: status, body: response}} ->
            IO.puts("❌ FAILURE! API returned status #{status}")
            IO.puts("📄 Response: #{inspect(response)}")
            IO.puts("🚨 OAuth implementation has CRITICAL ISSUES")
            
          {:error, reason} ->
            IO.puts("❌ FAILURE! API call error: #{inspect(reason)}")
            IO.puts("🚨 OAuth implementation has CRITICAL ISSUES")
        end
        
      {:error, reason} ->
        IO.puts("❌ FAILURE! OAuth client creation failed: #{inspect(reason)}")
        IO.puts("🚨 OAuth implementation has CRITICAL ISSUES")
    end
    
  {:error, reason} ->
    IO.puts("❌ FAILURE! Token exchange failed: #{inspect(reason)}")
    IO.puts("🚨 OAuth implementation has CRITICAL ISSUES")
end