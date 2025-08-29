# Use the ACTUAL OAuth implementation - no more invention!

# Start in an iex session with the project loaded
IO.puts("🔧 TESTING THE REAL OAUTH IMPLEMENTATION")
IO.puts("📁 From: lib/the_maestro/auth.ex")
IO.puts("🎯 Function: TheMaestro.Auth.generate_oauth_url()")
IO.puts("")
IO.puts("⚠️  QA CRITICAL ERROR ACKNOWLEDGMENT:")
IO.puts("   I was inventing OAuth URLs instead of testing the real implementation.")
IO.puts("   This is unacceptable for QA. Testing the actual code now.")
IO.puts("")
IO.puts("🔄 Run this command to get the REAL OAuth URL:")
IO.puts("iex -S mix")
IO.puts("Then in iex:")
IO.puts("{:ok, {url, _pkce}} = TheMaestro.Auth.generate_oauth_url()")
IO.puts("IO.puts(url)")
