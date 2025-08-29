alias TheMaestro.Auth

# PKCE params from our test
pkce_params = %Auth.PKCEParams{
  code_verifier: "d1crwgXJalwzbNOIgmTX3gMNNrWoXVslZDxXiRHMj6s",
  code_challenge: "TeoB4BXNrbd76mzfm6oswViaZWBPDCQfiEmfHhfijr0",
  code_challenge_method: "S256"
}

# Authorization code from browser OAuth flow
auth_code =
  "86jl2yYdgnkk0n3QCwwfkV88GWWQYoR3ReKyiBQ8MkfmkGqo#d1crwgXJalwzbNOIgmTX3gMNNrWoXVslZDxXiRHMj6s"

IO.puts("🧪 Testing real OAuth token exchange...")
IO.puts("📋 Authorization Code: #{String.slice(auth_code, 0, 30)}...")
IO.puts("🔐 Code Verifier: #{String.slice(pkce_params.code_verifier, 0, 20)}...")

# Test token exchange
case Auth.exchange_code_for_tokens(auth_code, pkce_params) do
  {:ok, oauth_token} ->
    IO.puts("\n🎉 SUCCESS: Token exchange completed!")
    IO.puts("✅ Access Token: #{String.slice(oauth_token.access_token, 0, 20)}...")
    IO.puts("✅ Token Type: #{oauth_token.token_type}")
    IO.puts("✅ Expires: #{oauth_token.expiry} (#{DateTime.from_unix!(oauth_token.expiry)})")

    if oauth_token.refresh_token do
      IO.puts("✅ Refresh Token: #{String.slice(oauth_token.refresh_token, 0, 20)}...")
    end

    if oauth_token.scope do
      IO.puts("✅ Scope: #{oauth_token.scope}")
    end

    IO.puts("\n🎯 REAL OAUTH FLOW VALIDATION COMPLETE!")

  {:error, reason} ->
    IO.puts("\n❌ Token exchange failed:")
    IO.puts("   #{inspect(reason)}")
    IO.puts("\n🔍 This could be due to:")
    IO.puts("   - Expired authorization code (codes expire quickly)")
    IO.puts("   - Network/connectivity issues")
    IO.puts("   - Configuration problems")
end
