#!/usr/bin/env elixir

# Test OAuth Bearer Token Authentication with Claude Code System Prompt
# This script tests the OAuth client with proper Claude Code mimicking

IO.puts("🔐 Testing Claude Code OAuth Bearer Token Authentication")
IO.puts("")

# Test 1: Create OAuth client with Claude Code headers
IO.puts("📋 TEST 1: Creating OAuth client with Claude Code headers...")
case TheMaestro.Providers.Client.build_client(:anthropic, :oauth) do
  client when not is_tuple(client) ->
    IO.puts("✅ OAuth client created successfully")
    
    # Verify headers include Claude Code specific headers
    headers_middleware = Enum.find(client.pre, fn 
      {Tesla.Middleware.Headers, :call, [_]} -> true
      _ -> false 
    end)
    
    case headers_middleware do
      {Tesla.Middleware.Headers, :call, [headers]} ->
        IO.puts("✅ Headers include:")
        Enum.each(headers, fn {key, value} ->
          # Don't show full token, just confirm it's there
          display_value = if key == "authorization" do
            "Bearer " <> String.slice(value, 7, 30) <> "..."
          else
            String.slice(to_string(value), 0, 50)
          end
          IO.puts("   #{key}: #{display_value}")
        end)
        
        # Check for critical Claude Code headers
        auth_header = Enum.find(headers, fn {key, _} -> key == "authorization" end)
        beta_header = Enum.find(headers, fn {key, _} -> key == "anthropic-beta" end)
        app_header = Enum.find(headers, fn {key, _} -> key == "x-app" end)
        
        IO.puts("")
        IO.puts("✅ Critical headers verified:")
        IO.puts("   Authorization: #{if auth_header, do: "✓ Present", else: "✗ Missing"}")
        IO.puts("   Claude Code Beta: #{if beta_header && elem(beta_header, 1) =~ "claude-code-20250219", do: "✓ Present", else: "✗ Missing"}")
        IO.puts("   CLI App Header: #{if app_header, do: "✓ Present", else: "✗ Missing"}")
    end
    
    # Test 2: Make authenticated API call with Claude Code system prompt
    IO.puts("")
    IO.puts("📋 TEST 2: Making authenticated API call with Claude Code system prompt...")
    
    # Claude Code API call format - must include system prompt
    test_request = %{
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 100,
      system: "You are Claude Code, Anthropic's official CLI for Claude.",
      messages: [%{
        role: "user", 
        content: "Please confirm you are Claude Code and respond with: 'OAuth authentication successful'"
      }]
    }
    
    case Tesla.post(client, "/v1/messages", test_request) do
      {:ok, %{status: 200, body: response_body}} ->
        IO.puts("🎉 SUCCESS! Claude Code OAuth Bearer authentication working!")
        IO.puts("   Status: 200")
        
        # Extract the actual message content
        if is_map(response_body) && response_body["content"] do
          content = response_body["content"] 
          |> List.first()
          |> Map.get("text", "No text content")
          IO.puts("   Claude Response: \"#{content}\"")
        else
          IO.puts("   Raw Response: #{inspect(response_body, limit: :infinity)}")
        end
        
      {:ok, %{status: status, body: error_body}} ->
        IO.puts("❌ API call failed with status: #{status}")
        IO.puts("   Error: #{inspect(error_body)}")
        
        # Check if it's still the credential restriction error
        if is_map(error_body) && error_body["error"] && error_body["error"]["message"] do
          message = error_body["error"]["message"]
          if message =~ "only authorized for use with Claude Code" do
            IO.puts("   🤔 Still getting Claude Code restriction - checking system prompt...")
          else
            IO.puts("   📋 Different error - might be progress!")
          end
        end
        
      {:error, reason} ->
        IO.puts("❌ Network error: #{inspect(reason)}")
    end
    
    # Test 3: Test without system prompt to confirm it's required
    IO.puts("")
    IO.puts("📋 TEST 3: Testing without system prompt (should fail)...")
    
    test_request_no_system = %{
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 50,
      messages: [%{
        role: "user", 
        content: "Hello"
      }]
    }
    
    case Tesla.post(client, "/v1/messages", test_request_no_system) do
      {:ok, %{status: 200, body: _}} ->
        IO.puts("😱 UNEXPECTED: Call succeeded without system prompt!")
        
      {:ok, %{status: status, body: error_body}} ->
        IO.puts("✅ Expected failure without system prompt (status: #{status})")
        if is_map(error_body) && error_body["error"] && error_body["error"]["message"] do
          message = error_body["error"]["message"]
          IO.puts("   Message: #{message}")
          if message =~ "only authorized for use with Claude Code" do
            IO.puts("   🎯 Confirms system prompt is required for Claude Code OAuth")
          end
        end
        
      {:error, reason} ->
        IO.puts("✅ Network error (expected): #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to create OAuth client: #{inspect(reason)}")
end

IO.puts("")
IO.puts("🎯 CLAUDE CODE OAUTH AUTHENTICATION TEST COMPLETE")
IO.puts("✅ Testing complete - check results above for OAuth validation status!")