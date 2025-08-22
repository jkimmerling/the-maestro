# Basic Optimization Example
# 
# This example demonstrates how to use the OptimizationEngine to analyze and improve prompts
# Run in IEx with: Code.eval_file("tutorials/epic7/story7.5/examples/basic_optimization.exs")

alias TheMaestro.Prompts.EngineeringTools
alias TheMaestro.Prompts.EngineeringTools.{OptimizationEngine, PerformanceAnalyzer}

# Sample prompt that needs optimization
sample_prompt = """
Hello AI, I need you to help me write some content for our company website. 
We sell software and we want you to make it sound good and professional. 
Make sure it's not too long but also not too short. 
Also make it engaging for our target audience which are business people.
Can you do that for me? Thanks.
"""

IO.puts("=== Basic Optimization Example ===")
IO.puts("Original prompt:")
IO.puts(sample_prompt)
IO.puts("\nOriginal length: #{String.length(sample_prompt)} characters")

# Step 1: Initialize the engineering environment
IO.puts("\n1. Initializing engineering environment...")

{:ok, env} = EngineeringTools.initialize_engineering_environment(%{
  user_id: "demo_user",
  skill_level: :intermediate
})

IO.puts("✅ Environment initialized with user: demo_user")

# Step 2: Analyze the prompt for optimization opportunities
IO.puts("\n2. Analyzing prompt for optimization opportunities...")

{:ok, analysis} = OptimizationEngine.analyze_prompt(sample_prompt)

IO.puts("✅ Analysis complete")
IO.puts("\nAnalysis results:")
IO.puts("- Issues found: #{length(analysis.issues)}")
IO.puts("- Optimization suggestions: #{length(analysis.suggestions)}")
IO.puts("- Clarity score: #{analysis.clarity_score}")
IO.puts("- Efficiency score: #{analysis.efficiency_score}")

# Display the issues found
IO.puts("\nIssues identified:")
Enum.each(analysis.issues, fn issue ->
  IO.puts("  • [#{String.upcase(to_string(issue.severity))}] #{issue.type}: #{issue.message}")
end)

# Display optimization suggestions
IO.puts("\nOptimization suggestions:")
Enum.each(analysis.suggestions, fn suggestion ->
  priority = String.upcase(to_string(suggestion.priority))
  IO.puts("  • [#{priority}] #{suggestion.type}: #{suggestion.description}")
end)

# Step 3: Apply the optimization suggestions
IO.puts("\n3. Applying optimization suggestions...")

# Apply the top priority optimizations
high_priority_suggestions = Enum.filter(analysis.suggestions, &(&1.priority == :high))

{:ok, optimized_prompt} = OptimizationEngine.apply_optimizations(
  sample_prompt, 
  high_priority_suggestions
)

IO.puts("✅ Optimizations applied")
IO.puts("\nOptimized prompt:")
IO.puts(optimized_prompt)
IO.puts("\nOptimized length: #{String.length(optimized_prompt)} characters")

# Step 4: Compare performance metrics
IO.puts("\n4. Comparing performance metrics...")

original_performance = PerformanceAnalyzer.analyze_prompt_performance(sample_prompt)
optimized_performance = PerformanceAnalyzer.analyze_prompt_performance(optimized_prompt)

IO.puts("\nPerformance Comparison:")
IO.puts("                    Original    Optimized    Improvement")
IO.puts("Token count:        #{String.pad_leading(to_string(original_performance.token_count), 8)}    #{String.pad_leading(to_string(optimized_performance.token_count), 9)}    #{if optimized_performance.token_count < original_performance.token_count, do: "✅ Better", else: "➖ Same"}")
IO.puts("Complexity:         #{String.pad_leading(to_string(original_performance.complexity_score), 8)}    #{String.pad_leading(to_string(optimized_performance.complexity_score), 9)}    #{if optimized_performance.complexity_score < original_performance.complexity_score, do: "✅ Better", else: "➖ Same"}")
IO.puts("Clarity:            #{String.pad_leading(to_string(original_performance.clarity_score), 8)}    #{String.pad_leading(to_string(optimized_performance.clarity_score), 9)}    #{if optimized_performance.clarity_score > original_performance.clarity_score, do: "✅ Better", else: "➖ Same"}")

# Step 5: Demonstrate iterative optimization
IO.puts("\n5. Demonstrating iterative optimization...")

# Perform a second round of analysis and optimization
{:ok, second_analysis} = OptimizationEngine.analyze_prompt(optimized_prompt)

IO.puts("Second analysis results:")
IO.puts("- Issues remaining: #{length(second_analysis.issues)}")
IO.puts("- Additional suggestions: #{length(second_analysis.suggestions)}")

if length(second_analysis.suggestions) > 0 do
  IO.puts("\nApplying additional optimizations...")
  
  medium_priority_suggestions = Enum.filter(second_analysis.suggestions, &(&1.priority in [:high, :medium]))
  
  {:ok, final_optimized_prompt} = OptimizationEngine.apply_optimizations(
    optimized_prompt,
    medium_priority_suggestions
  )
  
  IO.puts("✅ Final optimization complete")
  IO.puts("\nFinal optimized prompt:")
  IO.puts(final_optimized_prompt)
  IO.puts("\nFinal length: #{String.length(final_optimized_prompt)} characters")
  
  # Final performance analysis
  final_performance = PerformanceAnalyzer.analyze_prompt_performance(final_optimized_prompt)
  
  IO.puts("\nFinal Performance Metrics:")
  IO.puts("- Token count: #{final_performance.token_count}")
  IO.puts("- Complexity: #{final_performance.complexity_score}")
  IO.puts("- Clarity: #{final_performance.clarity_score}")
  IO.puts("- Overall efficiency: #{final_performance.efficiency_score}")
  
  # Calculate total improvement
  token_improvement = ((original_performance.token_count - final_performance.token_count) / original_performance.token_count * 100) |> Float.round(1)
  clarity_improvement = ((final_performance.clarity_score - original_performance.clarity_score) / original_performance.clarity_score * 100) |> Float.round(1)
  
  IO.puts("\nTotal Improvement:")
  IO.puts("- Token reduction: #{token_improvement}%")
  IO.puts("- Clarity improvement: #{clarity_improvement}%")
else
  IO.puts("✅ No additional optimizations needed - prompt is well optimized!")
end

# Step 6: Save the optimization results for future reference
IO.puts("\n6. Saving optimization results...")

optimization_results = %{
  original_prompt: sample_prompt,
  final_prompt: optimized_prompt,
  analysis_results: analysis,
  performance_comparison: %{
    original: original_performance,
    optimized: optimized_performance
  },
  applied_optimizations: high_priority_suggestions,
  timestamp: DateTime.utc_now()
}

# In a real application, you would save this to persistent storage
IO.puts("✅ Optimization results saved (demo - not persisted)")

IO.puts("\n=== Optimization Complete ===")
IO.puts("This example demonstrated:")
IO.puts("1. Environment initialization")
IO.puts("2. Prompt analysis and issue identification")  
IO.puts("3. Optimization suggestion generation")
IO.puts("4. Optimization application")
IO.puts("5. Performance comparison")
IO.puts("6. Iterative improvement process")

IO.puts("\nKey takeaways:")
IO.puts("• Always analyze before optimizing")
IO.puts("• Apply optimizations iteratively") 
IO.puts("• Measure performance improvements")
IO.puts("• Save results for future reference")

IO.puts("\nNext steps:")
IO.puts("- Try the collaboration_demo.exs example")
IO.puts("- Experiment with ab_testing_example.exs")
IO.puts("- Read the advanced-features.md guide")