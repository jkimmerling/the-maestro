# Development Guide: Extending the Enhancement Pipeline

This guide covers how to extend and customize the Contextual Prompt Enhancement Pipeline for your specific needs.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Adding Custom Context Sources](#adding-custom-context-sources)
3. [Extending Intent Detection](#extending-intent-detection)
4. [Custom Relevance Scoring](#custom-relevance-scoring)
5. [Performance Optimization](#performance-optimization)
6. [Testing Your Extensions](#testing-your-extensions)

## Architecture Overview

The pipeline follows a modular, stage-based architecture where each stage can be extended or replaced:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Context         │    │ Intent           │    │ Context         │
│ Analysis        │───▶│ Detection        │───▶│ Gathering       │
│                 │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Relevance       │    │ Context          │    │ Enhancement     │
│ Scoring         │◀───│ Integration      │◀───│ Optimization    │
│                 │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │
         ▼                        ▼
┌─────────────────┐    ┌──────────────────┐
│ Quality         │    │ Prompt           │
│ Validation      │───▶│ Formatting       │
│                 │    │                  │
└─────────────────┘    └──────────────────┘
```

## Adding Custom Context Sources

### 1. Define Your Context Source Module

Create a new module that implements the context source behavior:

```elixir
defmodule MyApp.CustomContextSource do
  @moduledoc """
  Custom context source for business-specific information.
  """
  
  @doc """
  Gathers context from your custom source.
  """
  def gather_context(user_context, analysis, intent) do
    %{
      business_unit: get_business_unit(user_context),
      compliance_requirements: get_compliance_requirements(analysis),
      team_preferences: get_team_preferences(user_context),
      timestamp: DateTime.utc_now()
    }
  end
  
  @doc """
  Determines if this context source should be included.
  """
  def required_for_prompt?(analysis, intent, user_context) do
    # Include for software engineering tasks in production environment
    analysis.prompt_type == :software_engineering and
    get_in(user_context, [:environment]) == "production"
  end
  
  defp get_business_unit(user_context) do
    # Your custom logic to determine business unit
    Map.get(user_context, :business_unit, "engineering")
  end
  
  defp get_compliance_requirements(analysis) do
    # Determine compliance needs based on analysis
    case analysis.domain_indicators do
      domains when :security in domains -> ["SOC2", "GDPR"]
      domains when :financial in domains -> ["PCI", "SOX"]
      _ -> []
    end
  end
  
  defp get_team_preferences(user_context) do
    # Get team-specific preferences
    %{
      coding_style: Map.get(user_context, :coding_style, "standard"),
      review_process: Map.get(user_context, :review_process, "peer_review")
    }
  end
end
```

### 2. Register Your Context Source

Add your source to the context gatherer:

```elixir
# In your application startup or config
defmodule MyApp.EnhancementConfig do
  def configure_pipeline do
    # Register the custom context source
    TheMaestro.Prompts.Enhancement.ContextGatherer.register_source(
      :business_context,
      MyApp.CustomContextSource
    )
  end
end
```

### 3. Update Context Requirements

Modify the intent detector to include your context when relevant:

```elixir
# Add to determine_context_requirements in intent_detector.ex
defp determine_context_requirements(analysis, confidence) do
  base_requirements = get_base_requirements(analysis)
  
  # Add business context for production environments
  business_requirements = if analysis.entities |> Enum.any?(&String.contains?(&1, "production")) do
    [:business_context]
  else
    []
  end
  
  base_requirements ++ business_requirements
end
```

## Extending Intent Detection

### 1. Add New Intent Types

Extend the intent types in the structs:

```elixir
# In structs.ex, update Intent struct
defmodule Intent do
  @type intent_type :: :software_engineering | :information_seeking | 
                       :creative_writing | :general_conversation |
                       :data_analysis | :devops | :security_audit
  
  defstruct [
    :type,
    :confidence,
    :category,
    :context_requirements,
    :urgency,
    :domain_specific_flags  # New field for domain flags
  ]
end
```

### 2. Add Detection Patterns

Update the intent detection patterns:

```elixir
# In intent_detector.ex
defp intent_patterns do
  %{
    # Existing patterns...
    data_analysis: [
      ~r/(?:analyze|analysis|data|dataset|metrics|statistics)/i,
      ~r/(?:visualization|chart|graph|dashboard)/i,
      ~r/(?:sql|query|database|csv|json)/i
    ],
    devops: [
      ~r/(?:deploy|deployment|infrastructure|docker|kubernetes)/i,
      ~r/(?:ci\/cd|pipeline|automation|monitoring)/i,
      ~r/(?:aws|azure|gcp|cloud)/i
    ],
    security_audit: [
      ~r/(?:security|vulnerability|audit|penetration|threat)/i,
      ~r/(?:authentication|authorization|encryption|ssl)/i,
      ~r/(?:compliance|gdpr|hipaa|pci)/i
    ]
  }
end
```

### 3. Add Intent-Specific Logic

Update the classification logic:

```elixir
defp classify_intent(analysis, patterns, confidence_scores) do
  # Existing logic...
  
  cond do
    # New intent types
    confidence_scores[:data_analysis] > 0.7 ->
      %Intent{
        type: :data_analysis,
        category: :analysis,
        context_requirements: [:data_sources, :analysis_tools, :visualization],
        urgency: determine_urgency(analysis)
      }
    
    confidence_scores[:devops] > 0.6 ->
      %Intent{
        type: :devops,
        category: :operations,
        context_requirements: [:infrastructure, :deployment_context, :monitoring],
        urgency: determine_urgency(analysis)
      }
    
    # Existing conditions...
  end
end
```

## Custom Relevance Scoring

### 1. Implement Custom Scoring Algorithm

Create a custom relevance scorer:

```elixir
defmodule MyApp.CustomRelevanceScorer do
  @moduledoc """
  Custom relevance scoring that considers business priorities.
  """
  
  def score_context_relevance(context, analysis, intent) do
    context
    |> Enum.map(fn {source, data} ->
      score = calculate_custom_score(source, data, analysis, intent)
      {score, source, data}
    end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
  end
  
  defp calculate_custom_score(source, data, analysis, intent) do
    base_score = get_base_relevance_score(source, analysis, intent)
    business_modifier = get_business_priority_modifier(source, data)
    freshness_modifier = get_freshness_modifier(data)
    
    # Custom scoring formula
    (base_score * 0.6) + (business_modifier * 0.3) + (freshness_modifier * 0.1)
  end
  
  defp get_business_priority_modifier(:security_context, _data), do: 1.0
  defp get_business_priority_modifier(:compliance_context, _data), do: 0.9
  defp get_business_priority_modifier(:performance_context, _data), do: 0.8
  defp get_business_priority_modifier(_source, _data), do: 0.5
  
  defp get_freshness_modifier(%{timestamp: timestamp}) do
    age_hours = DateTime.diff(DateTime.utc_now(), timestamp, :hour)
    max(0.0, 1.0 - (age_hours / 24.0))  # Decay over 24 hours
  end
  defp get_freshness_modifier(_data), do: 0.5
end
```

### 2. Replace Default Scorer

Configure the pipeline to use your custom scorer:

```elixir
# In config/config.exs
config :the_maestro, :prompt_enhancement,
  relevance_scorer: MyApp.CustomRelevanceScorer,
  scoring_weights: %{
    business_priority: 0.4,
    technical_relevance: 0.3,
    freshness: 0.2,
    user_preference: 0.1
  }
```

## Performance Optimization

### 1. Add Caching Layer

Implement context caching:

```elixir
defmodule MyApp.ContextCache do
  use GenServer
  
  @cache_ttl :timer.hours(1)
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_cached_context(cache_key) do
    GenServer.call(__MODULE__, {:get, cache_key})
  end
  
  def cache_context(cache_key, context) do
    GenServer.cast(__MODULE__, {:put, cache_key, context})
  end
  
  # GenServer callbacks
  def init(_opts) do
    :ets.new(:context_cache, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end
  
  def handle_call({:get, key}, _from, state) do
    case :ets.lookup(:context_cache, key) do
      [{^key, value, expires_at}] when expires_at > :os.system_time(:millisecond) ->
        {:reply, {:ok, value}, state}
      _ ->
        {:reply, :not_found, state}
    end
  end
  
  def handle_cast({:put, key, value}, state) do
    expires_at = :os.system_time(:millisecond) + @cache_ttl
    :ets.insert(:context_cache, {key, value, expires_at})
    {:noreply, state}
  end
end
```

### 2. Parallel Context Gathering

Optimize context gathering with parallel processing:

```elixir
defmodule MyApp.ParallelContextGatherer do
  def gather_context_parallel(analysis, intent, user_context) do
    sources = determine_required_sources(analysis, intent)
    
    # Gather contexts in parallel
    sources
    |> Task.async_stream(
        fn source -> 
          {source, gather_source_context(source, user_context, analysis, intent)}
        end,
        max_concurrency: 5,
        timeout: 5000
    )
    |> Enum.reduce(%{}, fn
      {:ok, {source, context}}, acc -> Map.put(acc, source, context)
      {:error, _}, acc -> acc  # Skip failed sources
    end)
  end
end
```

### 3. Batch Processing

Add support for batch enhancement:

```elixir
defmodule MyApp.BatchEnhancer do
  def enhance_prompts_batch(prompts, user_context, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 3)
    timeout = Keyword.get(opts, :timeout, 30_000)
    
    prompts
    |> Task.async_stream(
        fn prompt -> 
          Pipeline.enhance_prompt(prompt, user_context)
        end,
        max_concurrency: concurrency,
        timeout: timeout
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:error, reason} -> %{error: reason}
    end)
  end
end
```

## Testing Your Extensions

### 1. Unit Tests for Context Sources

```elixir
defmodule MyApp.CustomContextSourceTest do
  use ExUnit.Case
  
  alias MyApp.CustomContextSource
  
  test "gathers business context correctly" do
    user_context = %{
      business_unit: "engineering",
      environment: "production"
    }
    
    analysis = %{
      prompt_type: :software_engineering,
      domain_indicators: [:security]
    }
    
    intent = %{type: :software_engineering}
    
    context = CustomContextSource.gather_context(user_context, analysis, intent)
    
    assert context.business_unit == "engineering"
    assert "SOC2" in context.compliance_requirements
  end
  
  test "determines requirement correctly" do
    analysis = %{prompt_type: :software_engineering}
    intent = %{type: :software_engineering}
    user_context = %{environment: "production"}
    
    assert CustomContextSource.required_for_prompt?(analysis, intent, user_context)
  end
end
```

### 2. Integration Tests

```elixir
defmodule MyApp.PipelineIntegrationTest do
  use ExUnit.Case
  
  test "pipeline includes custom context source" do
    # Configure pipeline with custom source
    original_sources = Application.get_env(:the_maestro, :context_sources, [])
    new_sources = [:business_context | original_sources]
    Application.put_env(:the_maestro, :context_sources, new_sources)
    
    try do
      result = Pipeline.enhance_prompt(
        "Deploy to production", 
        %{environment: "production", business_unit: "engineering"}
      )
      
      assert result.metadata.context_sources |> Enum.member?(:business_context)
      assert String.contains?(result.pre_context, "engineering")
    after
      Application.put_env(:the_maestro, :context_sources, original_sources)
    end
  end
end
```

### 3. Performance Tests

```elixir
defmodule MyApp.PerformanceBenchmark do
  use ExUnit.Case
  
  @tag :benchmark
  test "custom extensions maintain performance" do
    prompts = [
      "Fix authentication bug",
      "Deploy to production", 
      "Analyze user metrics",
      "Security audit checklist"
    ]
    
    {time_us, _results} = :timer.tc(fn ->
      Enum.map(prompts, &Pipeline.enhance_prompt(&1, %{}))
    end)
    
    avg_time_ms = time_us / 1000 / length(prompts)
    
    # Ensure average processing time under 100ms
    assert avg_time_ms < 100,
           "Average processing time #{avg_time_ms}ms exceeds 100ms threshold"
  end
end
```

### 4. Load Testing

```elixir
defmodule MyApp.LoadTest do
  def run_load_test(concurrent_requests \\ 50, duration_seconds \\ 30) do
    test_prompts = [
      "Fix the bug in authentication",
      "Create API endpoint",
      "Deploy to staging",
      "Run security scan"
    ]
    
    start_time = System.monotonic_time(:second)
    end_time = start_time + duration_seconds
    
    # Spawn concurrent processes
    tasks = for _i <- 1..concurrent_requests do
      Task.async(fn ->
        run_requests_until(end_time, test_prompts)
      end)
    end
    
    # Collect results
    results = Task.await_many(tasks, (duration_seconds + 10) * 1000)
    
    total_requests = Enum.sum(results)
    requests_per_second = total_requests / duration_seconds
    
    IO.puts("Load test results:")
    IO.puts("Total requests: #{total_requests}")
    IO.puts("Requests per second: #{requests_per_second}")
    IO.puts("Concurrent users: #{concurrent_requests}")
  end
  
  defp run_requests_until(end_time, prompts) do
    run_requests_until(end_time, prompts, 0)
  end
  
  defp run_requests_until(end_time, prompts, count) do
    if System.monotonic_time(:second) < end_time do
      prompt = Enum.random(prompts)
      Pipeline.enhance_prompt(prompt, %{})
      run_requests_until(end_time, prompts, count + 1)
    else
      count
    end
  end
end
```

## Best Practices

1. **Keep Context Sources Lightweight**: Each source should complete in <100ms
2. **Cache Expensive Operations**: Use caching for database queries or API calls
3. **Handle Failures Gracefully**: Context gathering should never crash the pipeline
4. **Test Performance Impact**: Ensure extensions don't significantly slow the pipeline
5. **Document Your Extensions**: Provide clear documentation for custom components
6. **Version Your Changes**: Use proper versioning for breaking changes

## Monitoring and Observability

Add telemetry events for your extensions:

```elixir
defmodule MyApp.EnhancementTelemetry do
  def attach do
    events = [
      [:pipeline, :context_source, :start],
      [:pipeline, :context_source, :stop],
      [:pipeline, :custom_scoring, :start],
      [:pipeline, :custom_scoring, :stop]
    ]
    
    :telemetry.attach_many(
      "pipeline-monitoring",
      events,
      &handle_event/4,
      %{}
    )
  end
  
  def handle_event([:pipeline, :context_source, :stop], measurements, metadata, _config) do
    Logger.info(
      "Context source #{metadata.source} completed in #{measurements.duration}ms"
    )
  end
  
  # Handle other events...
end
```

This guide provides the foundation for extending the Enhancement Pipeline. For more specific use cases, refer to the test suite and existing implementations.