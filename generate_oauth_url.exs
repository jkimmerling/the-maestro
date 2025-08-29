# Generate OAuth URL using THE ACTUAL IMPLEMENTATION - not invented garbage

# Load the actual project mix file and start the app
Code.require_file("mix.exs")
Mix.Task.run("app.start")

# Use the REAL generate_oauth_url() function from the actual Auth module
{:ok, {url, pkce_params}} = TheMaestro.Auth.generate_oauth_url()

IO.puts("\n🔧 USING ACTUAL AUTH MODULE IMPLEMENTATION")
IO.puts("📁 From: lib/the_maestro/auth.ex")
IO.puts("🎯 Function: TheMaestro.Auth.generate_oauth_url()")

IO.puts("\n🔗 OAUTH AUTHORIZATION URL:")
IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
IO.puts(url)
IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

IO.puts("\n📋 INSTRUCTIONS:")
IO.puts("1. Copy and paste the URL above into your browser")
IO.puts("2. Complete the Anthropic OAuth authorization")
IO.puts("3. Copy the authorization code from the callback URL")
IO.puts("4. Provide the code back to the QA process")

IO.puts("\n⏳ Waiting for your authorization...")
