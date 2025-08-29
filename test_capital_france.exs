#!/usr/bin/env elixir

# FINAL OAUTH TEST: Ask "What is the capital of France?" and get successful answer
IO.puts("🎯 FINAL OAUTH TEST: Capital of France Question")
IO.puts("")

case TheMaestro.Providers.Client.build_client(:anthropic, :oauth) do
  client when not is_tuple(client) ->
    IO.puts("✅ OAuth client created successfully")

    # Test request asking about capital of France
    test_request = %{
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 100,
      system: "You are Claude Code, Anthropic's official CLI for Claude.",
      messages: [
        %{
          role: "user",
          content: "What is the capital of France?"
        }
      ]
    }

    IO.puts("❓ Asking: What is the capital of France?")

    case Tesla.post(client, "/v1/messages", test_request) do
      {:ok, %{status: 200, body: response_body}} ->
        IO.puts("🎉 SUCCESS! OAuth Bearer authentication is WORKING!")
        IO.puts("   Status: 200 OK")

        # Extract and display the answer
        if is_map(response_body) && response_body["content"] do
          content =
            response_body["content"]
            |> List.first()
            |> Map.get("text", "No text content")

          IO.puts("   📍 Claude's Answer: \"#{content}\"")

          # Check if the answer contains "Paris"
          if String.contains?(String.downcase(content), "paris") do
            IO.puts("✅ CORRECT ANSWER RECEIVED!")
            IO.puts("🏆 OAUTH IMPLEMENTATION COMPLETE AND WORKING!")
            IO.puts("")
            IO.puts("✅ All validation criteria met:")
            IO.puts("   ✓ OAuth client created successfully")
            IO.puts("   ✓ Bearer token authentication working (200 OK)")
            IO.puts("   ✓ Claude Code system prompt working")
            IO.puts("   ✓ Gzipped response handling working")
            IO.puts("   ✓ Real AI response received and parsed")
            IO.puts("   ✓ Correct answer to test question")
          else
            IO.puts("⚠️  Unexpected answer - should mention Paris")
          end
        else
          IO.puts("❌ No content in response body")
          IO.puts("   Response: #{inspect(response_body)}")
        end

      {:ok, %{status: status, body: error_body}} ->
        IO.puts("❌ API call failed with status: #{status}")

        if is_map(error_body) && error_body["error"] do
          IO.puts("   Error: #{error_body["error"]["message"]}")
        else
          IO.puts("   Response: #{inspect(error_body)}")
        end

      {:error, reason} ->
        IO.puts("❌ Request failed: #{inspect(reason)}")
    end

  {:error, reason} ->
    IO.puts("❌ Failed to create OAuth client: #{inspect(reason)}")
end
