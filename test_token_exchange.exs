# Test actual token exchange with real authorization code

IO.puts("🔧 TESTING REAL TOKEN EXCHANGE")
IO.puts("📁 Using: lib/the_maestro/auth.ex")
IO.puts("🎯 Function: TheMaestro.Auth.exchange_code_for_tokens/2")
IO.puts("")

# Authorization code from user
auth_code =
  "4odRX46ADwzIUTPcFfik3AeINQJ76C95sAZeIz465ONuefOW#fi6lA63xfvyZKwW0SAgf5KmnDYLoAf-92SDZAbODRLU"

# Generate PKCE params to match the URL generation (we need the same code_verifier)
# Note: In real flow, we'd store these from the URL generation step
# For testing, we'll recreate them using the state from the auth code

# Extract state from auth code (state = code_verifier from the URL generation)
[_code_part, state] = String.split(auth_code, "#", parts: 2)

# Create matching PKCE params using the state as code_verifier
code_verifier = state
code_challenge = :crypto.hash(:sha256, code_verifier) |> Base.url_encode64(padding: false)

pkce_params = %TheMaestro.Auth.PKCEParams{
  code_verifier: code_verifier,
  code_challenge: code_challenge,
  code_challenge_method: "S256"
}

IO.puts("🔑 Extracted PKCE params:")
IO.puts("   code_verifier: #{String.slice(code_verifier, 0, 20)}...")
IO.puts("   code_challenge: #{String.slice(code_challenge, 0, 20)}...")
IO.puts("")

case TheMaestro.Auth.exchange_code_for_tokens(auth_code, pkce_params) do
  {:ok, oauth_token} ->
    IO.puts("✅ TOKEN EXCHANGE SUCCESS!")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("🎯 Access Token: #{String.slice(oauth_token.access_token, 0, 30)}...")

    IO.puts(
      "🔄 Refresh Token: #{if oauth_token.refresh_token, do: String.slice(oauth_token.refresh_token, 0, 30) <> "...", else: "nil"}"
    )

    IO.puts("⏰ Expires: #{DateTime.from_unix!(oauth_token.expiry)}")
    IO.puts("🔒 Token Type: #{oauth_token.token_type}")
    IO.puts("📋 Scope: #{oauth_token.scope}")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

  {:error, reason} ->
    IO.puts("❌ TOKEN EXCHANGE FAILED!")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("Error: #{inspect(reason)}")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
end
