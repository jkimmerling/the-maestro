# Story 7.3: Provider-Specific Prompt Optimization

## User Story
**As an** Agent,  
**I want** intelligent prompt optimization tailored to different LLM providers and their specific capabilities,  
**so that** I can achieve optimal performance and response quality across Claude, Gemini, and ChatGPT.

## Acceptance Criteria

### Provider Optimization Architecture
1. **Provider Optimization Engine**: Comprehensive provider-specific optimization:
   ```elixir
   defmodule TheMaestro.Prompts.ProviderOptimizer do
     @providers %{
       anthropic: TheMaestro.Prompts.Optimizers.AnthropicOptimizer,
       google: TheMaestro.Prompts.Optimizers.GoogleOptimizer,
       openai: TheMaestro.Prompts.Optimizers.OpenAIOptimizer
     }
     
     def optimize_for_provider(enhanced_prompt, provider_info, optimization_config \\ %{}) do
       optimizer_module = @providers[provider_info.provider]
       
       if optimizer_module do
         %OptimizationContext{
           enhanced_prompt: enhanced_prompt,
           provider_info: provider_info,
           model_capabilities: get_model_capabilities(provider_info),
           optimization_targets: determine_optimization_targets(optimization_config),
           performance_constraints: get_performance_constraints(provider_info),
           quality_requirements: get_quality_requirements(optimization_config)
         }
         |> optimizer_module.optimize()
         |> validate_optimization_results()
       else
         apply_generic_optimization(enhanced_prompt, provider_info)
       end
     end
   end
   ```

2. **Model Capability Detection**: Dynamic capability assessment:
   ```elixir
   def get_model_capabilities(provider_info) do
     base_capabilities = get_base_model_capabilities(provider_info.provider, provider_info.model)
     
     %ModelCapabilities{
       context_window: base_capabilities.context_window,
       supports_function_calling: base_capabilities.supports_function_calling,
       supports_multimodal: base_capabilities.supports_multimodal,
       supports_structured_output: base_capabilities.supports_structured_output,
       supports_streaming: base_capabilities.supports_streaming,
       reasoning_strength: base_capabilities.reasoning_strength,
       code_understanding: base_capabilities.code_understanding,
       language_capabilities: base_capabilities.language_capabilities,
       safety_filtering: base_capabilities.safety_filtering,
       latency_characteristics: base_capabilities.latency_characteristics,
       cost_characteristics: base_capabilities.cost_characteristics,
       
       # Dynamic capability detection
       actual_context_utilization: measure_context_utilization(provider_info),
       function_calling_reliability: measure_function_calling_reliability(provider_info),
       response_consistency: measure_response_consistency(provider_info)
     }
   end
   ```

### Anthropic/Claude Optimization
3. **Claude-Specific Optimization**: Leverage Claude's unique strengths:
   ```elixir
   defmodule TheMaestro.Prompts.Optimizers.AnthropicOptimizer do
     @claude_strengths %{
       reasoning: :excellent,
       code_understanding: :excellent,
       context_utilization: :excellent,
       safety_awareness: :excellent,
       instruction_following: :excellent,
       structured_thinking: :excellent
     }
     
     def optimize(optimization_context) do
       optimization_context
       |> leverage_reasoning_capabilities()
       |> optimize_for_large_context()
       |> enhance_instruction_clarity()
       |> utilize_structured_thinking_patterns()
       |> optimize_safety_considerations()
       |> format_for_claude_preferences()
     end
     
     defp leverage_reasoning_capabilities(context) do
       if complex_reasoning_required?(context.enhanced_prompt) do
         context
         |> add_thinking_framework()
         |> encourage_step_by_step_analysis()
         |> add_reasoning_validation_prompts()
       else
         context
       end
     end
     
     defp optimize_for_large_context(context) do
       if exceeds_token_threshold?(context.enhanced_prompt, 50_000) do
         context
         |> add_context_navigation_aids()
         |> implement_hierarchical_information_structure()
         |> add_context_summarization_requests()
       else
         context
       end
     end
     
     defp add_thinking_framework(context) do
       thinking_prompt = """
       
       Please approach this systematically:
       1. First, analyze the current situation and requirements
       2. Consider multiple approaches and their trade-offs  
       3. Choose the best approach and explain your reasoning
       4. Implement the solution step by step
       5. Validate the results and suggest improvements
       """
       
       update_in(context.enhanced_prompt.enhanced_prompt, &(&1 <> thinking_prompt))
     end
   end
   ```

4. **Claude Context Window Optimization**: Maximize context utilization:
   ```elixir
   def optimize_claude_context_usage(enhanced_prompt, model_info) do
     max_context = get_claude_context_limit(model_info.model)
     current_usage = estimate_token_count(enhanced_prompt)
     
     cond do
       current_usage < max_context * 0.6 ->
         # Plenty of room, can add more context
         enhanced_prompt
         |> add_detailed_examples()
         |> include_comprehensive_documentation()
         |> add_alternative_approaches()
         
       current_usage < max_context * 0.85 ->
         # Moderate usage, optimize for quality
         enhanced_prompt
         |> prioritize_most_relevant_context()
         |> add_focused_examples()
         
       true ->
         # High usage, must compress
         enhanced_prompt
         |> compress_redundant_information()
         |> prioritize_essential_context_only()
         |> use_reference_based_context()
     end
   end
   ```

### Google/Gemini Optimization
5. **Gemini-Specific Optimization**: Leverage Gemini's capabilities:
   ```elixir
   defmodule TheMaestro.Prompts.Optimizers.GoogleOptimizer do
     @gemini_strengths %{
       multimodal: :excellent,
       function_calling: :excellent,
       code_generation: :excellent,
       reasoning: :very_good,
       context_window: :very_large,
       integration_capabilities: :excellent
     }
     
     def optimize(optimization_context) do
       optimization_context
       |> optimize_for_multimodal_capabilities()
       |> enhance_function_calling_integration()
       |> optimize_for_code_generation()
       |> leverage_large_context_window()
       |> integrate_google_services_context()
       |> format_for_gemini_preferences()
     end
     
     defp optimize_for_multimodal_capabilities(context) do
       if has_visual_elements?(context.enhanced_prompt) do
         context
         |> add_visual_analysis_instructions()
         |> optimize_image_description_requests()
         |> enhance_visual_reasoning_prompts()
       else
         context
       end
     end
     
     defp enhance_function_calling_integration(context) do
       available_tools = extract_available_tools(context)
       
       if length(available_tools) > 0 do
         context
         |> add_tool_usage_optimization()
         |> enhance_parameter_validation()
         |> add_tool_chaining_suggestions()
         |> optimize_tool_selection_logic()
       else
         context
       end
     end
   end
   ```

6. **Gemini Function Calling Optimization**: Optimize tool integration:
   ```elixir
   def optimize_gemini_function_calling(enhanced_prompt, available_tools) do
     tool_optimization = %{
       tool_selection_guidance: generate_tool_selection_guidance(available_tools),
       parameter_optimization: optimize_tool_parameters(available_tools),
       chaining_opportunities: identify_tool_chaining_opportunities(available_tools),
       error_handling: generate_tool_error_handling_guidance(available_tools)
     }
     
     """
     #{enhanced_prompt.enhanced_prompt}
     
     ## Tool Usage Optimization
     
     #{tool_optimization.tool_selection_guidance}
     
     ### Available Tools
     #{format_tools_for_gemini(available_tools)}
     
     ### Tool Usage Guidelines
     - Consider tool chaining opportunities: #{tool_optimization.chaining_opportunities}
     - Validate parameters carefully: #{tool_optimization.parameter_optimization}
     - Handle errors gracefully: #{tool_optimization.error_handling}
     """
   end
   ```

### OpenAI/ChatGPT Optimization
7. **ChatGPT-Specific Optimization**: Leverage GPT capabilities:
   ```elixir
   defmodule TheMaestro.Prompts.Optimizers.OpenAIOptimizer do
     @gpt_strengths %{
       general_reasoning: :excellent,
       language_understanding: :excellent,
       creative_tasks: :excellent,
       consistency: :excellent,
       api_reliability: :excellent,
       structured_output: :good
     }
     
     def optimize(optimization_context) do
       optimization_context
       |> optimize_for_consistent_reasoning()
       |> enhance_structured_output_requests()
       |> optimize_for_api_reliability()
       |> leverage_strong_language_capabilities()
       |> optimize_creative_and_analytical_balance()
       |> format_for_openai_preferences()
     end
     
     defp optimize_for_consistent_reasoning(context) do
       context
       |> add_consistency_checks()
       |> implement_reasoning_validation()
       |> add_output_format_specifications()
       |> enhance_error_detection_prompts()
     end
     
     defp enhance_structured_output_requests(context) do
       if requires_structured_output?(context.enhanced_prompt) do
         context
         |> add_json_schema_specifications()
         |> add_output_format_examples()
         |> add_validation_instructions()
       else
         context
       end
     end
   end
   ```

8. **GPT Token Optimization**: Efficient token usage for GPT models:
   ```elixir
   def optimize_gpt_token_usage(enhanced_prompt, model_info) do
     token_limit = get_gpt_token_limit(model_info.model)
     current_tokens = estimate_gpt_tokens(enhanced_prompt)
     
     optimization_strategies = [
       :compress_repetitive_content,
       :use_abbreviations_for_common_terms,
       :optimize_example_selection,
       :streamline_instruction_language,
       :prioritize_essential_context
     ]
     
     if current_tokens > token_limit * 0.8 do
       Enum.reduce(optimization_strategies, enhanced_prompt, fn strategy, prompt ->
         apply_optimization_strategy(strategy, prompt, token_limit - current_tokens)
       end)
     else
       enhanced_prompt
     end
   end
   ```

### Cross-Provider Optimization Strategies
9. **Universal Optimization Patterns**: Cross-provider improvements:
   ```elixir
   defmodule TheMaestro.Prompts.Optimizers.Universal do
     def apply_universal_optimizations(enhanced_prompt, provider_info) do
       enhanced_prompt
       |> optimize_instruction_clarity()
       |> enhance_context_organization()
       |> optimize_example_selection()
       |> improve_task_decomposition()
       |> add_quality_validation_prompts()
       |> optimize_output_format_requests()
     end
     
     defp optimize_instruction_clarity(enhanced_prompt) do
       enhanced_prompt
       |> use_active_voice()
       |> eliminate_ambiguous_language()
       |> add_clear_task_boundaries()
       |> specify_expected_outputs()
       |> add_constraint_clarifications()
     end
     
     defp enhance_context_organization(enhanced_prompt) do
       enhanced_prompt
       |> implement_hierarchical_structure()
       |> add_section_headers()
       |> use_consistent_formatting()
       |> optimize_information_flow()
       |> add_reference_aids()
     end
   end
   ```

10. **Performance-Based Optimization**: Optimize based on performance metrics:
    ```elixir
    def apply_performance_based_optimization(enhanced_prompt, provider_info, performance_history) do
      optimization_decisions = %{
        token_optimization: should_optimize_tokens?(performance_history),
        latency_optimization: should_optimize_latency?(performance_history),
        quality_optimization: should_optimize_quality?(performance_history),
        cost_optimization: should_optimize_cost?(performance_history)
      }
      
      enhanced_prompt
      |> apply_conditional_optimization(:token, optimization_decisions.token_optimization)
      |> apply_conditional_optimization(:latency, optimization_decisions.latency_optimization)
      |> apply_conditional_optimization(:quality, optimization_decisions.quality_optimization)
      |> apply_conditional_optimization(:cost, optimization_decisions.cost_optimization)
    end
    ```

### Dynamic Optimization Adaptation
11. **Adaptive Optimization**: Learn from interaction patterns:
    ```elixir
    defmodule TheMaestro.Prompts.AdaptiveOptimizer do
      def adapt_optimization_strategy(provider_info, interaction_history) do
        patterns = analyze_interaction_patterns(interaction_history)
        
        %AdaptationStrategy{
          preferred_instruction_style: patterns.effective_instruction_styles,
          optimal_context_length: patterns.optimal_context_lengths,
          effective_example_types: patterns.effective_example_types,
          successful_reasoning_patterns: patterns.successful_reasoning_patterns,
          error_prevention_strategies: patterns.error_prevention_strategies
        }
        |> validate_adaptation_effectiveness()
        |> store_adaptation_strategy(provider_info)
      end
      
      defp analyze_interaction_patterns(history) do
        %InteractionPatterns{
          effective_instruction_styles: identify_effective_styles(history),
          optimal_context_lengths: calculate_optimal_lengths(history),
          effective_example_types: classify_effective_examples(history),
          successful_reasoning_patterns: extract_reasoning_patterns(history),
          error_prevention_strategies: identify_error_patterns(history)
        }
      end
    end
    ```

12. **A/B Testing Integration**: Continuous optimization improvement:
    ```elixir
    def integrate_ab_testing_optimization(enhanced_prompt, provider_info) do
      active_experiments = get_active_experiments(provider_info)
      
      Enum.reduce(active_experiments, enhanced_prompt, fn experiment, current_prompt ->
        if should_apply_experiment?(experiment, current_prompt) do
          apply_experimental_optimization(current_prompt, experiment)
        else
          current_prompt
        end
      end)
      |> track_experiment_application(active_experiments)
    end
    ```

### Quality and Performance Monitoring
13. **Optimization Effectiveness Tracking**: Monitor optimization results:
    ```elixir
    def track_optimization_effectiveness(original_prompt, optimized_prompt, provider_info, response_data) do
      metrics = %{
        token_reduction: calculate_token_reduction(original_prompt, optimized_prompt),
        response_quality_improvement: measure_quality_improvement(response_data),
        latency_impact: measure_latency_impact(response_data),
        error_rate_change: measure_error_rate_change(response_data),
        user_satisfaction_delta: measure_satisfaction_delta(response_data)
      }
      
      :telemetry.execute(
        [:maestro, :prompt_optimization], 
        metrics, 
        %{provider: provider_info.provider, model: provider_info.model}
      )
      
      # Store results for adaptive learning
      store_optimization_results(provider_info, metrics)
    end
    ```

14. **Performance Regression Detection**: Detect optimization issues:
    ```elixir
    def detect_optimization_regression(current_metrics, historical_baseline) do
      regression_indicators = %{
        quality_regression: current_metrics.quality_score < historical_baseline.quality_score * 0.95,
        latency_regression: current_metrics.response_time > historical_baseline.response_time * 1.2,
        error_rate_increase: current_metrics.error_rate > historical_baseline.error_rate * 1.5,
        token_inefficiency: current_metrics.token_usage > historical_baseline.token_usage * 1.3
      }
      
      if any_regression?(regression_indicators) do
        trigger_optimization_review(current_metrics, historical_baseline, regression_indicators)
      end
    end
    ```

### Provider-Specific Configuration
15. **Configuration Management**: Provider-specific settings:
    ```elixir
    config :the_maestro, :prompt_optimization,
      anthropic: %{
        max_context_utilization: 0.9,
        reasoning_enhancement: true,
        structured_thinking: true,
        safety_optimization: true,
        context_navigation: true
      },
      google: %{
        multimodal_optimization: true,
        function_calling_enhancement: true,
        large_context_utilization: 0.85,
        integration_optimization: true,
        visual_reasoning: true
      },
      openai: %{
        consistency_optimization: true,
        structured_output_enhancement: true,
        token_efficiency_priority: :high,
        reliability_optimization: true,
        format_specification: true
      }
    ```

16. **Dynamic Configuration Updates**: Runtime configuration adaptation:
    ```elixir
    def update_provider_optimization_config(provider, performance_data) do
      current_config = get_current_optimization_config(provider)
      
      optimization_adjustments = analyze_performance_for_config_updates(performance_data)
      
      updated_config = apply_config_adjustments(current_config, optimization_adjustments)
      
      if validate_config_update_safety(updated_config) do
        store_updated_config(provider, updated_config)
        notify_optimization_config_update(provider, updated_config)
      end
    end
    ```

## Technical Implementation

### Optimization Module Structure
```elixir
lib/the_maestro/prompts/optimization/
├── provider_optimizer.ex      # Main optimization coordinator
├── providers/
│   ├── anthropic_optimizer.ex # Claude-specific optimization
│   ├── google_optimizer.ex    # Gemini-specific optimization
│   ├── openai_optimizer.ex    # GPT-specific optimization
│   └── universal_optimizer.ex # Cross-provider optimization
├── strategies/
│   ├── token_optimizer.ex     # Token usage optimization
│   ├── context_optimizer.ex   # Context organization optimization
│   ├── quality_optimizer.ex   # Response quality optimization
│   └── performance_optimizer.ex # Performance optimization
├── adaptation/
│   ├── adaptive_optimizer.ex  # Learning-based optimization
│   ├── ab_testing.ex         # A/B testing integration
│   └── pattern_analyzer.ex   # Interaction pattern analysis
├── monitoring/
│   ├── effectiveness_tracker.ex # Optimization effectiveness tracking
│   └── regression_detector.ex   # Performance regression detection
└── config/
    ├── provider_configs.ex    # Provider-specific configurations
    └── dynamic_config.ex      # Runtime configuration updates
```

### Integration and Testing
17. **Integration Testing**: Comprehensive provider testing:
    - Provider-specific optimization validation
    - Cross-provider consistency testing
    - Performance impact measurement
    - Quality improvement verification
    - Regression testing

18. **Performance Benchmarking**: Optimization effectiveness measurement:
    - Response quality metrics
    - Token efficiency measurements
    - Latency impact analysis
    - Cost optimization tracking
    - User satisfaction metrics

## Dependencies
- Stories 7.1 and 7.2 (System Instructions and Context Enhancement)
- Provider system from Epic 5
- Performance monitoring and metrics systems
- A/B testing infrastructure

## Definition of Done
- [ ] Provider-specific optimization engines implemented for all providers
- [ ] Model capability detection and adaptation working
- [ ] Cross-provider universal optimizations functional
- [ ] Adaptive optimization based on interaction patterns
- [ ] A/B testing integration for continuous improvement
- [ ] Performance and quality monitoring systems
- [ ] Dynamic configuration management implemented
- [ ] Regression detection and alerting operational
- [ ] Integration with existing prompt enhancement systems
- [ ] Comprehensive testing across all providers
- [ ] Performance benchmarks established
- [ ] Documentation and optimization guides created
- [ ] Tutorial created in `tutorials/epic7/story7.3/`