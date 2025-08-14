# Story 9.5: Template Agent Instantiation & Lifecycle Management

## User Story

**As a** user of TheMaestro  
**I want** a comprehensive template agent instantiation and lifecycle management system that handles agent creation, deployment, monitoring, scaling, and termination  
**so that** I can reliably create agent instances from templates with full lifecycle control, performance monitoring, automatic scaling, graceful shutdown, and complete audit tracking throughout the agent's operational lifespan

## Acceptance Criteria

1. **Rapid Template Instantiation**: Sub-5-second agent instantiation from templates with configuration validation and dependency resolution
2. **Agent Lifecycle Orchestration**: Complete lifecycle management from creation through termination with state tracking and transition validation
3. **Configuration Override System**: Runtime configuration overrides during instantiation with validation and conflict resolution
4. **Deployment Environment Management**: Multi-environment deployment support (development, staging, production) with environment-specific configurations
5. **Agent Health Monitoring**: Continuous health checking, performance monitoring, and automatic recovery mechanisms
6. **Scaling and Load Management**: Automatic and manual scaling based on demand, resource utilization, and performance metrics
7. **Resource Allocation and Limits**: Dynamic resource allocation with enforcement of memory, CPU, and network limits
8. **Agent Session Management**: Session creation, persistence, restoration, and cleanup with conversation state management
9. **Real-time Status Tracking**: Live agent status updates, performance metrics, and operational dashboard integration
10. **Agent Communication Framework**: Inter-agent communication, message routing, and coordination mechanisms
11. **Configuration Hot-Reloading**: Live configuration updates without service interruption and rollback capabilities
12. **Agent Performance Optimization**: Runtime performance tuning, caching optimization, and resource efficiency improvements
13. **Graceful Shutdown Management**: Controlled agent termination with session preservation, data persistence, and cleanup procedures
14. **Agent Backup and Recovery**: Automated state backup, disaster recovery, and point-in-time restoration capabilities
15. **Multi-tenant Agent Isolation**: Secure isolation between different users' agent instances with resource and data segregation
16. **Agent Debugging and Diagnostics**: Comprehensive debugging tools, log analysis, performance profiling, and diagnostic capabilities
17. **Agent Version Management**: Version tracking, upgrade management, compatibility checking, and rollback procedures
18. **Integration Service Management**: Dynamic integration with provider services, MCP servers, and external tools
19. **Agent Analytics and Telemetry**: Comprehensive usage analytics, performance telemetry, and optimization insights
20. **Template Compliance Validation**: Continuous validation of agent behavior against template specifications
21. **Agent Security Management**: Security policy enforcement, access control, vulnerability scanning, and compliance monitoring
22. **Cost Tracking and Optimization**: Resource cost tracking, usage optimization, and budget management
23. **Agent Collaboration Orchestration**: Multi-agent workflows, task delegation, and collaborative execution management
24. **Disaster Recovery and Failover**: Automated failover mechanisms, disaster recovery procedures, and business continuity
25. **Agent Lifecycle Audit Trail**: Complete audit logging of all lifecycle events with compliance reporting and forensic analysis

## Technical Implementation

### Agent Instantiation Engine

```elixir
# lib/the_maestro/agent_lifecycle/instantiation_engine.ex
defmodule TheMaestro.AgentLifecycle.InstantiationEngine do
  @moduledoc """
  High-performance agent instantiation engine with template processing,
  configuration validation, and lifecycle initialization.
  """
  
  use GenServer
  require Logger
  
  alias TheMaestro.AgentTemplates
  alias TheMaestro.AgentLifecycle.{
    Agent,
    ConfigurationProcessor,
    DependencyResolver,
    ResourceAllocator,
    HealthMonitor,
    SessionManager
  }
  alias TheMaestro.Providers.ProviderManager
  alias TheMaestro.MCP.ServerManager
  alias TheMaestro.Personas.PersonaManager

  defstruct [
    :instantiation_pool,
    :resource_manager,
    :dependency_cache,
    :performance_monitor,
    :configuration_validator,
    :lifecycle_registry,
    :health_monitor
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Instantiate an agent from a template with optional configuration overrides
  """
  def instantiate_agent(template_id, user_id, opts \\ %{}) do
    GenServer.call(__MODULE__, {:instantiate_agent, template_id, user_id, opts}, 30_000)
  end

  @doc """
  Get agent instance details and status
  """
  def get_agent_instance(instance_id) do
    GenServer.call(__MODULE__, {:get_agent_instance, instance_id})
  end

  @doc """
  Update agent configuration with hot-reloading
  """
  def update_agent_configuration(instance_id, configuration_updates) do
    GenServer.call(__MODULE__, {:update_agent_configuration, instance_id, configuration_updates})
  end

  @doc """
  Scale agent instance (increase/decrease resources)
  """
  def scale_agent_instance(instance_id, scale_options) do
    GenServer.call(__MODULE__, {:scale_agent_instance, instance_id, scale_options})
  end

  @doc """
  Gracefully terminate agent instance
  """
  def terminate_agent_instance(instance_id, opts \\ %{}) do
    GenServer.call(__MODULE__, {:terminate_agent_instance, instance_id, opts})
  end

  @doc """
  List all agent instances for a user
  """
  def list_user_agent_instances(user_id, filters \\ %{}) do
    GenServer.call(__MODULE__, {:list_user_agent_instances, user_id, filters})
  end

  @doc """
  Get agent performance metrics
  """
  def get_agent_metrics(instance_id) do
    GenServer.call(__MODULE__, {:get_agent_metrics, instance_id})
  end

  # GenServer Callbacks

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{
      instantiation_pool: :poolboy.start_pool(instantiation_worker_pool_config()),
      resource_manager: ResourceAllocator.start_link(),
      dependency_cache: :ets.new(:dependency_cache, [:set, :public]),
      performance_monitor: start_performance_monitor(),
      configuration_validator: ConfigurationProcessor.start_link(),
      lifecycle_registry: Agent.Registry.start_link(),
      health_monitor: HealthMonitor.start_link()
    }
    
    # Setup periodic maintenance
    schedule_maintenance()
    
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:instantiate_agent, template_id, user_id, opts}, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    result = with {:ok, template} <- load_template_with_validation(template_id, user_id),
                  {:ok, processed_config} <- process_template_configuration(template, opts),
                  {:ok, resolved_dependencies} <- resolve_agent_dependencies(processed_config),
                  {:ok, allocated_resources} <- allocate_agent_resources(processed_config, resolved_dependencies),
                  {:ok, agent_instance} <- create_agent_instance(template, processed_config, allocated_resources, user_id),
                  {:ok, _} <- start_agent_services(agent_instance),
                  {:ok, _} <- register_agent_instance(agent_instance, state),
                  :ok <- start_health_monitoring(agent_instance) do
      
      instantiation_time = System.monotonic_time(:millisecond) - start_time
      record_instantiation_metrics(agent_instance.id, instantiation_time, :success)
      
      {:ok, agent_instance}
    else
      error ->
        instantiation_time = System.monotonic_time(:millisecond) - start_time
        record_instantiation_metrics(template_id, instantiation_time, :failure)
        error
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_agent_instance, instance_id}, _from, state) do
    result = case Agent.Registry.lookup(state.lifecycle_registry, instance_id) do
      {:ok, agent_instance} ->
        # Enrich with current metrics and status
        enriched_instance = enrich_agent_instance_data(agent_instance)
        {:ok, enriched_instance}
      
      {:error, :not_found} ->
        {:error, :not_found}
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:update_agent_configuration, instance_id, configuration_updates}, _from, state) do
    result = with {:ok, agent_instance} <- Agent.Registry.lookup(state.lifecycle_registry, instance_id),
                  {:ok, validated_updates} <- validate_configuration_updates(configuration_updates),
                  {:ok, merged_config} <- merge_agent_configuration(agent_instance, validated_updates),
                  {:ok, updated_instance} <- apply_configuration_hot_reload(agent_instance, merged_config),
                  :ok <- update_agent_registry(state.lifecycle_registry, updated_instance) do
      
      record_configuration_update(instance_id, configuration_updates)
      {:ok, updated_instance}
    else
      error -> error
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:scale_agent_instance, instance_id, scale_options}, _from, state) do
    result = with {:ok, agent_instance} <- Agent.Registry.lookup(state.lifecycle_registry, instance_id),
                  {:ok, scaling_plan} <- calculate_scaling_requirements(agent_instance, scale_options),
                  {:ok, new_resources} <- ResourceAllocator.allocate_additional_resources(scaling_plan),
                  {:ok, scaled_instance} <- apply_scaling_changes(agent_instance, new_resources),
                  :ok <- update_agent_registry(state.lifecycle_registry, scaled_instance) do
      
      record_scaling_event(instance_id, scale_options, scaling_plan)
      {:ok, scaled_instance}
    else
      error -> error
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:terminate_agent_instance, instance_id, opts}, _from, state) do
    result = with {:ok, agent_instance} <- Agent.Registry.lookup(state.lifecycle_registry, instance_id),
                  :ok <- initiate_graceful_shutdown(agent_instance, opts),
                  :ok <- persist_agent_state(agent_instance),
                  :ok <- cleanup_agent_resources(agent_instance),
                  :ok <- stop_health_monitoring(agent_instance),
                  :ok <- unregister_agent_instance(state.lifecycle_registry, instance_id) do
      
      record_termination_event(instance_id, opts)
      :ok
    else
      error -> error
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:list_user_agent_instances, user_id, filters}, _from, state) do
    instances = Agent.Registry.list_user_instances(state.lifecycle_registry, user_id)
    filtered_instances = apply_instance_filters(instances, filters)
    enriched_instances = Enum.map(filtered_instances, &enrich_agent_instance_data/1)
    
    {:reply, {:ok, enriched_instances}, state}
  end

  @impl GenServer
  def handle_call({:get_agent_metrics, instance_id}, _from, state) do
    result = case Agent.Registry.lookup(state.lifecycle_registry, instance_id) do
      {:ok, agent_instance} ->
        metrics = collect_agent_performance_metrics(agent_instance)
        {:ok, metrics}
      
      error -> error
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_info(:maintenance, state) do
    perform_lifecycle_maintenance(state)
    schedule_maintenance()
    {:noreply, state}
  end

  def handle_info({:agent_health_check, instance_id, health_status}, state) do
    case health_status do
      :healthy ->
        :ok
      
      :degraded ->
        Logger.warn("Agent #{instance_id} health degraded")
        initiate_recovery_procedures(instance_id, :degraded)
      
      :unhealthy ->
        Logger.error("Agent #{instance_id} unhealthy")
        initiate_recovery_procedures(instance_id, :unhealthy)
      
      :failed ->
        Logger.error("Agent #{instance_id} failed")
        initiate_emergency_recovery(instance_id)
    end
    
    {:noreply, state}
  end

  # Private Implementation Functions

  defp load_template_with_validation(template_id, user_id) do
    case AgentTemplates.get_template(template_id, user_id: user_id) do
      {:ok, template} ->
        case validate_template_for_instantiation(template) do
          :ok -> {:ok, template}
          error -> error
        end
      
      error -> error
    end
  end

  defp process_template_configuration(template, opts) do
    base_config = extract_template_configuration(template)
    overrides = Map.get(opts, :configuration_overrides, %{})
    environment = Map.get(opts, :environment, :development)
    
    case ConfigurationProcessor.process_configuration(base_config, overrides, environment) do
      {:ok, processed_config} ->
        {:ok, Map.put(processed_config, :template_id, template.id)}
      
      error -> error
    end
  end

  defp resolve_agent_dependencies(configuration) do
    case DependencyResolver.resolve_all_dependencies(configuration) do
      {:ok, resolved_deps} ->
        # Cache dependencies for future instantiations
        cache_resolved_dependencies(configuration, resolved_deps)
        {:ok, resolved_deps}
      
      error -> error
    end
  end

  defp allocate_agent_resources(configuration, dependencies) do
    resource_requirements = calculate_resource_requirements(configuration, dependencies)
    
    case ResourceAllocator.allocate_resources(resource_requirements) do
      {:ok, allocated_resources} ->
        {:ok, allocated_resources}
      
      {:error, :insufficient_resources} ->
        {:error, "Insufficient resources available for agent instantiation"}
      
      error -> error
    end
  end

  defp create_agent_instance(template, configuration, resources, user_id) do
    instance_id = generate_agent_instance_id()
    
    agent_instance = %Agent{
      id: instance_id,
      template_id: template.id,
      template_name: template.name,
      user_id: user_id,
      configuration: configuration,
      allocated_resources: resources,
      status: :initializing,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      health_status: :unknown,
      performance_metrics: %{},
      session_data: %{},
      lifecycle_events: []
    }
    
    {:ok, agent_instance}
  end

  defp start_agent_services(agent_instance) do
    with {:ok, _} <- initialize_provider_services(agent_instance),
         {:ok, _} <- initialize_persona_services(agent_instance),
         {:ok, _} <- initialize_mcp_services(agent_instance),
         {:ok, _} <- initialize_session_management(agent_instance) do
      :ok
    else
      error ->
        cleanup_partial_initialization(agent_instance)
        error
    end
  end

  defp initialize_provider_services(agent_instance) do
    provider_config = agent_instance.configuration.provider_config
    
    case ProviderManager.initialize_for_agent(agent_instance.id, provider_config) do
      {:ok, provider_context} ->
        updated_instance = %{agent_instance | provider_context: provider_context}
        {:ok, updated_instance}
      
      error -> error
    end
  end

  defp initialize_persona_services(agent_instance) do
    persona_config = agent_instance.configuration.persona_config
    
    case PersonaManager.load_persona_for_agent(agent_instance.id, persona_config) do
      {:ok, persona_context} ->
        updated_instance = %{agent_instance | persona_context: persona_context}
        {:ok, updated_instance}
      
      error -> error
    end
  end

  defp initialize_mcp_services(agent_instance) do
    tool_config = agent_instance.configuration.tool_config
    
    case ServerManager.initialize_servers_for_agent(agent_instance.id, tool_config) do
      {:ok, mcp_context} ->
        updated_instance = %{agent_instance | mcp_context: mcp_context}
        {:ok, updated_instance}
      
      error -> error
    end
  end

  defp initialize_session_management(agent_instance) do
    session_config = agent_instance.configuration.deployment_config
    
    case SessionManager.create_session_for_agent(agent_instance.id, session_config) do
      {:ok, session_context} ->
        updated_instance = %{agent_instance | session_context: session_context}
        {:ok, updated_instance}
      
      error -> error
    end
  end

  defp register_agent_instance(agent_instance, state) do
    case Agent.Registry.register(state.lifecycle_registry, agent_instance) do
      :ok ->
        record_lifecycle_event(agent_instance.id, :instantiated)
        {:ok, agent_instance}
      
      error -> error
    end
  end

  defp start_health_monitoring(agent_instance) do
    HealthMonitor.start_monitoring(agent_instance.id, %{
      check_interval: 30_000,  # 30 seconds
      timeout: 5_000,         # 5 seconds
      failure_threshold: 3,   # 3 consecutive failures
      recovery_threshold: 2   # 2 consecutive successes
    })
  end

  # Configuration Management

  defp validate_configuration_updates(updates) do
    case ConfigurationProcessor.validate_updates(updates) do
      {:ok, validated_updates} ->
        {:ok, validated_updates}
      
      {:error, validation_errors} ->
        {:error, "Configuration validation failed: #{inspect(validation_errors)}"}
    end
  end

  defp merge_agent_configuration(agent_instance, updates) do
    merged_config = ConfigurationProcessor.merge_configurations(
      agent_instance.configuration,
      updates
    )
    
    {:ok, merged_config}
  end

  defp apply_configuration_hot_reload(agent_instance, new_configuration) do
    # Apply configuration changes without stopping the agent
    with :ok <- update_provider_configuration(agent_instance, new_configuration.provider_config),
         :ok <- update_persona_configuration(agent_instance, new_configuration.persona_config),
         :ok <- update_tool_configuration(agent_instance, new_configuration.tool_config) do
      
      updated_instance = %{agent_instance | 
        configuration: new_configuration,
        updated_at: DateTime.utc_now()
      }
      
      record_lifecycle_event(agent_instance.id, :configuration_updated)
      {:ok, updated_instance}
    else
      error -> error
    end
  end

  # Scaling Management

  defp calculate_scaling_requirements(agent_instance, scale_options) do
    current_resources = agent_instance.allocated_resources
    target_scale = Map.get(scale_options, :target_scale, 1.0)
    
    scaling_plan = %{
      memory_adjustment: trunc(current_resources.memory_mb * target_scale) - current_resources.memory_mb,
      cpu_adjustment: (current_resources.cpu_cores * target_scale) - current_resources.cpu_cores,
      concurrent_requests_adjustment: trunc(current_resources.max_concurrent_requests * target_scale) - current_resources.max_concurrent_requests
    }
    
    {:ok, scaling_plan}
  end

  defp apply_scaling_changes(agent_instance, new_resources) do
    # Apply resource scaling
    updated_instance = %{agent_instance |
      allocated_resources: new_resources,
      updated_at: DateTime.utc_now()
    }
    
    # Update runtime resource limits
    case update_runtime_resource_limits(agent_instance.id, new_resources) do
      :ok ->
        record_lifecycle_event(agent_instance.id, :scaled)
        {:ok, updated_instance}
      
      error -> error
    end
  end

  # Termination and Cleanup

  defp initiate_graceful_shutdown(agent_instance, opts) do
    shutdown_timeout = Map.get(opts, :timeout, 30_000)
    force_shutdown = Map.get(opts, :force, false)
    
    Logger.info("Initiating graceful shutdown for agent #{agent_instance.id}")
    
    # Signal agent to stop accepting new requests
    Agent.Registry.mark_for_termination(agent_instance.id)
    
    # Wait for ongoing requests to complete
    if not force_shutdown do
      wait_for_request_completion(agent_instance.id, shutdown_timeout)
    end
    
    :ok
  end

  defp persist_agent_state(agent_instance) do
    # Save conversation state, configuration, and metrics
    case Agent.StateManager.persist_state(agent_instance) do
      :ok ->
        record_lifecycle_event(agent_instance.id, :state_persisted)
        :ok
      
      error ->
        Logger.error("Failed to persist agent state: #{inspect(error)}")
        error
    end
  end

  defp cleanup_agent_resources(agent_instance) do
    # Clean up provider connections
    ProviderManager.cleanup_agent_resources(agent_instance.id)
    
    # Clean up MCP server connections
    ServerManager.cleanup_agent_resources(agent_instance.id)
    
    # Clean up session data
    SessionManager.cleanup_agent_session(agent_instance.id)
    
    # Release allocated resources
    ResourceAllocator.release_resources(agent_instance.allocated_resources)
    
    record_lifecycle_event(agent_instance.id, :resources_cleaned)
    :ok
  end

  # Monitoring and Metrics

  defp enrich_agent_instance_data(agent_instance) do
    current_metrics = collect_agent_performance_metrics(agent_instance)
    health_status = HealthMonitor.get_health_status(agent_instance.id)
    
    %{agent_instance |
      performance_metrics: current_metrics,
      health_status: health_status,
      enriched_at: DateTime.utc_now()
    }
  end

  defp collect_agent_performance_metrics(agent_instance) do
    %{
      response_time_ms: get_average_response_time(agent_instance.id),
      requests_per_minute: get_requests_per_minute(agent_instance.id),
      memory_usage_mb: get_memory_usage(agent_instance.id),
      cpu_utilization: get_cpu_utilization(agent_instance.id),
      error_rate: get_error_rate(agent_instance.id),
      uptime_seconds: calculate_uptime(agent_instance),
      last_activity: get_last_activity_time(agent_instance.id)
    }
  end

  # Recovery and Failover

  defp initiate_recovery_procedures(instance_id, severity) do
    case severity do
      :degraded ->
        # Attempt soft recovery
        attempt_soft_recovery(instance_id)
      
      :unhealthy ->
        # Attempt restart
        attempt_agent_restart(instance_id)
    end
  end

  defp initiate_emergency_recovery(instance_id) do
    Logger.error("Initiating emergency recovery for agent #{instance_id}")
    
    # Force restart or failover
    case attempt_emergency_restart(instance_id) do
      :ok ->
        record_lifecycle_event(instance_id, :emergency_recovery_successful)
      
      {:error, _reason} ->
        record_lifecycle_event(instance_id, :emergency_recovery_failed)
        # Escalate to manual intervention
        escalate_to_manual_intervention(instance_id)
    end
  end

  # Utility Functions

  defp generate_agent_instance_id do
    "agent_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp extract_template_configuration(template) do
    %{
      provider_config: template.provider_config,
      persona_config: template.persona_config,
      tool_config: template.tool_config,
      prompt_config: template.prompt_config,
      deployment_config: template.deployment_config
    }
  end

  defp calculate_resource_requirements(configuration, dependencies) do
    base_requirements = %{
      memory_mb: 256,
      cpu_cores: 0.5,
      max_concurrent_requests: 5
    }
    
    # Adjust based on configuration complexity
    adjusted_requirements = adjust_for_configuration_complexity(base_requirements, configuration)
    
    # Adjust based on dependencies
    final_requirements = adjust_for_dependencies(adjusted_requirements, dependencies)
    
    final_requirements
  end

  defp record_instantiation_metrics(instance_id, duration_ms, result) do
    :telemetry.execute([:agent, :instantiation], %{
      duration: duration_ms,
      result: result
    }, %{instance_id: instance_id})
  end

  defp record_lifecycle_event(instance_id, event_type) do
    :telemetry.execute([:agent, :lifecycle], %{
      event: event_type,
      timestamp: DateTime.utc_now()
    }, %{instance_id: instance_id})
  end

  defp schedule_maintenance do
    Process.send_after(__MODULE__, :maintenance, 60_000)  # 1 minute
  end

  defp perform_lifecycle_maintenance(state) do
    # Clean up terminated agents
    # Update performance metrics
    # Check resource utilization
    # Optimize resource allocation
    :ok
  end

  # Pool configuration for instantiation workers
  defp instantiation_worker_pool_config do
    [
      name: {:local, :instantiation_worker_pool},
      worker_module: TheMaestro.AgentLifecycle.InstantiationWorker,
      size: 10,
      max_overflow: 5
    ]
  end

  # Placeholder implementations for complex functions
  defp validate_template_for_instantiation(_template), do: :ok
  defp cache_resolved_dependencies(_config, _deps), do: :ok
  defp cleanup_partial_initialization(_instance), do: :ok
  defp update_agent_registry(_registry, _instance), do: :ok
  defp apply_instance_filters(instances, _filters), do: instances
  defp update_provider_configuration(_instance, _config), do: :ok
  defp update_persona_configuration(_instance, _config), do: :ok
  defp update_tool_configuration(_instance, _config), do: :ok
  defp update_runtime_resource_limits(_instance_id, _resources), do: :ok
  defp wait_for_request_completion(_instance_id, _timeout), do: :ok
  defp stop_health_monitoring(_instance), do: :ok
  defp unregister_agent_instance(_registry, _instance_id), do: :ok
  defp get_average_response_time(_instance_id), do: 150
  defp get_requests_per_minute(_instance_id), do: 10
  defp get_memory_usage(_instance_id), do: 128
  defp get_cpu_utilization(_instance_id), do: 15.5
  defp get_error_rate(_instance_id), do: 0.02
  defp calculate_uptime(instance), do: DateTime.diff(DateTime.utc_now(), instance.created_at)
  defp get_last_activity_time(_instance_id), do: DateTime.utc_now()
  defp attempt_soft_recovery(_instance_id), do: :ok
  defp attempt_agent_restart(_instance_id), do: :ok
  defp attempt_emergency_restart(_instance_id), do: :ok
  defp escalate_to_manual_intervention(_instance_id), do: :ok
  defp adjust_for_configuration_complexity(reqs, _config), do: reqs
  defp adjust_for_dependencies(reqs, _deps), do: reqs
  defp record_configuration_update(_instance_id, _updates), do: :ok
  defp record_scaling_event(_instance_id, _options, _plan), do: :ok
  defp record_termination_event(_instance_id, _opts), do: :ok
  defp start_performance_monitor, do: :ok
end
```

### Agent Lifecycle Registry

```elixir
# lib/the_maestro/agent_lifecycle/agent_registry.ex
defmodule TheMaestro.AgentLifecycle.Agent.Registry do
  @moduledoc """
  Centralized registry for tracking agent instance lifecycle and state.
  """
  
  use GenServer
  
  alias TheMaestro.AgentLifecycle.Agent

  defstruct [
    :agents,           # ETS table for agent storage
    :user_index,       # ETS table for user -> agents mapping
    :status_index,     # ETS table for status -> agents mapping
    :metrics_cache,    # Performance metrics cache
    :lifecycle_log     # Audit trail of lifecycle events
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register(registry \\ __MODULE__, agent_instance) do
    GenServer.call(registry, {:register, agent_instance})
  end

  def lookup(registry \\ __MODULE__, instance_id) do
    GenServer.call(registry, {:lookup, instance_id})
  end

  def update(registry \\ __MODULE__, instance_id, updates) do
    GenServer.call(registry, {:update, instance_id, updates})
  end

  def list_user_instances(registry \\ __MODULE__, user_id) do
    GenServer.call(registry, {:list_user_instances, user_id})
  end

  def list_instances_by_status(registry \\ __MODULE__, status) do
    GenServer.call(registry, {:list_instances_by_status, status})
  end

  def mark_for_termination(registry \\ __MODULE__, instance_id) do
    GenServer.call(registry, {:mark_for_termination, instance_id})
  end

  def remove(registry \\ __MODULE__, instance_id) do
    GenServer.call(registry, {:remove, instance_id})
  end

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{
      agents: :ets.new(:agents, [:set, :protected]),
      user_index: :ets.new(:user_agents, [:bag, :protected]),
      status_index: :ets.new(:status_agents, [:bag, :protected]),
      metrics_cache: :ets.new(:agent_metrics, [:set, :protected]),
      lifecycle_log: :ets.new(:lifecycle_log, [:ordered_set, :protected])
    }
    
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register, agent_instance}, _from, state) do
    instance_id = agent_instance.id
    
    # Store agent instance
    :ets.insert(state.agents, {instance_id, agent_instance})
    
    # Update indexes
    :ets.insert(state.user_index, {agent_instance.user_id, instance_id})
    :ets.insert(state.status_index, {agent_instance.status, instance_id})
    
    # Log registration event
    log_event = {System.monotonic_time(), instance_id, :registered, %{}}
    :ets.insert(state.lifecycle_log, log_event)
    
    {:reply, :ok, state}
  end

  def handle_call({:lookup, instance_id}, _from, state) do
    result = case :ets.lookup(state.agents, instance_id) do
      [{^instance_id, agent_instance}] -> {:ok, agent_instance}
      [] -> {:error, :not_found}
    end
    
    {:reply, result, state}
  end

  def handle_call({:update, instance_id, updates}, _from, state) do
    result = case :ets.lookup(state.agents, instance_id) do
      [{^instance_id, agent_instance}] ->
        updated_instance = Map.merge(agent_instance, updates)
        updated_instance = %{updated_instance | updated_at: DateTime.utc_now()}
        
        # Update main record
        :ets.insert(state.agents, {instance_id, updated_instance})
        
        # Update status index if status changed
        if Map.has_key?(updates, :status) do
          :ets.delete_object(state.status_index, {agent_instance.status, instance_id})
          :ets.insert(state.status_index, {updated_instance.status, instance_id})
        end
        
        # Log update event
        log_event = {System.monotonic_time(), instance_id, :updated, updates}
        :ets.insert(state.lifecycle_log, log_event)
        
        {:ok, updated_instance}
      
      [] -> 
        {:error, :not_found}
    end
    
    {:reply, result, state}
  end

  def handle_call({:list_user_instances, user_id}, _from, state) do
    instance_ids = :ets.lookup(state.user_index, user_id)
                   |> Enum.map(fn {_, instance_id} -> instance_id end)
    
    instances = Enum.map(instance_ids, fn instance_id ->
      case :ets.lookup(state.agents, instance_id) do
        [{^instance_id, agent_instance}] -> agent_instance
        [] -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    
    {:reply, instances, state}
  end

  def handle_call({:list_instances_by_status, status}, _from, state) do
    instance_ids = :ets.lookup(state.status_index, status)
                   |> Enum.map(fn {_, instance_id} -> instance_id end)
    
    instances = Enum.map(instance_ids, fn instance_id ->
      case :ets.lookup(state.agents, instance_id) do
        [{^instance_id, agent_instance}] -> agent_instance
        [] -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    
    {:reply, instances, state}
  end

  def handle_call({:mark_for_termination, instance_id}, _from, state) do
    result = case :ets.lookup(state.agents, instance_id) do
      [{^instance_id, agent_instance}] ->
        updated_instance = %{agent_instance | 
          status: :terminating,
          updated_at: DateTime.utc_now()
        }
        
        :ets.insert(state.agents, {instance_id, updated_instance})
        :ets.delete_object(state.status_index, {agent_instance.status, instance_id})
        :ets.insert(state.status_index, {:terminating, instance_id})
        
        # Log termination event
        log_event = {System.monotonic_time(), instance_id, :marked_for_termination, %{}}
        :ets.insert(state.lifecycle_log, log_event)
        
        :ok
      
      [] -> 
        {:error, :not_found}
    end
    
    {:reply, result, state}
  end

  def handle_call({:remove, instance_id}, _from, state) do
    result = case :ets.lookup(state.agents, instance_id) do
      [{^instance_id, agent_instance}] ->
        # Remove from all tables and indexes
        :ets.delete(state.agents, instance_id)
        :ets.delete_object(state.user_index, {agent_instance.user_id, instance_id})
        :ets.delete_object(state.status_index, {agent_instance.status, instance_id})
        :ets.delete(state.metrics_cache, instance_id)
        
        # Log removal event
        log_event = {System.monotonic_time(), instance_id, :removed, %{}}
        :ets.insert(state.lifecycle_log, log_event)
        
        :ok
      
      [] -> 
        {:error, :not_found}
    end
    
    {:reply, result, state}
  end
end
```

### Agent Health Monitor

```elixir
# lib/the_maestro/agent_lifecycle/health_monitor.ex
defmodule TheMaestro.AgentLifecycle.HealthMonitor do
  @moduledoc """
  Continuous health monitoring system for agent instances with
  automatic recovery and alerting capabilities.
  """
  
  use GenServer
  require Logger

  defstruct [
    :monitoring_tasks,    # Map of instance_id -> monitoring task
    :health_history,      # ETS table for health history
    :alert_manager,       # Alert notification manager
    :recovery_strategies  # Recovery strategy configurations
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_monitoring(instance_id, config \\ %{}) do
    GenServer.call(__MODULE__, {:start_monitoring, instance_id, config})
  end

  def stop_monitoring(instance_id) do
    GenServer.call(__MODULE__, {:stop_monitoring, instance_id})
  end

  def get_health_status(instance_id) do
    GenServer.call(__MODULE__, {:get_health_status, instance_id})
  end

  def get_health_history(instance_id, opts \\ %{}) do
    GenServer.call(__MODULE__, {:get_health_history, instance_id, opts})
  end

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{
      monitoring_tasks: %{},
      health_history: :ets.new(:health_history, [:ordered_set, :protected]),
      alert_manager: start_alert_manager(),
      recovery_strategies: load_recovery_strategies()
    }
    
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:start_monitoring, instance_id, config}, _from, state) do
    default_config = %{
      check_interval: 30_000,  # 30 seconds
      timeout: 5_000,         # 5 seconds
      failure_threshold: 3,   # 3 consecutive failures
      recovery_threshold: 2   # 2 consecutive successes
    }
    
    monitoring_config = Map.merge(default_config, config)
    
    # Start monitoring task
    task = Task.async(fn ->
      monitor_agent_health(instance_id, monitoring_config)
    end)
    
    updated_tasks = Map.put(state.monitoring_tasks, instance_id, task)
    updated_state = %{state | monitoring_tasks: updated_tasks}
    
    Logger.info("Started health monitoring for agent #{instance_id}")
    {:reply, :ok, updated_state}
  end

  def handle_call({:stop_monitoring, instance_id}, _from, state) do
    case Map.get(state.monitoring_tasks, instance_id) do
      nil -> 
        {:reply, {:error, :not_monitoring}, state}
      
      task ->
        Task.shutdown(task, :brutal_kill)
        updated_tasks = Map.delete(state.monitoring_tasks, instance_id)
        updated_state = %{state | monitoring_tasks: updated_tasks}
        
        Logger.info("Stopped health monitoring for agent #{instance_id}")
        {:reply, :ok, updated_state}
    end
  end

  def handle_call({:get_health_status, instance_id}, _from, state) do
    # Get latest health check result
    case :ets.select(state.health_history, [
      {{instance_id, :"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}
    ]) do
      [] -> 
        {:reply, {:error, :no_data}, state}
      
      results ->
        latest_result = List.last(Enum.sort(results))
        {:reply, {:ok, elem(latest_result, 1)}, state}
    end
  end

  def handle_call({:get_health_history, instance_id, opts}, _from, state) do
    limit = Map.get(opts, :limit, 100)
    since = Map.get(opts, :since, DateTime.add(DateTime.utc_now(), -3600)) # Last hour
    
    pattern = {{instance_id, :"$1", :"$2"}, 
               [{:>=, :"$1", datetime_to_timestamp(since)}], 
               [{{:"$1", :"$2"}}]}
    
    results = :ets.select(state.health_history, [pattern], limit)
    
    history = case results do
      {matches, _continuation} -> matches
      matches when is_list(matches) -> matches
      :"$end_of_table" -> []
    end
    
    {:reply, {:ok, history}, state}
  end

  # Health monitoring implementation

  defp monitor_agent_health(instance_id, config) do
    consecutive_failures = 0
    consecutive_successes = 0
    
    monitor_loop(instance_id, config, consecutive_failures, consecutive_successes)
  end

  defp monitor_loop(instance_id, config, failures, successes) do
    # Perform health check
    health_result = perform_health_check(instance_id, config.timeout)
    
    # Record health check result
    record_health_check(instance_id, health_result)
    
    {new_failures, new_successes, health_status} = case health_result do
      :healthy ->
        new_successes = successes + 1
        new_failures = 0
        
        status = if new_successes >= config.recovery_threshold and failures > 0 do
          :recovered
        else
          :healthy
        end
        
        {new_failures, new_successes, status}
      
      :degraded ->
        {failures + 1, 0, :degraded}
      
      :unhealthy ->
        new_failures = failures + 1
        
        status = if new_failures >= config.failure_threshold do
          :failed
        else
          :unhealthy
        end
        
        {new_failures, 0, status}
    end
    
    # Notify monitoring system
    notify_health_status(instance_id, health_status)
    
    # Sleep until next check
    Process.sleep(config.check_interval)
    
    # Continue monitoring loop
    monitor_loop(instance_id, config, new_failures, new_successes)
  end

  defp perform_health_check(instance_id, timeout) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      # Check agent responsiveness
      case check_agent_responsiveness(instance_id, timeout) do
        :ok ->
          # Check resource utilization
          case check_resource_utilization(instance_id) do
            :ok -> :healthy
            :degraded -> :degraded
            :critical -> :unhealthy
          end
        
        :timeout -> :unhealthy
        :error -> :unhealthy
      end
    rescue
      _ -> :unhealthy
    after
      duration = System.monotonic_time(:millisecond) - start_time
      record_health_check_duration(instance_id, duration)
    end
  end

  defp check_agent_responsiveness(instance_id, timeout) do
    # Send ping request to agent
    case GenServer.call({:agent, instance_id}, :health_ping, timeout) do
      :pong -> :ok
      _ -> :error
    catch
      :exit, {:timeout, _} -> :timeout
      :exit, _ -> :error
    end
  end

  defp check_resource_utilization(instance_id) do
    case get_agent_resource_usage(instance_id) do
      {:ok, usage} ->
        memory_usage = usage.memory_percentage
        cpu_usage = usage.cpu_percentage
        
        cond do
          memory_usage > 90 or cpu_usage > 90 -> :critical
          memory_usage > 75 or cpu_usage > 75 -> :degraded
          true -> :ok
        end
      
      {:error, _} -> :degraded
    end
  end

  defp record_health_check(instance_id, result) do
    timestamp = System.monotonic_time(:millisecond)
    health_entry = {instance_id, timestamp, result}
    
    :ets.insert(__MODULE__.health_history, health_entry)
    
    # Clean up old entries (keep last 1000 per agent)
    cleanup_old_health_records(instance_id)
  end

  defp notify_health_status(instance_id, health_status) do
    # Send health status to the instantiation engine
    send(TheMaestro.AgentLifecycle.InstantiationEngine, 
         {:agent_health_check, instance_id, health_status})
    
    # Log significant health changes
    case health_status do
      :failed -> Logger.error("Agent #{instance_id} failed health checks")
      :recovered -> Logger.info("Agent #{instance_id} recovered")
      _ -> :ok
    end
  end

  # Utility functions

  defp datetime_to_timestamp(datetime) do
    DateTime.to_unix(datetime, :millisecond)
  end

  defp start_alert_manager do
    # Start alert notification system
    :ok
  end

  defp load_recovery_strategies do
    # Load recovery strategy configurations
    %{}
  end

  defp get_agent_resource_usage(_instance_id) do
    # Mock resource usage data
    {:ok, %{
      memory_percentage: :rand.uniform(100),
      cpu_percentage: :rand.uniform(100)
    }}
  end

  defp record_health_check_duration(_instance_id, _duration) do
    # Record performance metrics
    :ok
  end

  defp cleanup_old_health_records(instance_id) do
    # Keep only the latest 1000 records per agent
    pattern = {{instance_id, :"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}
    
    all_records = :ets.select(__MODULE__.health_history, [pattern])
    
    if length(all_records) > 1000 do
      sorted_records = Enum.sort(all_records, fn {t1, _}, {t2, _} -> t1 <= t2 end)
      old_records = Enum.take(sorted_records, length(all_records) - 1000)
      
      Enum.each(old_records, fn {timestamp, _} ->
        :ets.delete_object(__MODULE__.health_history, {instance_id, timestamp, :_})
      end)
    end
  end
end
```

## Module Structure

```
lib/the_maestro/agent_lifecycle/
├── instantiation_engine.ex          # Main instantiation engine
├── agent.ex                        # Agent instance struct and utilities
├── agent_registry.ex               # Agent lifecycle registry
├── configuration_processor.ex      # Configuration processing and validation
├── dependency_resolver.ex          # Dependency resolution system
├── resource_allocator.ex          # Resource allocation management
├── health_monitor.ex               # Health monitoring and recovery
├── session_manager.ex              # Session lifecycle management
├── performance_monitor.ex          # Performance metrics collection
├── scaling_manager.ex              # Auto-scaling and resource management
├── backup_manager.ex               # State backup and recovery
├── security_manager.ex             # Security policy enforcement
└── analytics_collector.ex          # Usage analytics and telemetry
```

## Integration Points

1. **Epic 5 Integration**: Provider service initialization and management
2. **Epic 6 Integration**: MCP server lifecycle and tool coordination
3. **Epic 7 Integration**: Prompt processing and context management
4. **Epic 8 Integration**: Persona loading and behavioral configuration
5. **Storage System**: Template loading and configuration processing
6. **Authentication**: User permission validation and multi-tenant isolation

## Performance Considerations

- Parallel agent instantiation with resource pool management
- Efficient resource allocation with automatic scaling
- Performance monitoring with real-time optimization
- Memory-efficient state management with lazy loading
- Background health monitoring with minimal overhead

## Security Considerations

- Multi-tenant isolation with resource segregation
- Permission validation at instantiation and runtime
- Secure configuration handling with encryption
- Audit logging for compliance and forensic analysis
- Network security with encrypted communication

## Dependencies

- Epic 5: Model Choice & Authentication System
- Epic 6: MCP Protocol Implementation
- Epic 7: Enhanced Prompt Handling System
- Epic 8: Persona Management System
- Epic 9.2: Template Agent Storage & Retrieval System
- Elixir GenServer for concurrent processing
- ETS for high-performance in-memory storage

## Definition of Done

- [ ] Sub-5-second agent instantiation from templates
- [ ] Complete lifecycle orchestration with state tracking
- [ ] Configuration override system with validation
- [ ] Multi-environment deployment support
- [ ] Continuous health monitoring with automatic recovery
- [ ] Auto-scaling based on demand and performance metrics
- [ ] Dynamic resource allocation with limit enforcement
- [ ] Agent session management with state persistence
- [ ] Real-time status tracking with dashboard integration
- [ ] Inter-agent communication framework
- [ ] Configuration hot-reloading without service interruption
- [ ] Runtime performance optimization and tuning
- [ ] Graceful shutdown with session preservation
- [ ] Automated backup and disaster recovery
- [ ] Multi-tenant isolation with security enforcement
- [ ] Comprehensive debugging and diagnostic tools
- [ ] Agent version management with upgrade capabilities
- [ ] Dynamic integration service management
- [ ] Usage analytics and performance telemetry
- [ ] Template compliance validation system
- [ ] Security policy enforcement and monitoring
- [ ] Cost tracking and optimization features
- [ ] Multi-agent collaboration orchestration
- [ ] Disaster recovery and failover mechanisms
- [ ] Complete audit trail with compliance reporting
- [ ] Comprehensive unit tests with >95% coverage
- [ ] Integration tests with all dependent Epic systems
- [ ] Load testing validation for 1000+ concurrent agents
- [ ] Performance benchmarks meeting sub-5-second instantiation
- [ ] Security testing with penetration testing validation
- [ ] Disaster recovery testing with failover validation
- [ ] Complete lifecycle management documentation
- [ ] Operational runbooks for troubleshooting and maintenance