# DEBUG: Why is OAuth returning 401? This is UNACCEPTABLE for QA

IO.puts("🚨 CRITICAL QA FAILURE: 401 Invalid Bearer Token")
IO.puts("🔍 Debugging OAuth implementation...")
IO.puts("")

# Generate fresh OAuth URL and show the ACTUAL parameters
{:ok, {url, pkce_params}} = TheMaestro.Auth.generate_oauth_url()

IO.puts("🔗 FRESH OAuth URL (decode and examine):")
%URI{query: query} = URI.parse(url)
decoded_params = URI.decode_query(query)

IO.puts("📋 OAuth Parameters:")
Enum.each(decoded_params, fn {key, value} ->
  IO.puts("   #{key}: #{value}")
end)
IO.puts("")

IO.puts("🔑 PKCE Parameters:")
IO.puts("   code_verifier: #{String.slice(pkce_params.code_verifier, 0, 20)}...")
IO.puts("   code_challenge: #{String.slice(pkce_params.code_challenge, 0, 20)}...")  
IO.puts("   code_challenge_method: #{pkce_params.code_challenge_method}")
IO.puts("")

IO.puts("⚠️  CRITICAL ISSUES TO CHECK:")
IO.puts("1. Is the authorization code format wrong?")
IO.puts("2. Is the token endpoint returning test/invalid tokens?")  
IO.puts("3. Are the Bearer token headers incorrect?")
IO.puts("4. Is there a mismatch between OAuth scopes and API requirements?")
IO.puts("")

IO.puts("📄 Expected vs Actual Token Analysis:")
IO.puts("Expected token format: sk-ant-oat01-... (OAuth access token)")
IO.puts("Expected response: 200 OK with real Claude response")
IO.puts("Actual response: 401 Invalid bearer token")
IO.puts("")

IO.puts("🔧 Next Steps:")
IO.puts("1. Re-authorize with fresh URL above")  
IO.puts("2. Verify token exchange response")
IO.puts("3. Test API call immediately after token exchange")
IO.puts("4. If still 401, the OAuth implementation is BROKEN")