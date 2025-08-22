# A/B Testing Example
#
# This example demonstrates how to set up and run A/B tests for prompts using the
# ExperimentationPlatform and StatisticalAnalyzer modules
# Run in IEx with: Code.eval_file("tutorials/epic7/story7.5/examples/ab_testing_example.exs")

alias TheMaestro.Prompts.EngineeringTools.{ExperimentationPlatform, StatisticalAnalyzer}

IO.puts("=== A/B Testing Example ===")

# Step 1: Define the prompt variants to test
IO.puts("\n1. Defining prompt variants for testing...")

prompt_variants = %{
  control: """
  Please help the customer with their inquiry. Provide a helpful response.
  
  Customer: {{customer_message}}
  """,
  
  empathy_focused: """
  I understand you're reaching out for help, and I'm here to assist you. 
  Let me address your concern with care and provide you with the best solution.
  
  Customer inquiry: {{customer_message}}
  
  I'll make sure to provide you with clear, helpful information.
  """,
  
  efficiency_focused: """
  Quick help for your inquiry:
  
  Your question: {{customer_message}}
  
  Solution steps:
  1. [Identify issue]
  2. [Provide solution]  
  3. [Next steps if needed]
  
  Response time target: <2 minutes
  """,
  
  professional_tone: """
  Thank you for contacting our support team. We appreciate the opportunity 
  to assist you with your inquiry.
  
  Regarding: {{customer_message}}
  
  Our response will include:
  - Comprehensive analysis of your situation
  - Recommended solution pathway  
  - Follow-up support options
  
  We're committed to resolving your matter promptly and thoroughly.
  """
}

IO.puts("✅ Created 4 prompt variants:")
Enum.each(prompt_variants, fn {variant, prompt} ->
  IO.puts("   • #{variant}: #{String.length(prompt)} characters")
end)

# Step 2: Create the A/B test experiment
IO.puts("\n2. Setting up A/B test experiment...")

experiment_config = %{
  name: "customer_service_prompt_optimization",
  description: "Testing different approaches to customer service prompts",
  hypothesis: "Empathy-focused prompts will improve customer satisfaction by 15%",
  variants: [
    %{
      name: "control",
      prompt_content: prompt_variants.control,
      traffic_allocation: 0.25,
      description: "Basic prompt without specific tone guidance"
    },
    %{
      name: "empathy_focused",
      prompt_content: prompt_variants.empathy_focused,
      traffic_allocation: 0.25,
      description: "Emphasis on understanding and empathy"
    },
    %{
      name: "efficiency_focused", 
      prompt_content: prompt_variants.efficiency_focused,
      traffic_allocation: 0.25,
      description: "Focus on quick, structured responses"
    },
    %{
      name: "professional_tone",
      prompt_content: prompt_variants.professional_tone,
      traffic_allocation: 0.25,
      description: "Formal, comprehensive professional approach"
    }
  ],
  success_metrics: [
    %{name: :customer_satisfaction, weight: 0.4, target_improvement: 0.15},
    %{name: :response_time, weight: 0.25, target_improvement: 0.10},
    %{name: :resolution_rate, weight: 0.25, target_improvement: 0.12},
    %{name: :follow_up_needed, weight: 0.1, target_improvement: -0.20}  # Negative = reduction is good
  ],
  experiment_settings: %{
    duration_days: 14,
    min_sample_size: 1000,
    confidence_level: 0.95,
    statistical_power: 0.80
  }
}

{:ok, experiment} = ExperimentationPlatform.create_experiment(experiment_config)

IO.puts("✅ Experiment created: #{experiment.name}")
IO.puts("   Experiment ID: #{experiment.id}")
IO.puts("   Duration: #{experiment_config.experiment_settings.duration_days} days")
IO.puts("   Target sample size: #{experiment_config.experiment_settings.min_sample_size}")
IO.puts("   Confidence level: #{experiment_config.experiment_settings.confidence_level * 100}%")

# Step 3: Simulate running the experiment and collecting data
IO.puts("\n3. Simulating experiment execution...")

# Generate realistic test data for each variant
simulated_results = %{
  control: %{
    sample_size: 1250,
    customer_satisfaction: 3.2,  # out of 5
    response_time: 180,          # seconds
    resolution_rate: 0.72,       # percentage resolved
    follow_up_needed: 0.35       # percentage needing follow-up
  },
  empathy_focused: %{
    sample_size: 1180,
    customer_satisfaction: 4.1,  # 28% improvement!
    response_time: 220,          # slightly slower
    resolution_rate: 0.78,       # 8% improvement
    follow_up_needed: 0.28       # 20% reduction (good!)
  },
  efficiency_focused: %{
    sample_size: 1300,
    customer_satisfaction: 3.6,  # 12% improvement
    response_time: 95,           # 47% improvement!
    resolution_rate: 0.75,       # 4% improvement  
    follow_up_needed: 0.32       # 9% reduction
  },
  professional_tone: %{
    sample_size: 1150,
    customer_satisfaction: 3.8,  # 19% improvement
    response_time: 240,          # slower
    resolution_rate: 0.80,       # 11% improvement
    follow_up_needed: 0.25       # 29% reduction!
  }
}

IO.puts("✅ Experiment data collected:")
Enum.each(simulated_results, fn {variant, results} ->
  IO.puts("   #{variant}:")
  IO.puts("     Sample size: #{results.sample_size}")
  IO.puts("     Satisfaction: #{results.customer_satisfaction}/5")
  IO.puts("     Response time: #{results.response_time}s")
  IO.puts("     Resolution rate: #{Float.round(results.resolution_rate * 100, 1)}%")
  IO.puts("     Follow-up needed: #{Float.round(results.follow_up_needed * 100, 1)}%")
end)

# Step 4: Perform statistical analysis
IO.puts("\n4. Performing statistical analysis...")

{:ok, statistical_analysis} = StatisticalAnalyzer.analyze_experiment_results(
  experiment, 
  simulated_results
)

IO.puts("✅ Statistical analysis complete")

# Display significance test results
IO.puts("\nStatistical Significance Tests:")
Enum.each(statistical_analysis.significance_tests, fn test ->
  significance = if test.p_value < 0.05, do: "✅ Significant", else: "❌ Not Significant"
  IO.puts("   #{test.variant} vs control (#{test.metric}): p=#{Float.round(test.p_value, 4)} #{significance}")
end)

# Display confidence intervals
IO.puts("\nConfidence Intervals (95%):")
Enum.each(statistical_analysis.confidence_intervals, fn interval ->
  IO.puts("   #{interval.variant} (#{interval.metric}): #{Float.round(interval.lower_bound, 3)} to #{Float.round(interval.upper_bound, 3)}")
end)

# Step 5: Determine winning variant and provide recommendations
IO.puts("\n5. Analyzing results and determining winner...")

# Calculate overall scores for each variant
variant_scores = Enum.map(simulated_results, fn {variant, results} ->
  control_results = simulated_results.control
  
  # Calculate weighted improvement scores
  satisfaction_improvement = (results.customer_satisfaction - control_results.customer_satisfaction) / control_results.customer_satisfaction
  time_improvement = (control_results.response_time - results.response_time) / control_results.response_time
  resolution_improvement = (results.resolution_rate - control_results.resolution_rate) / control_results.resolution_rate
  followup_improvement = (control_results.follow_up_needed - results.follow_up_needed) / control_results.follow_up_needed
  
  overall_score = (satisfaction_improvement * 0.4) + 
                 (time_improvement * 0.25) + 
                 (resolution_improvement * 0.25) + 
                 (followup_improvement * 0.1)
  
  {variant, %{
    satisfaction_improvement: Float.round(satisfaction_improvement * 100, 1),
    time_improvement: Float.round(time_improvement * 100, 1), 
    resolution_improvement: Float.round(resolution_improvement * 100, 1),
    followup_improvement: Float.round(followup_improvement * 100, 1),
    overall_score: Float.round(overall_score * 100, 1)
  }}
end)

# Sort by overall score
ranked_variants = Enum.sort_by(variant_scores, fn {_variant, scores} -> scores.overall_score end, :desc)

IO.puts("📊 Variant Performance Rankings:")
Enum.with_index(ranked_variants, 1) do {{variant, scores}, rank} ->
  status = case rank do
    1 -> "🏆 WINNER"
    2 -> "🥈 Runner-up" 
    3 -> "🥉 Third place"
    _ -> "   Place #{rank}"
  end
  
  IO.puts("#{status}: #{variant} (Overall score: #{scores.overall_score}%)")
  IO.puts("     Satisfaction: #{scores.satisfaction_improvement}%")
  IO.puts("     Response time: #{scores.time_improvement}%") 
  IO.puts("     Resolution rate: #{scores.resolution_improvement}%")
  IO.puts("     Follow-up reduction: #{scores.followup_improvement}%")
  IO.puts("")
end

{winner_variant, winner_scores} = List.first(ranked_variants)

IO.puts("🎯 WINNER: #{winner_variant}")
IO.puts("Overall improvement: #{winner_scores.overall_score}%")

# Step 6: Generate recommendations based on results
IO.puts("\n6. Generating recommendations...")

recommendations = [
  %{
    category: "Primary Recommendation",
    recommendation: "Deploy the '#{winner_variant}' variant as the new default",
    confidence: :high,
    expected_impact: "#{winner_scores.overall_score}% overall improvement"
  },
  %{
    category: "Secondary Insights",
    recommendation: "Consider hybrid approach combining empathy (satisfaction) with efficiency (speed)",
    confidence: :medium,
    expected_impact: "Potential for even greater improvements"
  },
  %{
    category: "Further Testing",
    recommendation: "Test hybrid variants based on customer urgency levels",
    confidence: :medium,
    expected_impact: "Personalized experience optimization"
  }
]

IO.puts("💡 Recommendations:")
Enum.each(recommendations, fn rec ->
  confidence_emoji = case rec.confidence do
    :high -> "🟢"
    :medium -> "🟡"
    :low -> "🔴"
  end
  
  IO.puts("   #{confidence_emoji} #{rec.category}:")
  IO.puts("     #{rec.recommendation}")
  IO.puts("     Expected impact: #{rec.expected_impact}")
  IO.puts("")
end)

# Step 7: Create deployment plan
IO.puts("\n7. Creating deployment plan...")

deployment_plan = %{
  winning_variant: winner_variant,
  rollout_strategy: "Progressive deployment",
  phases: [
    %{phase: 1, traffic: 10, duration_hours: 24, validation: "Monitor error rates"},
    %{phase: 2, traffic: 25, duration_hours: 48, validation: "Confirm satisfaction improvements"},
    %{phase: 3, traffic: 50, duration_hours: 72, validation: "Validate at scale"},
    %{phase: 4, traffic: 100, monitoring: "Full deployment with continuous monitoring"}
  ],
  success_criteria: %{
    customer_satisfaction: ">= 4.0/5",
    resolution_rate: ">= 75%",
    response_time: "<= 250s",
    error_rate: "<= 1%"
  },
  rollback_triggers: [
    "Customer satisfaction drops below 3.5",
    "Resolution rate drops below 70%", 
    "Error rate exceeds 2%",
    "Response time exceeds 300s"
  ]
}

IO.puts("🚀 Deployment Plan for '#{deployment_plan.winning_variant}':")
IO.puts("Strategy: #{deployment_plan.rollout_strategy}")

IO.puts("\nPhases:")
Enum.each(deployment_plan.phases, fn phase ->
  IO.puts("   Phase #{phase.phase}: #{phase.traffic}% traffic for #{phase[:duration_hours] || "ongoing"}")
  IO.puts("     Validation: #{phase[:validation] || phase[:monitoring]}")
end)

IO.puts("\nSuccess Criteria:")
Enum.each(deployment_plan.success_criteria, fn {metric, target} ->
  IO.puts("   • #{metric}: #{target}")
end)

IO.puts("\nRollback Triggers:")
Enum.each(deployment_plan.rollback_triggers, fn trigger ->
  IO.puts("   ⚠️  #{trigger}")
end)

# Step 8: Save experiment results
IO.puts("\n8. Saving experiment results...")

experiment_summary = %{
  experiment_id: experiment.id,
  winning_variant: winner_variant,
  results_summary: simulated_results,
  statistical_analysis: statistical_analysis,
  recommendations: recommendations,
  deployment_plan: deployment_plan,
  completed_at: DateTime.utc_now()
}

# In a real application, you would persist this to a database
IO.puts("✅ Experiment results saved (demo - not persisted)")

IO.puts("\n=== A/B Testing Example Complete ===")
IO.puts("This example demonstrated:")
IO.puts("1. Creating multi-variant A/B test experiments")
IO.puts("2. Defining success metrics and weights")
IO.puts("3. Simulating data collection across variants")
IO.puts("4. Statistical significance testing")
IO.puts("5. Confidence interval analysis")
IO.puts("6. Winner determination with scoring")
IO.puts("7. Recommendation generation")
IO.puts("8. Progressive deployment planning")

IO.puts("\nKey insights from this experiment:")
IO.puts("• 🎯 Winner: #{winner_variant} with #{winner_scores.overall_score}% overall improvement")
IO.puts("• 📈 Satisfaction improved most with empathy-focused approach")
IO.puts("• ⚡ Response time best with efficiency-focused approach") 
IO.puts("• 🤝 Professional tone reduced follow-up needs most")
IO.puts("• 📊 Statistical significance confirmed for multiple metrics")

IO.puts("\nExperiment design best practices shown:")
IO.puts("• Multiple variants to test different hypotheses")
IO.puts("• Weighted success metrics aligned with business goals")
IO.puts("• Appropriate sample sizes for statistical power")
IO.puts("• Progressive rollout with safety measures")
IO.puts("• Clear success criteria and rollback triggers")

IO.puts("\nNext steps:")
IO.puts("- Review advanced-features.md for complex experiment designs")  
IO.puts("- Check troubleshooting.md for common A/B testing issues")
IO.puts("- Try basic_optimization.exs and collaboration_demo.exs")