#!/usr/bin/env elixir

# OAuth Token Exchange Script
# Run this script after getting the authorization code from the browser

IO.puts("🔄 OAuth Token Exchange")
IO.puts("")

# Get authorization code from command line argument or user input
auth_code =
  case System.argv() do
    [code] ->
      code

    [] ->
      IO.puts("Enter the authorization code from the OAuth callback URL:")
      IO.gets("Auth Code: ") |> String.trim()
  end

if auth_code == "" do
  IO.puts("❌ No authorization code provided")
  System.halt(1)
end

IO.puts("📝 Processing authorization code: #{String.slice(auth_code, 0, 20)}...")

# Read PKCE parameters from file
pkce_content = File.read!("pkce_params.txt")
code_verifier = Regex.run(~r/PKCE_CODE_VERIFIER = "([^"]+)"/, pkce_content) |> List.last()
code_challenge = Regex.run(~r/PKCE_CODE_CHALLENGE = "([^"]+)"/, pkce_content) |> List.last()

code_challenge_method =
  Regex.run(~r/PKCE_CODE_CHALLENGE_METHOD = "([^"]+)"/, pkce_content) |> List.last()

# Create PKCEParams struct
pkce_params = %TheMaestro.Auth.PKCEParams{
  code_verifier: code_verifier,
  code_challenge: code_challenge,
  code_challenge_method: code_challenge_method
}

IO.puts("✅ PKCE parameters loaded successfully")
IO.puts("")

# Exchange code for tokens
IO.puts("🔄 Exchanging authorization code for tokens...")

case TheMaestro.Auth.exchange_code_for_tokens(auth_code, pkce_params) do
  {:ok, oauth_token} ->
    IO.puts("🎉 SUCCESS! OAuth tokens received")
    IO.puts("")
    IO.puts("📊 TOKEN DETAILS:")
    IO.puts("Access Token: #{String.slice(oauth_token.access_token, 0, 30)}...")
    IO.puts("Token Type: #{oauth_token.token_type}")

    IO.puts(
      "Expires At: #{if oauth_token.expiry, do: DateTime.from_unix!(oauth_token.expiry), else: "N/A"}"
    )

    IO.puts(
      "Refresh Token: #{if oauth_token.refresh_token, do: String.slice(oauth_token.refresh_token, 0, 30) <> "...", else: "N/A"}"
    )

    IO.puts("Scope: #{oauth_token.scope || "N/A"}")
    IO.puts("")

    # Save tokens to file for testing
    token_data = %{
      access_token: oauth_token.access_token,
      refresh_token: oauth_token.refresh_token,
      token_type: oauth_token.token_type,
      expiry: oauth_token.expiry,
      scope: oauth_token.scope,
      generated_at: DateTime.utc_now() |> DateTime.to_string()
    }

    File.write!("oauth_tokens.json", Jason.encode!(token_data, pretty: true))
    IO.puts("💾 Tokens saved to: oauth_tokens.json")
    IO.puts("")
    IO.puts("🔐 NEXT STEP: Store tokens in database")
    IO.puts("Run this to store in saved_authentications table:")
    IO.puts("mix run -e \"")
    IO.puts("  tokens = File.read!('oauth_tokens.json') |> Jason.decode!()")
    IO.puts("  expires_at = DateTime.from_unix!(tokens[\\\"expiry\\\"])")
    IO.puts("  %TheMaestro.SavedAuthentication{}")
    IO.puts("  |> TheMaestro.SavedAuthentication.changeset(%{")
    IO.puts("    provider: :anthropic,")
    IO.puts("    auth_type: :oauth,")
    IO.puts("    credentials: %{")
    IO.puts("      \\\"access_token\\\" => tokens[\\\"access_token\\\"],")
    IO.puts("      \\\"refresh_token\\\" => tokens[\\\"refresh_token\\\"],")
    IO.puts("      \\\"token_type\\\" => tokens[\\\"token_type\\\"],")
    IO.puts("      \\\"scope\\\" => tokens[\\\"scope\\\"]")
    IO.puts("    },")
    IO.puts("    expires_at: expires_at")
    IO.puts("  })")
    IO.puts("  |> TheMaestro.Repo.insert!()")
    IO.puts("\"")

  {:error, reason} ->
    IO.puts("❌ TOKEN EXCHANGE FAILED")
    IO.puts("Error: #{inspect(reason)}")
    IO.puts("")
    IO.puts("💡 TROUBLESHOOTING:")
    IO.puts("1. Check that the authorization code is complete and correct")
    IO.puts("2. Make sure you didn't wait too long (codes expire quickly)")
    IO.puts("3. Verify the PKCE parameters match the original OAuth URL")
    IO.puts("4. Try generating a new OAuth URL and starting over")
end
