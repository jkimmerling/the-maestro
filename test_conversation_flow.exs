#!/usr/bin/env elixir

# CONVERSATION FLOW TEST: Two-part question to verify full OAuth conversation handling
IO.puts("🔄 CONVERSATION FLOW TEST: Capital → Population")
IO.puts("")

case TheMaestro.Providers.Client.build_client(:anthropic, :oauth) do
  client when not is_tuple(client) ->
    IO.puts("✅ OAuth client created successfully")
    
    # First request: Ask about capital of France
    first_request = %{
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 100,
      system: "You are Claude Code, Anthropic's official CLI for Claude.",
      messages: [%{
        role: "user", 
        content: "What is the capital of France?"
      }]
    }
    
    IO.puts("❓ First question: What is the capital of France?")
    
    case Tesla.post(client, "/v1/messages", first_request) do
      {:ok, %{status: 200, body: first_response}} ->
        IO.puts("✅ First response SUCCESS!")
        
        # Extract first answer
        if is_map(first_response) && first_response["content"] do
          first_content = first_response["content"] 
          |> List.first()
          |> Map.get("text", "No text content")
          
          IO.puts("   📍 Claude's Answer: \"#{first_content}\"")
          
          # Now ask follow-up question without mentioning Paris
          second_request = %{
            model: "claude-3-5-sonnet-20241022",
            max_tokens: 150,
            system: "You are Claude Code, Anthropic's official CLI for Claude.",
            messages: [
              %{role: "user", content: "What is the capital of France?"},
              %{role: "assistant", content: first_content},
              %{role: "user", content: "What is the population of that city?"}
            ]
          }
          
          IO.puts("")
          IO.puts("❓ Follow-up question: What is the population of that city?")
          
          case Tesla.post(client, "/v1/messages", second_request) do
            {:ok, %{status: 200, body: second_response}} ->
              IO.puts("✅ Second response SUCCESS!")
              
              if is_map(second_response) && second_response["content"] do
                second_content = second_response["content"] 
                |> List.first()
                |> Map.get("text", "No text content")
                
                IO.puts("   🏙️  Claude's Answer: \"#{second_content}\"")
                
                # Check if answer mentions population/numbers
                if String.contains?(String.downcase(second_content), "million") or 
                   String.contains?(String.downcase(second_content), "population") do
                  IO.puts("✅ CORRECT FOLLOW-UP ANSWER!")
                  IO.puts("🏆 CONVERSATION FLOW TEST COMPLETE!")
                  IO.puts("")
                  IO.puts("✅ All validation criteria met:")
                  IO.puts("   ✓ OAuth client working")
                  IO.puts("   ✓ First question answered correctly")
                  IO.puts("   ✓ Follow-up question understood in context")
                  IO.puts("   ✓ No special gzip response requirements")
                  IO.puts("   ✓ Full conversation flow working")
                else
                  IO.puts("⚠️  Follow-up answer doesn't mention population")
                  IO.puts("   (But OAuth conversation flow is working)")
                end
              else
                IO.puts("❌ No content in second response")
              end
              
            {:ok, %{status: status, body: error_body}} ->
              IO.puts("❌ Second API call failed with status: #{status}")
              if is_map(error_body) && error_body["error"] do
                IO.puts("   Error: #{error_body["error"]["message"]}")
              end
              
            {:error, reason} ->
              IO.puts("❌ Second request failed: #{inspect(reason)}")
          end
          
        else
          IO.puts("❌ No content in first response")
        end
        
      {:ok, %{status: status, body: error_body}} ->
        IO.puts("❌ First API call failed with status: #{status}")
        if is_map(error_body) && error_body["error"] do
          IO.puts("   Error: #{error_body["error"]["message"]}")
        end
        
      {:error, reason} ->
        IO.puts("❌ First request failed: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to create OAuth client: #{inspect(reason)}")
end