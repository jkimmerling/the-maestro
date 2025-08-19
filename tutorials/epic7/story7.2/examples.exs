# Contextual Prompt Enhancement Pipeline - Practical Examples
# Run with: elixir tutorials/epic7/story7.2/examples.exs

defmodule PipelineExamples do
  alias TheMaestro.Prompts.Enhancement.Pipeline

  def run_examples do
    IO.puts("🚀 Contextual Prompt Enhancement Pipeline Examples\n")
    
    # Example 1: Software Engineering Task
    example_1()
    
    # Example 2: Learning Question  
    example_2()
    
    # Example 3: API Development
    example_3()
    
    # Example 4: Performance Analysis
    example_4()
  end

  defp example_1 do
    IO.puts("📋 Example 1: Software Engineering Task")
    IO.puts(String.duplicate("=", 50))
    
    prompt = "Fix the authentication bug in the user service"
    context = %{
      working_directory: "/app/src/services",
      operating_system: "Darwin",
      project_type: "elixir_phoenix"
    }
    
    IO.puts("Input Prompt: #{prompt}")
    IO.puts("User Context: #{inspect(context, pretty: true)}")
    IO.puts("")
    
    result = Pipeline.enhance_prompt(prompt, context)
    
    IO.puts("Enhanced Output:")
    IO.puts("Pre-Context:")
    IO.puts(result.pre_context)
    IO.puts("\nEnhanced Prompt: #{result.enhanced_prompt}")
    IO.puts("\nMetadata: #{inspect(result.metadata, pretty: true)}")
    IO.puts("\n" <> String.duplicate("-", 50) <> "\n")
  end

  defp example_2 do
    IO.puts("🎓 Example 2: Learning Question")
    IO.puts(String.duplicate("=", 50))
    
    prompt = "How do GenServers work in Elixir?"
    context = %{
      working_directory: "/learning",
      user_level: "intermediate"
    }
    
    IO.puts("Input Prompt: #{prompt}")
    IO.puts("User Context: #{inspect(context, pretty: true)}")
    IO.puts("")
    
    result = Pipeline.enhance_prompt(prompt, context)
    
    IO.puts("Enhanced Output:")
    IO.puts("Pre-Context:")
    IO.puts(result.pre_context)
    IO.puts("\nEnhanced Prompt: #{result.enhanced_prompt}")
    IO.puts("\nProcessing Time: #{result.metadata.processing_time_ms}ms")
    IO.puts("\n" <> String.duplicate("-", 50) <> "\n")
  end

  defp example_3 do
    IO.puts("🔗 Example 3: API Development")
    IO.puts(String.duplicate("=", 50))
    
    prompt = "Create a REST API endpoint for user registration"
    context = %{
      working_directory: "/api",
      project_type: "phoenix",
      database: "postgresql",
      authentication: "guardian"
    }
    
    IO.puts("Input Prompt: #{prompt}")
    IO.puts("User Context: #{inspect(context, pretty: true)}")
    IO.puts("")
    
    result = Pipeline.enhance_prompt(prompt, context)
    
    IO.puts("Enhanced Output:")
    IO.puts("Pre-Context:")
    IO.puts(result.pre_context)
    IO.puts("\nIntent Type: #{result.metadata.intent.type}")
    IO.puts("Complexity: #{result.metadata.complexity}")
    IO.puts("Context Sources: #{inspect(result.metadata.context_sources)}")
    IO.puts("\n" <> String.duplicate("-", 50) <> "\n")
  end

  defp example_4 do
    IO.puts("⚡ Example 4: Performance Comparison")
    IO.puts(String.duplicate("=", 50))
    
    prompts = [
      "Fix bug",
      "Create a comprehensive microservices architecture", 
      "How does OTP work?",
      "Add user authentication with OAuth2"
    ]
    
    IO.puts("Testing multiple prompts for performance...")
    IO.puts("")
    
    results = Enum.map(prompts, fn prompt ->
      start_time = System.monotonic_time(:millisecond)
      result = Pipeline.enhance_prompt(prompt, %{})
      end_time = System.monotonic_time(:millisecond)
      
      {prompt, result, end_time - start_time}
    end)
    
    Enum.each(results, fn {prompt, result, duration} ->
      IO.puts("Prompt: \"#{prompt}\"")
      IO.puts("Complexity: #{result.metadata.complexity}")
      IO.puts("Processing Time: #{duration}ms")
      IO.puts("Context Sources: #{length(result.metadata.context_sources)}")
      IO.puts("")
    end)
    
    avg_time = results |> Enum.map(fn {_, _, time} -> time end) |> Enum.sum() |> div(length(results))
    IO.puts("Average Processing Time: #{avg_time}ms")
    IO.puts(String.duplicate("-", 50))
  end
end

# Run examples if this file is executed directly
if System.argv() |> List.first() != "test" do
  PipelineExamples.run_examples()
end