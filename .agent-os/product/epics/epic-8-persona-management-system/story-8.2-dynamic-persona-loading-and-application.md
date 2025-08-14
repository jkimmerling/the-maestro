# Story 8.2: Dynamic Persona Loading & Application

## User Story

**As a** user of TheMaestro
**I want** personas to be dynamically loaded and applied to my agent sessions in real-time
**so that** I can experience immediate changes in agent behavior and switch between different interaction modes during conversations

## Acceptance Criteria

1. **Real-time Persona Loading**: Personas can be loaded and applied to active agent sessions without requiring session restart
2. **Context-aware Application**: Persona content is intelligently applied to agent prompts while preserving conversation context
3. **Hierarchical Loading**: Support for persona inheritance where child personas extend parent persona characteristics
4. **Session State Management**: Agent sessions maintain persona state across conversation turns and system restarts
5. **Memory-efficient Caching**: Frequently used personas are cached in memory with smart eviction policies
6. **Token Optimization**: Persona content is optimized to minimize token usage while maintaining effectiveness
7. **Conflict Resolution**: System handles persona switching conflicts and maintains conversation coherence
8. **Performance Monitoring**: Real-time metrics for persona loading, application, and effectiveness
9. **Rollback Capability**: Ability to revert to previous persona or remove persona application mid-conversation
10. **Content Preprocessing**: Persona content is parsed and prepared for optimal LLM integration
11. **Error Recovery**: Graceful handling of persona loading failures with fallback mechanisms
12. **Concurrent Session Support**: Multiple agents can use different personas simultaneously without interference
13. **Dynamic Content Updates**: Live updates to persona content are reflected in active sessions
14. **Context Window Management**: Intelligent management of context window space when applying personas
15. **Persona Activation Events**: Event system for tracking when personas are applied, changed, or removed
16. **State Persistence**: Persona application state survives agent process restarts and system failures
17. **Integration with Agent Lifecycle**: Personas integrate seamlessly with agent creation, update, and termination flows
18. **Validation at Runtime**: Real-time validation of persona content before application to prevent errors
19. **Debug and Monitoring**: Comprehensive logging and debugging tools for persona application issues
20. **A/B Testing Support**: Framework for testing different persona versions with the same agent
21. **Persona Composition**: Support for combining multiple personas or persona fragments
22. **Conditional Application**: Personas can be applied based on conversation context, user preferences, or environmental factors
23. **Performance Benchmarking**: Automated benchmarking of persona loading and application performance
24. **Security Validation**: Runtime security checks to prevent malicious persona content execution
25. **Graceful Degradation**: System continues to function effectively when persona services are unavailable

## Technical Implementation

### Persona Application Engine

```elixir
# lib/the_maestro/personas/application_engine.ex
defmodule TheMaestro.Personas.ApplicationEngine do
  @moduledoc """
  Core engine for applying personas to agent sessions in real-time.
  """
  
  use GenServer
  require Logger
  
  alias TheMaestro.Personas.{Persona, Cache, ContentProcessor}
  alias TheMaestro.Agents.Agent
  
  @cache_ttl :timer.minutes(30)
  @max_cache_size 1000
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Apply a persona to an agent session.
  """
  def apply_persona(agent_pid, persona_id, opts \\ []) do
    GenServer.call(__MODULE__, {:apply_persona, agent_pid, persona_id, opts})
  end
  
  @doc """
  Remove persona from an agent session.
  """
  def remove_persona(agent_pid) do
    GenServer.call(__MODULE__, {:remove_persona, agent_pid})
  end
  
  @doc """
  Switch persona for an agent session.
  """
  def switch_persona(agent_pid, new_persona_id, opts \\ []) do
    GenServer.call(__MODULE__, {:switch_persona, agent_pid, new_persona_id, opts})
  end
  
  @doc """
  Get current persona for an agent.
  """
  def get_current_persona(agent_pid) do
    GenServer.call(__MODULE__, {:get_current_persona, agent_pid})
  end
  
  @doc """
  Preload personas into cache.
  """
  def preload_personas(persona_ids) do
    GenServer.cast(__MODULE__, {:preload_personas, persona_ids})
  end
  
  # GenServer Callbacks
  
  def init(_opts) do
    state = %{
      active_personas: %{},  # agent_pid -> persona_data
      persona_cache: %{},    # persona_id -> {persona, loaded_at}
      performance_stats: %{
        applications: 0,
        cache_hits: 0,
        cache_misses: 0,
        avg_load_time: 0
      }
    }
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    {:ok, state}
  end
  
  def handle_call({:apply_persona, agent_pid, persona_id, opts}, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    case load_persona(persona_id, state) do
      {:ok, persona_data, new_state} ->
        case apply_persona_to_agent(agent_pid, persona_data, opts) do
          :ok ->
            updated_state = %{new_state | 
              active_personas: Map.put(new_state.active_personas, agent_pid, persona_data)
            }
            
            # Update performance stats
            load_time = System.monotonic_time(:millisecond) - start_time
            updated_stats = update_performance_stats(updated_state.performance_stats, :application, load_time)
            final_state = %{updated_state | performance_stats: updated_stats}
            
            # Log application event
            log_persona_event(agent_pid, persona_id, :applied, load_time)
            
            # Notify listeners
            broadcast_persona_event(agent_pid, {:persona_applied, persona_id})
            
            {:reply, {:ok, persona_data}, final_state}
            
          {:error, reason} = error ->
            Logger.error("Failed to apply persona #{persona_id} to agent #{inspect(agent_pid)}: #{inspect(reason)}")
            {:reply, error, new_state}
        end
        
      {:error, reason} = error ->
        Logger.error("Failed to load persona #{persona_id}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end
  
  def handle_call({:remove_persona, agent_pid}, _from, state) do
    case Map.get(state.active_personas, agent_pid) do
      nil ->
        {:reply, {:error, :no_active_persona}, state}
        
      persona_data ->
        case remove_persona_from_agent(agent_pid) do
          :ok ->
            updated_state = %{state | 
              active_personas: Map.delete(state.active_personas, agent_pid)
            }
            
            log_persona_event(agent_pid, persona_data.id, :removed, 0)
            broadcast_persona_event(agent_pid, {:persona_removed, persona_data.id})
            
            {:reply, :ok, updated_state}
            
          error ->
            {:reply, error, state}
        end
    end
  end
  
  def handle_call({:switch_persona, agent_pid, new_persona_id, opts}, _from, state) do
    # First remove current persona, then apply new one
    with :ok <- remove_persona_from_agent(agent_pid),
         {:ok, persona_data, new_state} <- load_persona(new_persona_id, state),
         :ok <- apply_persona_to_agent(agent_pid, persona_data, opts) do
      
      updated_state = %{new_state | 
        active_personas: Map.put(new_state.active_personas, agent_pid, persona_data)
      }
      
      log_persona_event(agent_pid, new_persona_id, :switched, 0)
      broadcast_persona_event(agent_pid, {:persona_switched, new_persona_id})
      
      {:reply, {:ok, persona_data}, updated_state}
    else
      error ->
        {:reply, error, state}
    end
  end
  
  def handle_call({:get_current_persona, agent_pid}, _from, state) do
    persona_data = Map.get(state.active_personas, agent_pid)
    {:reply, persona_data, state}
  end
  
  def handle_cast({:preload_personas, persona_ids}, state) do
    new_state = Enum.reduce(persona_ids, state, fn persona_id, acc_state ->
      case load_persona(persona_id, acc_state) do
        {:ok, _persona_data, updated_state} -> updated_state
        {:error, _reason} -> acc_state
      end
    end)
    
    {:noreply, new_state}
  end
  
  def handle_info(:cleanup_cache, state) do
    cleaned_state = cleanup_cache(state)
    schedule_cleanup()
    {:noreply, cleaned_state}
  end
  
  def handle_info({:DOWN, _ref, :process, agent_pid, _reason}, state) do
    # Clean up when agent process dies
    updated_state = %{state | 
      active_personas: Map.delete(state.active_personas, agent_pid)
    }
    {:noreply, updated_state}
  end
  
  # Private Functions
  
  defp load_persona(persona_id, state) do
    case Map.get(state.persona_cache, persona_id) do
      {persona_data, loaded_at} when System.monotonic_time(:second) - loaded_at < @cache_ttl ->
        # Cache hit
        updated_stats = update_performance_stats(state.performance_stats, :cache_hit, 0)
        {:ok, persona_data, %{state | performance_stats: updated_stats}}
        
      _ ->
        # Cache miss - load from database
        case TheMaestro.Personas.get_persona(persona_id) do
          nil ->
            {:error, :persona_not_found}
            
          persona ->
            case process_persona_content(persona) do
              {:ok, persona_data} ->
                # Update cache
                new_cache = Map.put(state.persona_cache, persona_id, {persona_data, System.monotonic_time(:second)})
                
                # Evict old entries if cache is full
                final_cache = if map_size(new_cache) > @max_cache_size do
                  evict_oldest_entries(new_cache)
                else
                  new_cache
                end
                
                updated_stats = update_performance_stats(state.performance_stats, :cache_miss, 0)
                new_state = %{state | persona_cache: final_cache, performance_stats: updated_stats}
                
                {:ok, persona_data, new_state}
                
              error ->
                error
            end
        end
    end
  end
  
  defp process_persona_content(persona) do
    try do
      processed_content = ContentProcessor.process(persona.content)
      
      persona_data = %{
        id: persona.id,
        name: persona.name,
        display_name: persona.display_name,
        processed_content: processed_content,
        metadata: persona.metadata,
        version: persona.version,
        token_count: ContentProcessor.estimate_tokens(processed_content)
      }
      
      {:ok, persona_data}
    rescue
      error ->
        Logger.error("Error processing persona content for #{persona.id}: #{inspect(error)}")
        {:error, :content_processing_failed}
    end
  end
  
  defp apply_persona_to_agent(agent_pid, persona_data, opts) do
    # Apply persona through agent's update mechanism
    try do
      Agent.apply_persona(agent_pid, persona_data, opts)
    catch
      :exit, {:noproc, _} ->
        {:error, :agent_not_found}
      error ->
        {:error, error}
    end
  end
  
  defp remove_persona_from_agent(agent_pid) do
    try do
      Agent.remove_persona(agent_pid)
    catch
      :exit, {:noproc, _} ->
        {:error, :agent_not_found}
      error ->
        {:error, error}
    end
  end
  
  defp evict_oldest_entries(cache) do
    # Keep the most recently loaded entries
    sorted_entries = Enum.sort_by(cache, fn {_id, {_data, loaded_at}} -> loaded_at end, :desc)
    
    sorted_entries
    |> Enum.take(div(@max_cache_size, 2))
    |> Enum.into(%{})
  end
  
  defp cleanup_cache(state) do
    current_time = System.monotonic_time(:second)
    
    cleaned_cache = Enum.filter(state.persona_cache, fn {_id, {_data, loaded_at}} ->
      current_time - loaded_at < @cache_ttl
    end) |> Enum.into(%{})
    
    %{state | persona_cache: cleaned_cache}
  end
  
  defp update_performance_stats(stats, operation, time) do
    case operation do
      :application ->
        %{stats | 
          applications: stats.applications + 1,
          avg_load_time: calculate_avg_load_time(stats.avg_load_time, stats.applications, time)
        }
        
      :cache_hit ->
        %{stats | cache_hits: stats.cache_hits + 1}
        
      :cache_miss ->
        %{stats | cache_misses: stats.cache_misses + 1}
    end
  end
  
  defp calculate_avg_load_time(current_avg, count, new_time) do
    if count == 0 do
      new_time
    else
      (current_avg * count + new_time) / (count + 1)
    end
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_cache, :timer.minutes(5))
  end
  
  defp log_persona_event(agent_pid, persona_id, action, load_time) do
    Logger.info("Persona #{action}: #{persona_id} for agent #{inspect(agent_pid)} (#{load_time}ms)")
  end
  
  defp broadcast_persona_event(agent_pid, event) do
    Phoenix.PubSub.broadcast(TheMaestro.PubSub, "agent:#{inspect(agent_pid)}", event)
  end
end
```

### Content Processor Module

```elixir
# lib/the_maestro/personas/content_processor.ex
defmodule TheMaestro.Personas.ContentProcessor do
  @moduledoc """
  Processes persona content for optimal LLM integration.
  """
  
  @token_estimation_ratio 4  # Rough estimate: 4 characters per token
  
  def process(content) when is_binary(content) do
    content
    |> normalize_whitespace()
    |> process_markdown()
    |> optimize_for_tokens()
    |> validate_structure()
  end
  
  def estimate_tokens(content) when is_binary(content) do
    div(byte_size(content), @token_estimation_ratio)
  end
  
  defp normalize_whitespace(content) do
    content
    |> String.trim()
    |> String.replace(~r/\r\n|\r/, "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/[ \t]+/, " ")
  end
  
  defp process_markdown(content) do
    # Convert markdown headers to structured format
    content
    |> String.replace(~r/^# (.+)$/m, "## Role: \\1")
    |> String.replace(~r/^## (.+)$/m, "### \\1")
    |> String.replace(~r/^### (.+)$/m, "#### \\1")
  end
  
  defp optimize_for_tokens(content) do
    # Remove excessive formatting that doesn't add value for LLMs
    content
    |> String.replace(~r/\*{3,}/, "**")  # Reduce multiple asterisks
    |> String.replace(~r/_{3,}/, "__")   # Reduce multiple underscores
    |> String.replace(~r/`{4,}/, "```")  # Normalize code blocks
  end
  
  defp validate_structure(content) do
    # Ensure content has required structure for LLM instructions
    if String.contains?(content, ["You are", "Your role", "##"]) do
      content
    else
      # Wrap in basic instruction format
      "## Role\n\nYou are an AI assistant with the following characteristics:\n\n#{content}"
    end
  end
end
```

### Agent Integration Module

```elixir
# lib/the_maestro/agents/agent.ex (additions)
defmodule TheMaestro.Agents.Agent do
  # ... existing code ...
  
  @doc """
  Apply a persona to the agent session.
  """
  def apply_persona(agent_pid, persona_data, opts \\ []) do
    GenServer.call(agent_pid, {:apply_persona, persona_data, opts})
  end
  
  @doc """
  Remove the current persona from the agent session.
  """
  def remove_persona(agent_pid) do
    GenServer.call(agent_pid, :remove_persona)
  end
  
  def handle_call({:apply_persona, persona_data, opts}, _from, state) do
    try do
      # Prepare persona for integration
      prepared_persona = prepare_persona_for_integration(persona_data, state, opts)
      
      # Update agent state with persona
      new_state = %{state |
        current_persona: prepared_persona,
        system_prompt: build_system_prompt(state.base_system_prompt, prepared_persona),
        persona_metadata: %{
          applied_at: NaiveDateTime.utc_now(),
          version: persona_data.version,
          token_count: persona_data.token_count,
          options: opts
        }
      }
      
      # Update conversation session if needed
      if state.session_id do
        TheMaestro.Sessions.update_session_persona(state.session_id, persona_data.id)
      end
      
      {:reply, :ok, new_state}
    rescue
      error ->
        Logger.error("Failed to apply persona: #{inspect(error)}")
        {:reply, {:error, :persona_application_failed}, state}
    end
  end
  
  def handle_call(:remove_persona, _from, state) do
    new_state = %{state |
      current_persona: nil,
      system_prompt: state.base_system_prompt,
      persona_metadata: nil
    }
    
    # Update conversation session
    if state.session_id do
      TheMaestro.Sessions.update_session_persona(state.session_id, nil)
    end
    
    {:reply, :ok, new_state}
  end
  
  defp prepare_persona_for_integration(persona_data, agent_state, opts) do
    # Adjust persona content based on agent context and options
    processed_content = persona_data.processed_content
    
    # Handle inheritance if this persona has a parent
    processed_content = if parent_id = persona_data.metadata["parent_id"] do
      merge_with_parent_persona(processed_content, parent_id)
    else
      processed_content
    end
    
    # Apply context-specific modifications
    processed_content = apply_context_modifications(processed_content, agent_state, opts)
    
    %{persona_data | processed_content: processed_content}
  end
  
  defp merge_with_parent_persona(content, parent_id) do
    case TheMaestro.Personas.get_persona(parent_id) do
      nil -> content
      parent ->
        case TheMaestro.Personas.ContentProcessor.process(parent.content) do
          parent_content when is_binary(parent_content) ->
            """
            #{parent_content}
            
            ## Specialized Instructions
            
            #{content}
            """
          _ -> content
        end
    end
  end
  
  defp apply_context_modifications(content, _agent_state, opts) do
    # Apply any context-specific modifications based on options
    content = if Keyword.get(opts, :strict_mode, false) do
      "#{content}\n\n**Note: Operating in strict mode with enhanced validation.**"
    else
      content
    end
    
    # Add conversation context if specified
    if context = Keyword.get(opts, :conversation_context) do
      "#{content}\n\n## Current Context\n\n#{context}"
    else
      content
    end
  end
  
  defp build_system_prompt(base_prompt, nil), do: base_prompt
  defp build_system_prompt(base_prompt, persona) do
    """
    #{base_prompt}
    
    ## Persona Instructions
    
    #{persona.processed_content}
    """
  end
  
  # ... rest of existing code ...
end
```

### Performance Monitoring

```elixir
# lib/the_maestro/personas/performance_monitor.ex
defmodule TheMaestro.Personas.PerformanceMonitor do
  @moduledoc """
  Monitors persona application performance and effectiveness.
  """
  
  use GenServer
  alias TheMaestro.Personas.ApplicationEngine
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def record_application(persona_id, agent_id, metrics) do
    GenServer.cast(__MODULE__, {:record_application, persona_id, agent_id, metrics})
  end
  
  def get_performance_stats(persona_id) do
    GenServer.call(__MODULE__, {:get_stats, persona_id})
  end
  
  def get_global_stats do
    GenServer.call(__MODULE__, :get_global_stats)
  end
  
  def init(_opts) do
    state = %{
      persona_stats: %{},
      global_stats: %{
        total_applications: 0,
        avg_load_time: 0,
        cache_hit_rate: 0
      }
    }
    
    {:ok, state}
  end
  
  def handle_cast({:record_application, persona_id, agent_id, metrics}, state) do
    persona_stats = Map.get(state.persona_stats, persona_id, %{
      applications: 0,
      total_load_time: 0,
      avg_load_time: 0,
      effectiveness_scores: [],
      last_applied: nil
    })
    
    updated_persona_stats = %{persona_stats |
      applications: persona_stats.applications + 1,
      total_load_time: persona_stats.total_load_time + metrics.load_time,
      avg_load_time: (persona_stats.total_load_time + metrics.load_time) / (persona_stats.applications + 1),
      last_applied: NaiveDateTime.utc_now()
    }
    
    new_state = %{state |
      persona_stats: Map.put(state.persona_stats, persona_id, updated_persona_stats),
      global_stats: update_global_stats(state.global_stats, metrics)
    }
    
    {:noreply, new_state}
  end
  
  def handle_call({:get_stats, persona_id}, _from, state) do
    stats = Map.get(state.persona_stats, persona_id, %{})
    {:reply, stats, state}
  end
  
  def handle_call(:get_global_stats, _from, state) do
    {:reply, state.global_stats, state}
  end
  
  defp update_global_stats(global_stats, metrics) do
    new_total = global_stats.total_applications + 1
    new_avg_load = (global_stats.avg_load_time * global_stats.total_applications + metrics.load_time) / new_total
    
    %{global_stats |
      total_applications: new_total,
      avg_load_time: new_avg_load
    }
  end
end
```

### Session State Persistence

```elixir
# lib/the_maestro/sessions/conversation_session.ex (additions)
defmodule TheMaestro.Sessions.ConversationSession do
  # ... existing schema ...
  
  schema "conversation_sessions" do
    # ... existing fields ...
    field :current_persona_id, :binary_id
    field :persona_application_history, {:array, :map}, default: []
    # ... rest of fields ...
  end
  
  def changeset(session, attrs) do
    session
    |> cast(attrs, [..., :current_persona_id, :persona_application_history])
    |> # ... existing validations ...
  end
end
```

### Testing Strategy

```elixir
# test/the_maestro/personas/application_engine_test.exs
defmodule TheMaestro.Personas.ApplicationEngineTest do
  use TheMaestro.DataCase
  alias TheMaestro.Personas.ApplicationEngine
  alias TheMaestro.Agents.Agent
  
  setup do
    user = insert(:user)
    persona = insert(:persona, user: user)
    
    {:ok, agent_pid} = Agent.start_link(%{user_id: user.id, session_id: nil})
    
    %{user: user, persona: persona, agent_pid: agent_pid}
  end
  
  describe "apply_persona/3" do
    test "successfully applies persona to agent", %{persona: persona, agent_pid: agent_pid} do
      assert {:ok, persona_data} = ApplicationEngine.apply_persona(agent_pid, persona.id)
      assert persona_data.id == persona.id
      assert persona_data.processed_content != nil
    end
    
    test "caches persona after first load", %{persona: persona, agent_pid: agent_pid} do
      # First application
      {:ok, _} = ApplicationEngine.apply_persona(agent_pid, persona.id)
      
      # Second application should use cache
      {:ok, _} = ApplicationEngine.apply_persona(agent_pid, persona.id)
      
      stats = ApplicationEngine.get_performance_stats()
      assert stats.cache_hits > 0
    end
    
    test "handles agent process death gracefully", %{persona: persona, agent_pid: agent_pid} do
      {:ok, _} = ApplicationEngine.apply_persona(agent_pid, persona.id)
      
      # Kill agent process
      Process.exit(agent_pid, :kill)
      Process.sleep(100)
      
      # Engine should clean up internal state
      assert ApplicationEngine.get_current_persona(agent_pid) == nil
    end
  end
  
  describe "switch_persona/3" do
    test "switches from one persona to another", %{user: user, agent_pid: agent_pid} do
      persona1 = insert(:persona, user: user, name: "persona1")
      persona2 = insert(:persona, user: user, name: "persona2")
      
      {:ok, _} = ApplicationEngine.apply_persona(agent_pid, persona1.id)
      {:ok, persona_data} = ApplicationEngine.switch_persona(agent_pid, persona2.id)
      
      assert persona_data.id == persona2.id
    end
  end
  
  describe "remove_persona/1" do
    test "removes persona from agent", %{persona: persona, agent_pid: agent_pid} do
      {:ok, _} = ApplicationEngine.apply_persona(agent_pid, persona.id)
      assert :ok = ApplicationEngine.remove_persona(agent_pid)
      assert ApplicationEngine.get_current_persona(agent_pid) == nil
    end
  end
end
```

## Module Structure

```
lib/the_maestro/personas/
├── application_engine.ex       # Core persona application engine
├── content_processor.ex        # Content processing and optimization
├── performance_monitor.ex      # Performance monitoring and stats
├── cache.ex                    # Caching layer implementation
├── hierarchical_loader.ex      # Handles persona inheritance
└── event_broadcaster.ex        # Event system for persona changes
```

## Integration Points

1. **Agent Integration**: Direct integration with Agent GenServer for real-time persona application
2. **Session Persistence**: Persona state stored in conversation sessions
3. **Performance Monitoring**: Real-time metrics collection and analysis
4. **Event System**: Phoenix PubSub for persona change notifications

## Performance Considerations

- In-memory caching with TTL and size limits
- Lazy loading of persona content
- Token count estimation and optimization
- Background cache cleanup and eviction
- Performance metrics collection and monitoring

## Dependencies

- Story 8.1: Persona Definition & Storage System for core persona data
- Agent system for persona application
- Phoenix PubSub for event broadcasting
- Conversation sessions for state persistence

## Definition of Done

- [ ] ApplicationEngine GenServer implemented and operational
- [ ] Real-time persona loading and application functional
- [ ] Content processing and optimization implemented
- [ ] Caching layer with TTL and eviction policies operational
- [ ] Agent integration completed with persona state management
- [ ] Session state persistence implemented
- [ ] Performance monitoring and metrics collection functional
- [ ] Hierarchical persona loading with inheritance support
- [ ] Error handling and recovery mechanisms implemented
- [ ] Event system for persona change notifications operational
- [ ] Comprehensive unit tests passing (>90% coverage)
- [ ] Integration tests with Agent system passing
- [ ] Performance benchmarks meeting requirements (<50ms persona application)
- [ ] Memory usage optimization verified
- [ ] Concurrent session support tested and operational
- [ ] Documentation completed for all public APIs
- [ ] Load testing completed with acceptable performance
- [ ] Security validation completed for persona content processing