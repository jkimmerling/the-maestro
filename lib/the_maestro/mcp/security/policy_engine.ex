defmodule TheMaestro.MCP.Security.PolicyEngine do
  @moduledoc """
  Security policy management and enforcement system for MCP tools.
  
  Provides centralized policy management with support for:
  - Global security policies
  - Per-user policy overrides  
  - Per-server policy settings
  - Time-based policy changes
  - Emergency policy activation
  - Policy inheritance and precedence
  
  ## Policy Types
  
  - **Global Policies**: System-wide default security settings
  - **User Policies**: User-specific security overrides
  - **Server Policies**: Server-specific security rules
  - **Tool Policies**: Tool-specific security configurations
  - **Time-based Policies**: Policies that activate based on time/date
  - **Emergency Policies**: High-security policies for incident response
  
  ## Policy Precedence
  
  Policies are evaluated in order of precedence (highest to lowest):
  1. Emergency policies (active incidents)
  2. User-specific policies
  3. Tool-specific policies
  4. Server-specific policies
  5. Time-based policies (if active)
  6. Global default policies
  """
  
  use GenServer
  require Logger
  
  alias TheMaestro.MCP.Security.{Permissions, AuditLogger}
  
  @type policy_level :: :emergency | :user | :tool | :server | :time_based | :global
  @type policy_status :: :active | :inactive | :suspended | :expired
  
  @type policy :: %{
    id: String.t(),
    name: String.t(),
    description: String.t(),
    level: policy_level(),
    status: policy_status(),
    settings: map(),
    conditions: map(),
    created_by: String.t(),
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    expires_at: DateTime.t() | nil,
    priority: non_neg_integer()
  }
  
  defmodule PolicyState do
    @moduledoc false
    @type t :: %__MODULE__{
      policies: %{String.t() => map()},
      global_settings: map(),
      emergency_mode: boolean(),
      policy_cache: %{String.t() => map()},
      last_policy_check: DateTime.t()
    }
    
    defstruct [
      policies: %{},
      global_settings: %{},
      emergency_mode: false,
      policy_cache: %{},
      last_policy_check: nil
    ]
  end
  
  ## Public API
  
  @doc """
  Starts the policy engine GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets the effective security policy for a context.
  
  Evaluates all applicable policies and returns the merged result
  based on policy precedence rules.
  """
  @spec get_effective_policy(map()) :: {:ok, map()} | {:error, String.t()}
  def get_effective_policy(context) do
    GenServer.call(__MODULE__, {:get_effective_policy, context})
  end
  
  @doc """
  Creates or updates a security policy.
  """
  @spec update_policy(String.t(), map()) :: :ok | {:error, String.t()}
  def update_policy(policy_id, policy_data) do
    GenServer.call(__MODULE__, {:update_policy, policy_id, policy_data})
  end
  
  @doc """
  Deletes a security policy.
  """
  @spec delete_policy(String.t()) :: :ok | {:error, String.t()}
  def delete_policy(policy_id) do
    GenServer.call(__MODULE__, {:delete_policy, policy_id})
  end
  
  @doc """
  Sets global security settings.
  """
  @spec set_global_settings(map()) :: :ok
  def set_global_settings(settings) do
    GenServer.call(__MODULE__, {:set_global_settings, settings})
  end
  
  @doc """
  Gets current global security settings.
  """
  @spec get_global_settings() :: map()
  def get_global_settings() do
    GenServer.call(__MODULE__, :get_global_settings)
  end
  
  @doc """
  Activates emergency security mode.
  """
  @spec activate_emergency_mode(String.t(), String.t()) :: :ok
  def activate_emergency_mode(reason, activated_by) do
    GenServer.call(__MODULE__, {:activate_emergency_mode, reason, activated_by})
  end
  
  @doc """
  Deactivates emergency security mode.
  """
  @spec deactivate_emergency_mode(String.t()) :: :ok  
  def deactivate_emergency_mode(deactivated_by) do
    GenServer.call(__MODULE__, {:deactivate_emergency_mode, deactivated_by})
  end
  
  @doc """
  Checks if emergency mode is active.
  """
  @spec emergency_mode_active?() :: boolean()
  def emergency_mode_active?() do
    GenServer.call(__MODULE__, :emergency_mode_active?)
  end
  
  @doc """
  Lists all policies matching optional filters.
  """
  @spec list_policies(keyword()) :: [policy()]
  def list_policies(filters \\ []) do
    GenServer.call(__MODULE__, {:list_policies, filters})
  end
  
  @doc """
  Validates a policy configuration.
  """
  @spec validate_policy(map()) :: {:ok, map()} | {:error, [String.t()]}
  def validate_policy(policy_data) do
    GenServer.call(__MODULE__, {:validate_policy, policy_data})
  end
  
  @doc """
  Gets policy evaluation history for auditing.
  """
  @spec get_policy_history(String.t(), keyword()) :: [map()]
  def get_policy_history(context_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_policy_history, context_id, opts})
  end
  
  ## GenServer Implementation
  
  @impl GenServer
  def init(opts) do
    Logger.info("Starting MCP Security Policy Engine")
    
    initial_policies = Keyword.get(opts, :initial_policies, %{})
    global_settings = Keyword.get(opts, :global_settings, default_global_settings())
    
    state = %PolicyState{
      policies: initial_policies,
      global_settings: global_settings,
      last_policy_check: DateTime.utc_now()
    }
    
    # Load policies from configuration if available
    state = load_configuration_policies(state)
    
    # Schedule periodic policy cleanup
    :timer.send_interval(60_000, self(), :cleanup_expired_policies)
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:get_effective_policy, context}, _from, state) do
    try do
      effective_policy = evaluate_effective_policy(context, state)
      cache_key = generate_cache_key(context)
      
      new_state = %{state | 
        policy_cache: Map.put(state.policy_cache, cache_key, effective_policy),
        last_policy_check: DateTime.utc_now()
      }
      
      {:reply, {:ok, effective_policy}, new_state}
    catch
      error -> 
        Logger.error("Policy evaluation failed", error: error, context: context)
        {:reply, {:error, "Policy evaluation failed: #{inspect(error)}"}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:update_policy, policy_id, policy_data}, _from, state) do
    case validate_policy_data(policy_data) do
      {:ok, validated_policy} ->
        policy = Map.merge(validated_policy, %{
          id: policy_id,
          updated_at: DateTime.utc_now()
        })
        
        new_policies = Map.put(state.policies, policy_id, policy)
        new_state = %{state | 
          policies: new_policies,
          policy_cache: %{}  # Clear cache after policy update
        }
        
        # Log policy change - using info level for policy updates
        Logger.info("Policy updated", policy_id: policy_id, level: policy.level)
        
        {:reply, :ok, new_state}
        
      {:error, errors} ->
        {:reply, {:error, "Policy validation failed: #{Enum.join(errors, ", ")}"}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:delete_policy, policy_id}, _from, state) do
    case Map.get(state.policies, policy_id) do
      nil ->
        {:reply, {:error, "Policy not found"}, state}
        
      policy ->
        new_policies = Map.delete(state.policies, policy_id)
        new_state = %{state | 
          policies: new_policies,
          policy_cache: %{}  # Clear cache after policy deletion
        }
        
        # Log policy deletion
        Logger.info("Policy deleted", policy_id: policy_id)
        
        {:reply, :ok, new_state}
    end
  end
  
  @impl GenServer
  def handle_call({:set_global_settings, settings}, _from, state) do
    validated_settings = validate_global_settings(settings)
    new_state = %{state | 
      global_settings: Map.merge(state.global_settings, validated_settings),
      policy_cache: %{}  # Clear cache after global settings change
    }
    
    # Log global settings change
    Logger.info("Global security settings updated", settings: Map.keys(validated_settings))
    
    {:reply, :ok, new_state}
  end
  
  @impl GenServer
  def handle_call(:get_global_settings, _from, state) do
    {:reply, state.global_settings, state}
  end
  
  @impl GenServer
  def handle_call({:activate_emergency_mode, reason, activated_by}, _from, state) do
    Logger.warning("Emergency security mode activated", reason: reason, by: activated_by)
    
    new_state = %{state | emergency_mode: true, policy_cache: %{}}
    
    # Log emergency mode activation - already logged above with Logger.warning
    
    {:reply, :ok, new_state}
  end
  
  @impl GenServer
  def handle_call({:deactivate_emergency_mode, deactivated_by}, _from, state) do
    Logger.info("Emergency security mode deactivated", by: deactivated_by)
    
    new_state = %{state | emergency_mode: false, policy_cache: %{}}
    
    # Log emergency mode deactivation - already logged above with Logger.info
    
    {:reply, :ok, new_state}
  end
  
  @impl GenServer
  def handle_call(:emergency_mode_active?, _from, state) do
    {:reply, state.emergency_mode, state}
  end
  
  @impl GenServer
  def handle_call({:list_policies, filters}, _from, state) do
    policies = 
      state.policies
      |> Map.values()
      |> apply_filters(filters)
      |> Enum.sort_by(&(&1.priority), :desc)
    
    {:reply, policies, state}
  end
  
  @impl GenServer
  def handle_call({:validate_policy, policy_data}, _from, state) do
    result = validate_policy_data(policy_data)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:get_policy_history, context_id, _opts}, _from, state) do
    # In a full implementation, this would query a persistent audit log
    # For now, return empty list
    {:reply, [], state}
  end
  
  @impl GenServer
  def handle_info(:cleanup_expired_policies, state) do
    now = DateTime.utc_now()
    
    {expired_policies, active_policies} = 
      Enum.split_with(state.policies, fn {_id, policy} ->
        policy.expires_at && DateTime.compare(now, policy.expires_at) == :gt
      end)
    
    if length(expired_policies) > 0 do
      Logger.info("Cleaning up #{length(expired_policies)} expired policies")
      
      Enum.each(expired_policies, fn {policy_id, policy} ->
        # Use the actual AuditLogger method for policy violations
        AuditLogger.log_policy_violation("system", policy_id, "expiration", "Policy expired", :medium)
      end)
    end
    
    new_state = %{state | 
      policies: Map.new(active_policies),
      policy_cache: %{}  # Clear cache after cleanup
    }
    
    {:noreply, new_state}
  end
  
  ## Private Functions
  
  defp default_global_settings do
    %{
      default_server_trust: :untrusted,
      require_confirmation_threshold: :medium,
      auto_block_high_risk: true,
      session_trust_timeout: 3600,
      max_concurrent_executions: 10,
      enable_anomaly_detection: true,
      emergency_lockdown_timeout: 300,
      policy_evaluation_cache_ttl: 60
    }
  end
  
  defp load_configuration_policies(state) do
    # Load policies from application configuration
    config_policies = Application.get_env(:the_maestro, :mcp_security_policies, %{})
    
    policies_with_metadata = 
      Enum.map(config_policies, fn {policy_id, policy_data} ->
        policy = Map.merge(policy_data, %{
          id: to_string(policy_id),
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          created_by: "configuration"
        })
        {to_string(policy_id), policy}
      end)
      |> Map.new()
    
    %{state | policies: Map.merge(state.policies, policies_with_metadata)}
  end
  
  defp evaluate_effective_policy(context, state) do
    applicable_policies = find_applicable_policies(context, state)
    
    # Start with global settings as base
    base_policy = state.global_settings
    
    # Apply emergency mode restrictions if active
    base_policy = if state.emergency_mode do
      apply_emergency_restrictions(base_policy)
    else
      base_policy
    end
    
    # Merge policies in precedence order
    applicable_policies
    |> Enum.sort_by(&policy_priority/1, :desc)
    |> Enum.reduce(base_policy, &merge_policy_settings/2)
    |> add_context_metadata(context)
  end
  
  defp find_applicable_policies(context, state) do
    now = DateTime.utc_now()
    
    state.policies
    |> Map.values()
    |> Enum.filter(fn policy ->
      policy_active?(policy, now) and policy_matches_context?(policy, context)
    end)
  end
  
  defp policy_active?(policy, now) do
    policy.status == :active and
    (is_nil(policy.expires_at) or DateTime.compare(now, policy.expires_at) == :lt)
  end
  
  defp policy_matches_context?(policy, context) do
    conditions = policy.conditions || %{}
    
    Enum.all?(conditions, fn {condition_type, condition_value} ->
      case condition_type do
        :user_id -> Map.get(context, :user_id) == condition_value
        :server_id -> Map.get(context, :server_id) == condition_value  
        :tool_name -> Map.get(context, :tool_name) == condition_value
        :time_range -> time_in_range?(DateTime.utc_now(), condition_value)
        :user_roles -> user_has_role?(context, condition_value)
        _ -> true  # Unknown conditions are ignored
      end
    end)
  end
  
  defp time_in_range?(current_time, time_range) do
    # Simple time range check - could be enhanced for complex schedules
    case time_range do
      %{start_hour: start_h, end_hour: end_h} ->
        current_hour = current_time.hour
        current_hour >= start_h and current_hour <= end_h
      _ -> true
    end
  end
  
  defp user_has_role?(context, required_roles) when is_list(required_roles) do
    user_roles = Map.get(context, :user_roles, [])
    Enum.any?(required_roles, &(&1 in user_roles))
  end
  defp user_has_role?(context, required_role) do
    user_has_role?(context, [required_role])
  end
  
  defp policy_priority(policy) do
    base_priority = case policy.level do
      :emergency -> 1000
      :user -> 800
      :tool -> 600  
      :server -> 400
      :time_based -> 200
      :global -> 100
      _ -> 50
    end
    
    base_priority + Map.get(policy, :priority, 0)
  end
  
  defp merge_policy_settings(policy, base_settings) do
    policy_settings = policy.settings || %{}
    deep_merge(base_settings, policy_settings)
  end
  
  defp deep_merge(base, override) do
    Map.merge(base, override, fn
      _key, base_val, override_val when is_map(base_val) and is_map(override_val) ->
        deep_merge(base_val, override_val)
      _key, _base_val, override_val ->
        override_val
    end)
  end
  
  defp apply_emergency_restrictions(base_policy) do
    Map.merge(base_policy, %{
      default_server_trust: :untrusted,
      require_confirmation_threshold: :low,
      auto_block_high_risk: true,
      max_concurrent_executions: 3,
      emergency_mode: true,
      confirmation_required_for_all: true
    })
  end
  
  defp add_context_metadata(policy, context) do
    Map.merge(policy, %{
      evaluation_timestamp: DateTime.utc_now(),
      context_id: generate_cache_key(context),
      evaluated_for: %{
        user_id: Map.get(context, :user_id),
        server_id: Map.get(context, :server_id),
        tool_name: Map.get(context, :tool_name)
      }
    })
  end
  
  defp generate_cache_key(context) do
    context_string = 
      [:user_id, :server_id, :tool_name, :session_id]
      |> Enum.map(&Map.get(context, &1, ""))
      |> Enum.join("|")
    
    :crypto.hash(:md5, context_string) |> Base.encode16(case: :lower)
  end
  
  defp apply_filters(policies, filters) do
    Enum.reduce(filters, policies, fn {filter_type, filter_value}, acc ->
      Enum.filter(acc, fn policy ->
        case filter_type do
          :level -> policy.level == filter_value
          :status -> policy.status == filter_value  
          :created_by -> policy.created_by == filter_value
          :name_contains -> String.contains?(String.downcase(policy.name), String.downcase(filter_value))
          _ -> true
        end
      end)
    end)
  end
  
  defp validate_policy_data(policy_data) do
    errors = []
    
    errors = validate_required_fields(policy_data, errors)
    errors = validate_policy_level(policy_data, errors)
    errors = validate_policy_settings(policy_data, errors)
    errors = validate_policy_conditions(policy_data, errors)
    
    case errors do
      [] -> 
        {:ok, normalize_policy_data(policy_data)}
      errors -> 
        {:error, errors}
    end
  end
  
  defp validate_required_fields(policy_data, errors) do
    required_fields = [:name, :level, :settings]
    
    Enum.reduce(required_fields, errors, fn field, acc ->
      if Map.has_key?(policy_data, field) do
        acc
      else
        ["Missing required field: #{field}" | acc]
      end
    end)
  end
  
  defp validate_policy_level(policy_data, errors) do
    level = Map.get(policy_data, :level)
    valid_levels = [:emergency, :user, :tool, :server, :time_based, :global]
    
    if level in valid_levels do
      errors
    else
      ["Invalid policy level: #{level}. Must be one of: #{inspect(valid_levels)}" | errors]
    end
  end
  
  defp validate_policy_settings(policy_data, errors) do
    settings = Map.get(policy_data, :settings, %{})
    
    if is_map(settings) do
      errors
    else
      ["Policy settings must be a map" | errors]
    end
  end
  
  defp validate_policy_conditions(policy_data, errors) do
    conditions = Map.get(policy_data, :conditions, %{})
    
    if is_map(conditions) do
      errors
    else
      ["Policy conditions must be a map" | errors] 
    end
  end
  
  defp normalize_policy_data(policy_data) do
    now = DateTime.utc_now()
    
    Map.merge(%{
      description: "",
      status: :active,
      conditions: %{},
      created_by: "system",
      created_at: now,
      updated_at: now,
      expires_at: nil,
      priority: 0
    }, policy_data)
  end
  
  defp validate_global_settings(settings) do
    # Validate and normalize global settings
    valid_settings = [
      :default_server_trust,
      :require_confirmation_threshold,
      :auto_block_high_risk,
      :session_trust_timeout,
      :max_concurrent_executions,
      :enable_anomaly_detection,
      :emergency_lockdown_timeout,
      :policy_evaluation_cache_ttl
    ]
    
    settings
    |> Enum.filter(fn {key, _value} -> key in valid_settings end)
    |> Map.new()
  end
end