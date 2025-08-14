# Story 8.5: Persona Performance Analytics & Optimization

## User Story

**As a** user of TheMaestro
**I want** comprehensive analytics and optimization insights for my personas
**so that** I can understand their effectiveness, identify improvement opportunities, and optimize their performance for better agent interactions

## Acceptance Criteria

1. **Usage Analytics Dashboard**: Comprehensive dashboard tracking persona application frequency, duration, and success rates
2. **Effectiveness Scoring**: Automated scoring system measuring persona effectiveness based on multiple metrics
3. **Performance Metrics Collection**: Real-time collection of response quality, user satisfaction, and interaction success rates
4. **Comparative Analysis Tools**: Side-by-side comparison of different personas and their performance characteristics
5. **Optimization Recommendations**: AI-powered suggestions for improving persona content, structure, and effectiveness
6. **Token Usage Analysis**: Detailed analysis of token consumption patterns and optimization opportunities
7. **A/B Testing Framework**: Built-in system for testing persona variations and measuring performance differences
8. **Historical Trend Analysis**: Long-term trend tracking and seasonal pattern identification
9. **User Feedback Integration**: System for collecting and analyzing user feedback on persona performance
10. **Performance Alerting**: Automated alerts for performance degradation or anomalous behavior patterns
11. **Cost Analysis**: Understanding of computational costs associated with different personas and usage patterns
12. **Response Quality Metrics**: Analysis of response coherence, relevance, and adherence to persona instructions
13. **Session Success Tracking**: Measurement of conversation completion rates and user satisfaction indicators
14. **Content Analysis Tools**: Automated analysis of persona content effectiveness and structural optimization
15. **Benchmarking System**: Comparison against system-wide persona performance benchmarks
16. **Export and Reporting**: Comprehensive reporting capabilities with data export for external analysis
17. **Real-time Monitoring**: Live monitoring of persona performance during active sessions
18. **Predictive Analytics**: Machine learning models predicting persona performance and optimization opportunities
19. **Segmentation Analysis**: Performance analysis segmented by user type, use case, and context
20. **Integration Analytics**: Analysis of how personas perform with different LLM providers and models
21. **Error Pattern Analysis**: Identification and analysis of common failure modes and error patterns
22. **Optimization Automation**: Automated optimization suggestions and implementation workflows
23. **Performance Regression Detection**: Early detection of performance degradation over time
24. **Custom Metrics Framework**: User-definable metrics and KPIs for specific use cases
25. **API Analytics**: Programmatic access to analytics data for integration with external systems

## Technical Implementation

### Analytics Data Collection System

```elixir
# lib/the_maestro/personas/analytics.ex
defmodule TheMaestro.Personas.Analytics do
  @moduledoc """
  Comprehensive persona analytics and performance tracking system.
  """
  
  use GenServer
  require Logger
  
  alias TheMaestro.Personas.{Persona, PersonaApplication}
  alias TheMaestro.Repo
  
  @analytics_buffer_size 1000
  @flush_interval :timer.minutes(5)
  @retention_days 90
  
  defstruct [
    :user_id,
    :buffer,
    :metrics_cache,
    :last_flush,
    :performance_baselines
  ]
  
  # Client API
  
  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id, name: via_tuple(user_id))
  end
  
  @doc """
  Record a persona application event.
  """
  def record_application(user_id, event_data) do
    GenServer.cast(via_tuple(user_id), {:record_application, event_data})
  end
  
  @doc """
  Record persona performance metrics.
  """
  def record_performance(user_id, persona_id, metrics) do
    GenServer.cast(via_tuple(user_id), {:record_performance, persona_id, metrics})
  end
  
  @doc """
  Get analytics summary for a user.
  """
  def get_analytics_summary(user_id, opts \\ []) do
    GenServer.call(via_tuple(user_id), {:get_summary, opts})
  end
  
  @doc """
  Get persona performance comparison.
  """
  def compare_personas(user_id, persona_ids, timeframe \\ :last_30_days) do
    GenServer.call(via_tuple(user_id), {:compare_personas, persona_ids, timeframe})
  end
  
  @doc """
  Get optimization recommendations for a persona.
  """
  def get_optimization_recommendations(user_id, persona_id) do
    GenServer.call(via_tuple(user_id), {:get_recommendations, persona_id})
  end
  
  @doc """
  Start A/B test for persona variations.
  """
  def start_ab_test(user_id, test_config) do
    GenServer.call(via_tuple(user_id), {:start_ab_test, test_config})
  end
  
  # GenServer Callbacks
  
  def init(user_id) do
    state = %__MODULE__{
      user_id: user_id,
      buffer: [],
      metrics_cache: %{},
      last_flush: System.monotonic_time(:second),
      performance_baselines: load_performance_baselines(user_id)
    }
    
    # Schedule periodic data flush
    schedule_flush()
    
    # Subscribe to persona events
    Phoenix.PubSub.subscribe(TheMaestro.PubSub, "personas:#{user_id}")
    
    {:ok, state}
  end
  
  def handle_cast({:record_application, event_data}, state) do
    enhanced_event = enhance_event_data(event_data)
    new_buffer = [enhanced_event | state.buffer]
    
    # Flush if buffer is full
    new_state = if length(new_buffer) >= @analytics_buffer_size do
      flush_buffer(%{state | buffer: new_buffer})
    else
      %{state | buffer: new_buffer}
    end
    
    {:noreply, new_state}
  end
  
  def handle_cast({:record_performance, persona_id, metrics}, state) do
    # Update real-time metrics cache
    current_metrics = Map.get(state.metrics_cache, persona_id, %{})
    updated_metrics = merge_performance_metrics(current_metrics, metrics)
    
    new_cache = Map.put(state.metrics_cache, persona_id, updated_metrics)
    
    # Add to buffer for persistent storage
    performance_event = %{
      type: :performance_measurement,
      persona_id: persona_id,
      metrics: metrics,
      timestamp: NaiveDateTime.utc_now(),
      user_id: state.user_id
    }
    
    new_buffer = [performance_event | state.buffer]
    
    {:noreply, %{state | buffer: new_buffer, metrics_cache: new_cache}}
  end
  
  def handle_call({:get_summary, opts}, _from, state) do
    summary = generate_analytics_summary(state, opts)
    {:reply, summary, state}
  end
  
  def handle_call({:compare_personas, persona_ids, timeframe}, _from, state) do
    comparison = generate_persona_comparison(state.user_id, persona_ids, timeframe)
    {:reply, comparison, state}
  end
  
  def handle_call({:get_recommendations, persona_id}, _from, state) do
    recommendations = generate_optimization_recommendations(state, persona_id)
    {:reply, recommendations, state}
  end
  
  def handle_call({:start_ab_test, test_config}, _from, state) do
    case create_ab_test(state.user_id, test_config) do
      {:ok, test} -> {:reply, {:ok, test}, state}
      error -> {:reply, error, state}
    end
  end
  
  def handle_info(:flush_buffer, state) do
    new_state = flush_buffer(state)
    schedule_flush()
    {:noreply, new_state}
  end
  
  def handle_info({:persona_applied, persona_id, agent_id}, state) do
    event_data = %{
      type: :persona_applied,
      persona_id: persona_id,
      agent_id: agent_id,
      timestamp: NaiveDateTime.utc_now(),
      user_id: state.user_id
    }
    
    new_buffer = [event_data | state.buffer]
    {:noreply, %{state | buffer: new_buffer}}
  end
  
  # Private Functions
  
  defp via_tuple(user_id) do
    {:via, Registry, {TheMaestro.Analytics.Registry, user_id}}
  end
  
  defp enhance_event_data(event_data) do
    event_data
    |> Map.put(:id, Ecto.UUID.generate())
    |> Map.put(:collected_at, NaiveDateTime.utc_now())
    |> add_context_metadata()
  end
  
  defp add_context_metadata(event_data) do
    # Add system context, session info, etc.
    Map.merge(event_data, %{
      system_load: get_system_load(),
      memory_usage: get_memory_usage(),
      active_sessions: count_active_sessions(event_data.user_id)
    })
  end
  
  defp flush_buffer(state) do
    if length(state.buffer) > 0 do
      # Batch insert analytics events
      events = Enum.reverse(state.buffer)
      case insert_analytics_events(events) do
        {:ok, _} ->
          Logger.info("Flushed #{length(events)} analytics events for user #{state.user_id}")
          
        {:error, reason} ->
          Logger.error("Failed to flush analytics events: #{inspect(reason)}")
      end
    end
    
    %{state | buffer: [], last_flush: System.monotonic_time(:second)}
  end
  
  defp schedule_flush do
    Process.send_after(self(), :flush_buffer, @flush_interval)
  end
  
  defp generate_analytics_summary(state, opts) do
    timeframe = Keyword.get(opts, :timeframe, :last_7_days)
    
    # Get cached metrics
    cached_metrics = state.metrics_cache
    
    # Get historical data from database
    historical_data = get_historical_analytics(state.user_id, timeframe)
    
    %{
      timeframe: timeframe,
      total_applications: historical_data.total_applications,
      unique_personas: historical_data.unique_personas,
      average_effectiveness: calculate_average_effectiveness(historical_data),
      top_performing_personas: historical_data.top_performers,
      performance_trends: calculate_performance_trends(historical_data),
      token_usage_summary: calculate_token_usage(historical_data),
      success_rate: calculate_success_rate(historical_data),
      user_satisfaction: calculate_user_satisfaction(historical_data),
      cache_hit_rate: calculate_cache_hit_rate(historical_data),
      response_quality_score: calculate_response_quality(historical_data),
      optimization_opportunities: identify_optimization_opportunities(state, historical_data)
    }
  end
  
  defp generate_persona_comparison(user_id, persona_ids, timeframe) do
    personas_data = Enum.map(persona_ids, fn persona_id ->
      persona = TheMaestro.Personas.get_persona!(persona_id)
      metrics = get_persona_metrics(user_id, persona_id, timeframe)
      
      %{
        persona: persona,
        metrics: metrics,
        effectiveness_score: calculate_effectiveness_score(metrics),
        performance_ranking: calculate_performance_ranking(metrics),
        optimization_score: calculate_optimization_potential(metrics)
      }
    end)
    
    %{
      comparison_data: personas_data,
      relative_performance: calculate_relative_performance(personas_data),
      recommendations: generate_comparison_recommendations(personas_data)
    }
  end
  
  defp generate_optimization_recommendations(state, persona_id) do
    persona = TheMaestro.Personas.get_persona!(persona_id)
    metrics = Map.get(state.metrics_cache, persona_id, %{})
    historical_data = get_persona_historical_data(state.user_id, persona_id)
    
    recommendations = []
    
    # Content optimization recommendations
    recommendations = recommendations ++ analyze_content_optimization(persona, metrics)
    
    # Token usage optimization
    recommendations = recommendations ++ analyze_token_optimization(persona, metrics)
    
    # Performance optimization
    recommendations = recommendations ++ analyze_performance_optimization(metrics, historical_data)
    
    # Structure optimization
    recommendations = recommendations ++ analyze_structure_optimization(persona)
    
    %{
      persona_id: persona_id,
      recommendations: recommendations,
      priority_score: calculate_optimization_priority(recommendations),
      estimated_improvement: estimate_improvement_potential(recommendations, metrics)
    }
  end
  
  defp analyze_content_optimization(persona, metrics) do
    recommendations = []
    
    # Check content length vs performance
    if persona.size_bytes > 5000 && Map.get(metrics, :response_time_avg, 0) > 500 do
      recommendations = [
        %{
          type: :content_length,
          priority: :high,
          description: "Persona content is large and may be impacting response time",
          suggestion: "Consider condensing content or breaking into hierarchical structure",
          estimated_impact: :significant
        } | recommendations
      ]
    end
    
    # Check for unclear instructions
    if Map.get(metrics, :instruction_clarity_score, 1.0) < 0.7 do
      recommendations = [
        %{
          type: :instruction_clarity,
          priority: :medium,
          description: "Persona instructions may be unclear based on response quality",
          suggestion: "Add more specific examples and clearer directive language",
          estimated_impact: :moderate
        } | recommendations
      ]
    end
    
    recommendations
  end
  
  defp analyze_token_optimization(persona, metrics) do
    recommendations = []
    token_efficiency = Map.get(metrics, :token_efficiency, 1.0)
    
    if token_efficiency < 0.8 do
      recommendations = [
        %{
          type: :token_efficiency,
          priority: :medium,
          description: "Persona is using tokens inefficiently",
          suggestion: "Remove redundant phrases and optimize content structure",
          estimated_impact: :cost_reduction,
          potential_savings: calculate_token_savings(persona, metrics)
        } | recommendations
      ]
    end
    
    recommendations
  end
  
  defp analyze_performance_optimization(metrics, historical_data) do
    recommendations = []
    
    # Check response time trends
    if detect_performance_regression(historical_data) do
      recommendations = [
        %{
          type: :performance_regression,
          priority: :high,
          description: "Performance has degraded over time",
          suggestion: "Review recent changes and consider persona optimization",
          estimated_impact: :performance_improvement
        } | recommendations
      ]
    end
    
    recommendations
  end
  
  defp analyze_structure_optimization(persona) do
    recommendations = []
    
    # Analyze persona structure
    structure_score = analyze_persona_structure(persona.content)
    
    if structure_score.has_clear_sections == false do
      recommendations = [
        %{
          type: :structure_improvement,
          priority: :low,
          description: "Persona could benefit from better structural organization",
          suggestion: "Add clear sections with headers for different aspects",
          estimated_impact: :clarity_improvement
        } | recommendations
      ]
    end
    
    recommendations
  end
end
```

### Performance Metrics Schema

```elixir
# Migration: create_persona_analytics_tables.exs
defmodule TheMaestro.Repo.Migrations.CreatePersonaAnalyticsTables do
  use Ecto.Migration

  def change do
    create table(:persona_analytics_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :persona_id, references(:personas, type: :binary_id, on_delete: :delete_all)
      add :event_type, :string, null: false
      add :event_data, :map, default: %{}
      add :metrics, :map, default: %{}
      add :context_metadata, :map, default: %{}
      add :session_id, :string
      add :agent_id, :string
      
      timestamps(inserted_at: :occurred_at, type: :naive_datetime_usec, updated_at: false)
    end

    create table(:persona_performance_metrics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :persona_id, references(:personas, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      
      # Effectiveness metrics
      add :effectiveness_score, :float
      add :response_quality_score, :float
      add :instruction_adherence_score, :float
      add :user_satisfaction_score, :float
      
      # Performance metrics  
      add :average_response_time, :float
      add :token_efficiency, :float
      add :cache_hit_rate, :float
      add :error_rate, :float
      
      # Usage metrics
      add :application_count, :integer, default: 0
      add :session_count, :integer, default: 0
      add :total_tokens_used, :integer, default: 0
      add :successful_interactions, :integer, default: 0
      
      # Time period for these metrics
      add :measurement_period, :string  # e.g., "daily", "weekly", "monthly"
      add :period_start, :naive_datetime_usec
      add :period_end, :naive_datetime_usec
      
      timestamps(type: :naive_datetime_usec)
    end

    create table(:persona_ab_tests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :status, :string, default: "active"
      
      # Test configuration
      add :control_persona_id, references(:personas, type: :binary_id, on_delete: :delete_all)
      add :variant_persona_id, references(:personas, type: :binary_id, on_delete: :delete_all) 
      add :traffic_split, :float, default: 0.5  # 0.0 to 1.0
      add :success_metric, :string
      add :target_sample_size, :integer
      
      # Test results
      add :control_results, :map, default: %{}
      add :variant_results, :map, default: %{}
      add :statistical_significance, :float
      add :winner, :string  # "control", "variant", or "inconclusive"
      
      add :started_at, :naive_datetime_usec
      add :ended_at, :naive_datetime_usec
      
      timestamps(type: :naive_datetime_usec)
    end

    create table(:persona_optimization_recommendations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :persona_id, references(:personas, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :recommendation_type, :string, null: false
      add :priority, :string, null: false
      add :description, :text
      add :suggested_changes, :map
      add :estimated_impact, :string
      add :status, :string, default: "pending"  # pending, applied, dismissed
      add :applied_at, :naive_datetime_usec
      add :impact_measured, :map
      
      timestamps(type: :naive_datetime_usec)
    end

    # Indexes for performance
    create index(:persona_analytics_events, [:user_id, :occurred_at])
    create index(:persona_analytics_events, [:persona_id, :occurred_at])
    create index(:persona_analytics_events, [:event_type])
    create index(:persona_analytics_events, [:session_id])
    
    create index(:persona_performance_metrics, [:persona_id, :period_start, :period_end])
    create index(:persona_performance_metrics, [:user_id, :measurement_period])
    create index(:persona_performance_metrics, [:effectiveness_score])
    
    create index(:persona_ab_tests, [:user_id, :status])
    create index(:persona_ab_tests, [:started_at, :ended_at])
    
    create index(:persona_optimization_recommendations, [:persona_id, :status])
    create index(:persona_optimization_recommendations, [:user_id, :priority])
  end

  def down do
    drop_if_exists table(:persona_optimization_recommendations)
    drop_if_exists table(:persona_ab_tests)  
    drop_if_exists table(:persona_performance_metrics)
    drop_if_exists table(:persona_analytics_events)
  end
end
```

### Analytics Dashboard Component

```elixir
# lib/the_maestro_web/live/persona_live/analytics_component.ex
defmodule TheMaestroWeb.PersonaLive.AnalyticsComponent do
  use TheMaestroWeb, :live_component
  
  alias TheMaestro.Personas.Analytics
  
  def render(assigns) do
    ~H"""
    <div class="persona-analytics space-y-6">
      <!-- Analytics Header -->
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-2xl font-bold text-gray-900 dark:text-white">
            Persona Analytics
          </h2>
          <p class="text-gray-600 dark:text-gray-300">
            Performance insights and optimization recommendations
          </p>
        </div>
        
        <div class="flex items-center space-x-3">
          <!-- Timeframe selector -->
          <select
            phx-change="change_timeframe"
            phx-target={@myself}
            class="rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700"
          >
            <option value="last_24_hours" selected={@timeframe == :last_24_hours}>Last 24 Hours</option>
            <option value="last_7_days" selected={@timeframe == :last_7_days}>Last 7 Days</option>
            <option value="last_30_days" selected={@timeframe == :last_30_days}>Last 30 Days</option>
            <option value="last_90_days" selected={@timeframe == :last_90_days}>Last 90 Days</option>
          </select>
          
          <button
            phx-click="refresh_analytics"
            phx-target={@myself}
            class="px-3 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
          >
            <.icon name="hero-arrow-path" class="w-4 h-4 mr-1" />
            Refresh
          </button>
        </div>
      </div>
      
      <!-- Key Metrics Overview -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <.metric_card
          title="Total Applications"
          value={@summary.total_applications}
          change="+12%"
          trend="up"
          icon="hero-play"
        />
        
        <.metric_card
          title="Avg Effectiveness"
          value={"#{Float.round(@summary.average_effectiveness * 100, 1)}%"}
          change="+3.2%"
          trend="up"
          icon="hero-star"
        />
        
        <.metric_card
          title="Token Efficiency"
          value={"#{Float.round(@summary.token_usage_summary.efficiency * 100, 1)}%"}
          change="-1.5%"
          trend="down"
          icon="hero-cpu-chip"
        />
        
        <.metric_card
          title="Success Rate"
          value={"#{Float.round(@summary.success_rate * 100, 1)}%"}
          change="+5.7%"
          trend="up"
          icon="hero-check-circle"
        />
      </div>
      
      <!-- Performance Trends Chart -->
      <div class="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
            Performance Trends
          </h3>
          
          <div class="flex items-center space-x-2">
            <button
              phx-click="toggle_chart_metric"
              phx-value-metric="effectiveness"
              phx-target={@myself}
              class={[
                "px-3 py-1 text-sm rounded transition-colors",
                @chart_metric == "effectiveness" && "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200" || "text-gray-600 hover:text-gray-800"
              ]}
            >
              Effectiveness
            </button>
            
            <button
              phx-click="toggle_chart_metric"
              phx-value-metric="response_time"
              phx-target={@myself}
              class={[
                "px-3 py-1 text-sm rounded transition-colors",
                @chart_metric == "response_time" && "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200" || "text-gray-600 hover:text-gray-800"
              ]}
            >
              Response Time
            </button>
            
            <button
              phx-click="toggle_chart_metric"
              phx-value-metric="token_usage"
              phx-target={@myself}
              class={[
                "px-3 py-1 text-sm rounded transition-colors",
                @chart_metric == "token_usage" && "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200" || "text-gray-600 hover:text-gray-800"
              ]}
            >
              Token Usage
            </button>
          </div>
        </div>
        
        <!-- Chart placeholder - would integrate with charting library -->
        <div class="h-64 bg-gray-50 dark:bg-gray-900 rounded flex items-center justify-center">
          <div class="text-center">
            <.icon name="hero-chart-bar" class="w-12 h-12 text-gray-400 mx-auto mb-2" />
            <p class="text-gray-500">Performance trend chart for {@chart_metric}</p>
            <p class="text-sm text-gray-400">Chart integration would be implemented here</p>
          </div>
        </div>
      </div>
      
      <!-- Top Performing Personas -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div class="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700">
          <h3 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">
            Top Performing Personas
          </h3>
          
          <div class="space-y-3">
            <%= for {persona, index} <- Enum.with_index(@summary.top_performing_personas) do %>
              <div class="flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-900 rounded">
                <div class="flex items-center space-x-3">
                  <span class={[
                    "w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold",
                    index == 0 && "bg-yellow-100 text-yellow-800",
                    index == 1 && "bg-gray-100 text-gray-800", 
                    index == 2 && "bg-orange-100 text-orange-800",
                    index > 2 && "bg-blue-100 text-blue-800"
                  ]}>
                    <%= index + 1 %>
                  </span>
                  
                  <div>
                    <p class="font-medium text-gray-900 dark:text-white">
                      <%= persona.name %>
                    </p>
                    <p class="text-sm text-gray-500">
                      <%= persona.applications %> applications
                    </p>
                  </div>
                </div>
                
                <div class="text-right">
                  <p class="text-sm font-semibold text-green-600">
                    <%= Float.round(persona.effectiveness_score * 100, 1) %>%
                  </p>
                  <p class="text-xs text-gray-500">effectiveness</p>
                </div>
              </div>
            <% end %>
          </div>
        </div>
        
        <!-- Optimization Recommendations -->
        <div class="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700">
          <h3 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">
            Optimization Opportunities
          </h3>
          
          <div class="space-y-3">
            <%= for opportunity <- @summary.optimization_opportunities do %>
              <div class="p-3 border border-gray-200 dark:border-gray-600 rounded">
                <div class="flex items-start justify-between mb-2">
                  <div class="flex items-center space-x-2">
                    <span class={[
                      "px-2 py-1 text-xs font-medium rounded",
                      opportunity.priority == "high" && "bg-red-100 text-red-800",
                      opportunity.priority == "medium" && "bg-yellow-100 text-yellow-800",
                      opportunity.priority == "low" && "bg-blue-100 text-blue-800"
                    ]}>
                      <%= String.capitalize(opportunity.priority) %>
                    </span>
                    
                    <h4 class="font-medium text-gray-900 dark:text-white">
                      <%= opportunity.title %>
                    </h4>
                  </div>
                  
                  <button
                    phx-click="apply_optimization"
                    phx-value-id={opportunity.id}
                    phx-target={@myself}
                    class="text-blue-600 hover:text-blue-800 text-sm"
                  >
                    Apply
                  </button>
                </div>
                
                <p class="text-sm text-gray-600 dark:text-gray-300 mb-2">
                  <%= opportunity.description %>
                </p>
                
                <div class="flex items-center justify-between text-xs text-gray-500">
                  <span>Persona: <%= opportunity.persona_name %></span>
                  <span>Est. Impact: <%= String.capitalize(opportunity.estimated_impact) %></span>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
      
      <!-- A/B Testing Section -->
      <div class="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
            A/B Testing
          </h3>
          
          <button
            phx-click="create_ab_test"
            phx-target={@myself}
            class="px-4 py-2 bg-green-600 text-white text-sm rounded-md hover:bg-green-700"
          >
            <.icon name="hero-plus" class="w-4 h-4 mr-1" />
            New Test
          </button>
        </div>
        
        <%= if @ab_tests == [] do %>
          <div class="text-center py-8">
            <.icon name="hero-beaker" class="w-12 h-12 text-gray-400 mx-auto mb-2" />
            <p class="text-gray-500">No A/B tests running</p>
            <p class="text-sm text-gray-400">Create a test to compare persona variations</p>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%= for test <- @ab_tests do %>
              <div class="p-4 border border-gray-200 dark:border-gray-600 rounded">
                <div class="flex items-center justify-between mb-2">
                  <h4 class="font-medium text-gray-900 dark:text-white">
                    <%= test.name %>
                  </h4>
                  
                  <span class={[
                    "px-2 py-1 text-xs font-medium rounded",
                    test.status == "active" && "bg-green-100 text-green-800",
                    test.status == "completed" && "bg-blue-100 text-blue-800",
                    test.status == "paused" && "bg-yellow-100 text-yellow-800"
                  ]}>
                    <%= String.capitalize(test.status) %>
                  </span>
                </div>
                
                <p class="text-sm text-gray-600 dark:text-gray-300 mb-3">
                  <%= test.description %>
                </p>
                
                <!-- Test Results -->
                <%= if test.status == "completed" do %>
                  <div class="grid grid-cols-2 gap-2 text-xs">
                    <div class="bg-blue-50 dark:bg-blue-900 p-2 rounded">
                      <div class="font-medium">Control</div>
                      <div><%= test.control_results.effectiveness %>% eff.</div>
                    </div>
                    
                    <div class="bg-green-50 dark:bg-green-900 p-2 rounded">
                      <div class="font-medium">Variant</div>
                      <div><%= test.variant_results.effectiveness %>% eff.</div>
                    </div>
                  </div>
                  
                  <div class="mt-2 text-xs">
                    <span class="font-medium">Winner:</span>
                    <span class={[
                      test.winner == "variant" && "text-green-600",
                      test.winner == "control" && "text-blue-600",
                      test.winner == "inconclusive" && "text-gray-600"
                    ]}>
                      <%= String.capitalize(test.winner) %>
                    </span>
                  </div>
                <% else %>
                  <div class="text-xs text-gray-500">
                    Progress: <%= test.sample_size %> / <%= test.target_sample_size %> samples
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
  
  def mount(socket) do
    socket = 
      socket
      |> assign(:timeframe, :last_7_days)
      |> assign(:chart_metric, "effectiveness")
      |> assign(:loading, true)
    
    {:ok, socket}
  end
  
  def update(%{user: user} = assigns, socket) do
    socket = 
      socket
      |> assign(assigns)
      |> load_analytics_data()
    
    {:ok, socket}
  end
  
  def handle_event("change_timeframe", %{"value" => timeframe}, socket) do
    timeframe_atom = String.to_existing_atom(timeframe)
    
    socket = 
      socket
      |> assign(:timeframe, timeframe_atom)
      |> assign(:loading, true)
      |> load_analytics_data()
    
    {:noreply, socket}
  end
  
  def handle_event("refresh_analytics", _params, socket) do
    socket = 
      socket
      |> assign(:loading, true)
      |> load_analytics_data()
    
    {:noreply, socket}
  end
  
  def handle_event("toggle_chart_metric", %{"metric" => metric}, socket) do
    {:noreply, assign(socket, :chart_metric, metric)}
  end
  
  def handle_event("apply_optimization", %{"id" => recommendation_id}, socket) do
    # Apply optimization recommendation
    send(self(), {:apply_optimization, recommendation_id})
    {:noreply, socket}
  end
  
  def handle_event("create_ab_test", _params, socket) do
    send(self(), :show_ab_test_modal)
    {:noreply, socket}
  end
  
  defp load_analytics_data(socket) do
    user = socket.assigns.user
    timeframe = socket.assigns.timeframe
    
    # Load analytics summary
    summary = Analytics.get_analytics_summary(user.id, timeframe: timeframe)
    
    # Load A/B tests
    ab_tests = Analytics.list_ab_tests(user.id, status: :active)
    
    socket
    |> assign(:summary, summary)
    |> assign(:ab_tests, ab_tests)
    |> assign(:loading, false)
  end
  
  defp metric_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-gray-800 p-6 rounded-lg border border-gray-200 dark:border-gray-700">
      <div class="flex items-center justify-between">
        <div>
          <p class="text-sm font-medium text-gray-600 dark:text-gray-400">
            <%= @title %>
          </p>
          <p class="text-2xl font-bold text-gray-900 dark:text-white">
            <%= @value %>
          </p>
        </div>
        
        <div class={[
          "p-3 rounded-full",
          @trend == "up" && "bg-green-100 dark:bg-green-900",
          @trend == "down" && "bg-red-100 dark:bg-red-900",
          @trend == "neutral" && "bg-gray-100 dark:bg-gray-700"
        ]}>
          <.icon name={@icon} class={[
            "w-6 h-6",
            @trend == "up" && "text-green-600",
            @trend == "down" && "text-red-600",
            @trend == "neutral" && "text-gray-600"
          ]} />
        </div>
      </div>
      
      <div class="mt-2 flex items-center">
        <span class={[
          "text-sm font-medium",
          @trend == "up" && "text-green-600",
          @trend == "down" && "text-red-600",
          @trend == "neutral" && "text-gray-600"
        ]}>
          <%= @change %>
        </span>
        <span class="text-sm text-gray-500 ml-2">vs previous period</span>
      </div>
    </div>
    """
  end
end
```

## Module Structure

```
lib/the_maestro/personas/
├── analytics/
│   ├── analytics.ex              # Main analytics GenServer
│   ├── collector.ex              # Event collection system  
│   ├── processor.ex              # Data processing and aggregation
│   ├── optimizer.ex              # Optimization recommendation engine
│   ├── ab_tester.ex              # A/B testing framework
│   ├── performance_monitor.ex    # Real-time performance monitoring
│   ├── report_generator.ex       # Analytics reporting system
│   └── metrics_calculator.ex     # Metrics calculation utilities
└── schemas/
    ├── analytics_event.ex        # Analytics event schema
    ├── performance_metric.ex     # Performance metrics schema
    ├── ab_test.ex                # A/B test schema
    └── optimization_recommendation.ex # Recommendation schema
```

## Integration Points

1. **Real-time Data Collection**: Integration with ApplicationEngine for live metrics
2. **Performance Monitoring**: System-wide performance tracking and alerting
3. **User Interface Integration**: Analytics dashboard in both web UI and TUI
4. **Optimization Pipeline**: Automated recommendation generation and application
5. **A/B Testing Framework**: Integrated testing capabilities for persona variations

## Performance Considerations

- Asynchronous data collection with buffering
- Background data processing and aggregation
- Efficient database queries with proper indexing
- Caching of frequently accessed analytics data
- Batch processing for large-scale analytics operations

## Privacy and Security

- User data anonymization for system-wide analytics
- Secure storage of performance metrics
- Privacy-compliant data retention policies
- User consent for analytics data collection
- Audit trails for optimization recommendations

## Dependencies

- Story 8.1: Persona Definition & Storage System for core data
- Story 8.2: Dynamic Persona Loading & Application for performance metrics collection
- Phoenix LiveView for real-time analytics dashboard
- Background job processing system (Oban)
- Time-series database capabilities for trend analysis

## Definition of Done

- [ ] Analytics data collection system implemented and operational
- [ ] Performance metrics calculation and storage functional
- [ ] Analytics dashboard with real-time updates implemented
- [ ] Optimization recommendation engine operational
- [ ] A/B testing framework with statistical analysis
- [ ] Historical trend analysis and visualization
- [ ] User feedback integration system implemented
- [ ] Performance alerting system operational
- [ ] Cost analysis and token usage optimization
- [ ] Export and reporting capabilities functional
- [ ] Real-time monitoring dashboard implemented
- [ ] Predictive analytics models operational
- [ ] Custom metrics framework implemented
- [ ] API analytics with programmatic access
- [ ] Privacy-compliant data handling verified
- [ ] Comprehensive unit tests passing (>90% coverage)
- [ ] Integration tests for all analytics workflows
- [ ] Performance benchmarks meeting requirements
- [ ] Security audit completed with no issues
- [ ] User acceptance testing completed
- [ ] Documentation for analytics APIs and features complete