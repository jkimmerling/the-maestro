#!/usr/bin/env elixir

# OAuth Flow Script for Manual Testing
# This script generates OAuth URL and saves PKCE params for token exchange

IO.puts("🔐 Starting OAuth Flow Generation...")
IO.puts("")

# Generate OAuth URL with PKCE parameters
case TheMaestro.Auth.generate_oauth_url() do
  {:ok, {auth_url, pkce_params}} ->
    IO.puts("✅ OAuth URL Generated Successfully!")
    IO.puts("")
    IO.puts("🌐 AUTHORIZATION URL:")
    IO.puts(auth_url)
    IO.puts("")
    IO.puts("📋 NEXT STEPS:")
    IO.puts("1. Copy the URL above")
    IO.puts("2. Open it in your browser")
    IO.puts("3. Complete the authorization on Anthropic's page")
    IO.puts("4. Copy the authorization code from the redirect URL")
    IO.puts("5. Return here with the code")
    IO.puts("")

    # Save PKCE parameters for later use
    pkce_file_content = """
    # PKCE Parameters for OAuth Token Exchange
    # Generated on #{DateTime.utc_now() |> DateTime.to_string()}
    # DO NOT SHARE - These parameters are required for token exchange

    PKCE_CODE_VERIFIER = "#{pkce_params.code_verifier}"
    PKCE_CODE_CHALLENGE = "#{pkce_params.code_challenge}"
    PKCE_CODE_CHALLENGE_METHOD = "#{pkce_params.code_challenge_method}"
    PKCE_STATE = "#{pkce_params.state}"
    """

    File.write!("/Users/jasonk/Development/the_maestro/pkce_params.txt", pkce_file_content)
    IO.puts("💾 PKCE parameters saved to: pkce_params.txt")
    IO.puts("")

    IO.puts(
      "⚠️  IMPORTANT: Keep the pkce_params.txt file secure - it's needed for token exchange!"
    )

  {:error, reason} ->
    IO.puts("❌ Failed to generate OAuth URL: #{inspect(reason)}")
end

# Show how to use the authorization code
IO.puts("")
IO.puts("🔄 WHEN YOU GET THE AUTHORIZATION CODE:")
IO.puts("Run this in IEx to exchange for tokens:")
IO.puts(~S|mix run -e "|)
IO.puts(~S|  # Load PKCE params|)
IO.puts(~S|  pkce_content = File.read!('pkce_params.txt')|)
IO.puts(~S|  # Extract values and create pkce_params struct|)
IO.puts(~S|  # Then: TheMaestro.Auth.exchange_code_for_tokens(auth_code, pkce_params)|)
IO.puts(~S|"|)
