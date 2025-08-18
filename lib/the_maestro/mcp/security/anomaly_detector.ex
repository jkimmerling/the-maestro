defmodule TheMaestro.MCP.Security.AnomalyDetector do
  @moduledoc """
  Suspicious activity detection system for MCP tool execution security.

  Provides real-time anomaly detection for:
  - Unusual tool usage patterns
  - Multiple failed confirmations
  - Suspicious parameter patterns  
  - Resource usage anomalies
  - Time-based access patterns
  - Behavioral deviation detection

  ## Detection Strategies

  - **Statistical Analysis**: Baseline behavior modeling with deviation thresholds
  - **Pattern Recognition**: Known attack patterns and suspicious sequences
  - **Frequency Analysis**: Rate limiting and burst detection
  - **Contextual Analysis**: Context-aware anomaly scoring
  - **Machine Learning**: Adaptive learning from historical data

  ## Anomaly Types

  - **Usage Patterns**: Unusual tool combinations or sequences
  - **Access Patterns**: Suspicious file/network access attempts
  - **Temporal Patterns**: Off-hours access, rapid execution bursts
  - **Parameter Patterns**: Injection attempts, traversal patterns
  - **Resource Patterns**: Excessive resource consumption
  - **Behavioral Patterns**: User behavior deviation from baseline
  """

  use GenServer
  require Logger

  alias TheMaestro.MCP.Security.AuditLogger

  @type anomaly_type ::
          :usage_pattern
          | :access_pattern
          | :temporal_pattern
          | :parameter_pattern
          | :resource_pattern
          | :behavioral_pattern
  @type severity_level :: :low | :medium | :high | :critical
  @type anomaly_status :: :detected | :investigating | :confirmed | :false_positive | :resolved

  @type anomaly :: %{
          id: String.t(),
          type: anomaly_type(),
          severity: severity_level(),
          status: anomaly_status(),
          description: String.t(),
          evidence: map(),
          context: map(),
          score: float(),
          detected_at: DateTime.t(),
          updated_at: DateTime.t(),
          user_id: String.t() | nil,
          server_id: String.t() | nil,
          tool_name: String.t() | nil
        }

  defmodule DetectorState do
    @moduledoc false
    alias TheMaestro.MCP.Security.AnomalyDetector

    @type t :: %__MODULE__{
            baselines: %{String.t() => map()},
            active_anomalies: %{String.t() => map()},
            recent_events: [map()],
            detection_patterns: [map()],
            thresholds: map(),
            stats: map(),
            last_baseline_update: DateTime.t()
          }

    defstruct baselines: %{},
              active_anomalies: %{},
              recent_events: [],
              detection_patterns: [],
              thresholds: %{},
              stats: %{},
              last_baseline_update: nil
  end

  ## Public API

  @doc """
  Starts the anomaly detector GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a security event for anomaly analysis.
  """
  @spec record_event(map()) :: :ok
  def record_event(event) do
    GenServer.cast(__MODULE__, {:record_event, event})
  end

  @doc """
  Analyzes current context for anomalies.
  """
  @spec analyze_context(map()) :: {:ok, [anomaly()]} | {:error, String.t()}
  def analyze_context(context) do
    GenServer.call(__MODULE__, {:analyze_context, context})
  end

  @doc """
  Gets active anomalies with optional filtering.
  """
  @spec get_active_anomalies(keyword()) :: [anomaly()]
  def get_active_anomalies(filters \\ []) do
    GenServer.call(__MODULE__, {:get_active_anomalies, filters})
  end

  @doc """
  Updates anomaly status (for investigation workflow).
  """
  @spec update_anomaly_status(String.t(), anomaly_status(), String.t()) ::
          :ok | {:error, String.t()}
  def update_anomaly_status(anomaly_id, new_status, updated_by) do
    GenServer.call(__MODULE__, {:update_anomaly_status, anomaly_id, new_status, updated_by})
  end

  @doc """
  Gets user behavior baseline.
  """
  @spec get_user_baseline(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_user_baseline(user_id) do
    GenServer.call(__MODULE__, {:get_user_baseline, user_id})
  end

  @doc """
  Configures detection thresholds.
  """
  @spec configure_thresholds(map()) :: :ok
  def configure_thresholds(thresholds) do
    GenServer.call(__MODULE__, {:configure_thresholds, thresholds})
  end

  @doc """
  Gets detection statistics.
  """
  @spec get_statistics() :: map()
  def get_statistics() do
    GenServer.call(__MODULE__, :get_statistics)
  end

  ## GenServer Implementation

  @impl GenServer
  def init(opts) do
    Logger.info("Starting MCP Security Anomaly Detector")

    thresholds = Keyword.get(opts, :thresholds, default_thresholds())
    patterns = Keyword.get(opts, :detection_patterns, default_detection_patterns())

    state = %DetectorState{
      thresholds: thresholds,
      detection_patterns: patterns,
      stats: %{
        events_processed: 0,
        anomalies_detected: 0,
        false_positives: 0,
        confirmed_threats: 0
      }
    }

    # Schedule periodic baseline updates
    # 5 minutes
    :timer.send_interval(300_000, self(), :update_baselines)

    # Schedule anomaly cleanup
    # 1 hour
    :timer.send_interval(3600_000, self(), :cleanup_resolved_anomalies)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:record_event, event}, state) do
    new_state =
      state
      |> add_event_to_history(event)
      |> update_statistics(:event_recorded)
      |> detect_anomalies_from_event(event)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call({:analyze_context, context}, _from, state) do
    try do
      anomalies = analyze_context_for_anomalies(context, state)
      {:reply, {:ok, anomalies}, state}
    catch
      error ->
        Logger.error("Context analysis failed", error: error, context: context)
        {:reply, {:error, "Analysis failed: #{inspect(error)}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_active_anomalies, filters}, _from, state) do
    active_anomalies =
      state.active_anomalies
      |> Map.values()
      |> apply_anomaly_filters(filters)
      |> Enum.sort_by(& &1.detected_at, {:desc, DateTime})

    {:reply, active_anomalies, state}
  end

  @impl GenServer
  def handle_call({:update_anomaly_status, anomaly_id, new_status, updated_by}, _from, state) do
    case Map.get(state.active_anomalies, anomaly_id) do
      nil ->
        {:reply, {:error, "Anomaly not found"}, state}

      anomaly ->
        updated_anomaly = %{anomaly | status: new_status, updated_at: DateTime.utc_now()}

        new_active_anomalies = Map.put(state.active_anomalies, anomaly_id, updated_anomaly)
        new_state = %{state | active_anomalies: new_active_anomalies}

        # Log status change
        Logger.info("Anomaly status updated",
          anomaly_id: anomaly_id,
          old_status: anomaly.status,
          new_status: new_status
        )

        # Update statistics
        new_state = update_anomaly_statistics(new_state, new_status)

        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call({:get_user_baseline, user_id}, _from, state) do
    case Map.get(state.baselines, user_id) do
      nil -> {:reply, {:error, "No baseline found for user"}, state}
      baseline -> {:reply, {:ok, baseline}, state}
    end
  end

  @impl GenServer
  def handle_call({:configure_thresholds, thresholds}, _from, state) do
    validated_thresholds = validate_thresholds(thresholds)
    new_state = %{state | thresholds: Map.merge(state.thresholds, validated_thresholds)}

    Logger.info("Updated anomaly detection thresholds", thresholds: validated_thresholds)

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_statistics, _from, state) do
    stats =
      Map.merge(state.stats, %{
        active_anomalies: map_size(state.active_anomalies),
        baselines_tracked: map_size(state.baselines),
        recent_events: length(state.recent_events)
      })

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_info(:update_baselines, state) do
    Logger.debug("Updating user behavior baselines")
    new_state = update_user_baselines(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:cleanup_resolved_anomalies, state) do
    Logger.debug("Cleaning up resolved anomalies")
    new_state = cleanup_old_anomalies(state)
    {:noreply, new_state}
  end

  ## Private Functions

  defp default_thresholds do
    %{
      # Usage pattern thresholds
      max_tools_per_minute: 20,
      max_failed_confirmations_per_hour: 5,
      unusual_tool_combination_threshold: 0.8,

      # Access pattern thresholds
      max_file_access_per_minute: 50,
      max_network_requests_per_minute: 30,
      suspicious_path_score_threshold: 0.7,

      # Temporal pattern thresholds
      off_hours_score_threshold: 0.6,
      burst_activity_threshold: 5.0,
      session_length_anomaly_threshold: 2.0,

      # Parameter pattern thresholds
      injection_pattern_threshold: 0.8,
      traversal_pattern_threshold: 0.9,

      # Resource pattern thresholds
      cpu_usage_anomaly_threshold: 2.5,
      memory_usage_anomaly_threshold: 2.0,
      execution_time_anomaly_threshold: 3.0,

      # Behavioral pattern thresholds
      user_behavior_deviation_threshold: 2.0,
      new_tool_usage_threshold: 0.7
    }
  end

  defp default_detection_patterns do
    [
      # Known attack patterns
      %{
        name: "directory_traversal",
        type: :parameter_pattern,
        patterns: ["../", "..\\", "%2e%2e%2f", "%2e%2e%5c", "....//"],
        severity: :high
      },
      %{
        name: "command_injection",
        type: :parameter_pattern,
        patterns: ["; ", "| ", "& ", "$(", "`", "&&", "||"],
        severity: :critical
      },
      %{
        name: "sql_injection",
        type: :parameter_pattern,
        patterns: ["' or ", "\" or ", "union select", "drop table", "'; drop"],
        severity: :high
      },
      %{
        name: "script_injection",
        type: :parameter_pattern,
        patterns: ["<script", "javascript:", "vbscript:", "onload=", "onerror="],
        severity: :medium
      },

      # Behavioral patterns
      %{
        name: "rapid_tool_switching",
        type: :usage_pattern,
        description: "Rapid switching between many different tools",
        threshold: 10,
        severity: :medium
      },
      %{
        name: "privilege_escalation_attempt",
        type: :usage_pattern,
        patterns: ["sudo", "su", "chmod 777", "chown root", "passwd"],
        severity: :critical
      },

      # Access patterns
      %{
        name: "sensitive_file_access",
        type: :access_pattern,
        patterns: ["/etc/passwd", "/etc/shadow", "id_rsa", "private.key", ".env"],
        severity: :high
      }
    ]
  end

  defp add_event_to_history(state, event) do
    # Keep last 1000 events for analysis
    recent_events = [event | state.recent_events] |> Enum.take(1000)
    %{state | recent_events: recent_events}
  end

  defp detect_anomalies_from_event(state, event) do
    detected_anomalies = []

    # Run all detection algorithms
    detected_anomalies = detected_anomalies ++ detect_usage_pattern_anomalies(event, state)
    detected_anomalies = detected_anomalies ++ detect_parameter_pattern_anomalies(event, state)
    detected_anomalies = detected_anomalies ++ detect_temporal_pattern_anomalies(event, state)
    detected_anomalies = detected_anomalies ++ detect_access_pattern_anomalies(event, state)
    detected_anomalies = detected_anomalies ++ detect_resource_pattern_anomalies(event, state)
    detected_anomalies = detected_anomalies ++ detect_behavioral_pattern_anomalies(event, state)

    # Add new anomalies to active list
    Enum.reduce(detected_anomalies, state, &add_anomaly_to_active/2)
  end

  defp detect_usage_pattern_anomalies(event, state) do
    anomalies = []
    user_id = Map.get(event, :user_id)

    # Check for rapid tool usage
    if user_id do
      # last minute
      recent_user_events = get_recent_user_events(state, user_id, 60)

      tool_count =
        recent_user_events |> Enum.map(&Map.get(&1, :tool_name)) |> Enum.uniq() |> length()

      anomalies =
        if tool_count > state.thresholds.max_tools_per_minute do
          [
            create_anomaly(
              :usage_pattern,
              :medium,
              "Excessive tool usage rate",
              %{
                tool_count: tool_count,
                threshold: state.thresholds.max_tools_per_minute,
                user_id: user_id
              },
              event
            )
            | anomalies
          ]
        else
          anomalies
        end
    end

    # Check for unusual tool combinations
    anomalies = anomalies ++ detect_unusual_tool_combinations(event, state)

    anomalies
  end

  defp detect_parameter_pattern_anomalies(event, state) do
    parameters = Map.get(event, :parameters, %{})

    state.detection_patterns
    |> Enum.filter(&(&1.type == :parameter_pattern))
    |> Enum.flat_map(fn pattern ->
      matches = find_pattern_matches(parameters, pattern.patterns)

      if length(matches) > 0 do
        [
          create_anomaly(
            :parameter_pattern,
            pattern.severity,
            "Suspicious parameter pattern: #{pattern.name}",
            %{
              pattern_name: pattern.name,
              matches: matches,
              parameters: sanitize_parameters_for_logging(parameters)
            },
            event
          )
        ]
      else
        []
      end
    end)
  end

  defp detect_temporal_pattern_anomalies(event, state) do
    anomalies = []
    timestamp = Map.get(event, :timestamp, DateTime.utc_now())
    user_id = Map.get(event, :user_id)

    # Off-hours access detection
    if is_off_hours?(timestamp) and user_id do
      baseline = Map.get(state.baselines, user_id, %{})
      normal_hours_activity = Map.get(baseline, :normal_hours_activity, 0.5)

      if normal_hours_activity > state.thresholds.off_hours_score_threshold do
        anomalies = [
          create_anomaly(
            :temporal_pattern,
            :medium,
            "Off-hours access by typically daytime user",
            %{
              timestamp: timestamp,
              normal_hours_activity: normal_hours_activity,
              user_id: user_id
            },
            event
          )
          | anomalies
        ]
      end
    end

    # Burst activity detection
    if user_id do
      # last 5 minutes
      recent_events = get_recent_user_events(state, user_id, 300)
      # events per minute
      event_rate = length(recent_events) / 5.0

      baseline_rate = get_user_baseline_rate(state, user_id)

      if event_rate > baseline_rate * state.thresholds.burst_activity_threshold do
        anomalies = [
          create_anomaly(
            :temporal_pattern,
            :high,
            "Burst activity detected",
            %{
              current_rate: event_rate,
              baseline_rate: baseline_rate,
              threshold_multiplier: state.thresholds.burst_activity_threshold,
              user_id: user_id
            },
            event
          )
          | anomalies
        ]
      end
    end

    anomalies
  end

  defp detect_access_pattern_anomalies(event, state) do
    anomalies = []

    # Sensitive file access detection
    file_path = get_in(event, [:parameters, :path]) || get_in(event, [:parameters, "path"])

    if file_path do
      sensitive_patterns = get_sensitive_file_patterns(state)
      matches = find_pattern_matches(%{path: file_path}, sensitive_patterns)

      if length(matches) > 0 do
        anomalies = [
          create_anomaly(
            :access_pattern,
            :high,
            "Sensitive file access attempt",
            %{
              file_path: file_path,
              matches: matches
            },
            event
          )
          | anomalies
        ]
      end
    end

    # Network access pattern analysis
    url = get_in(event, [:parameters, :url]) || get_in(event, [:parameters, "url"])

    if url do
      anomalies = anomalies ++ analyze_network_access_patterns(url, event, state)
    end

    anomalies
  end

  defp detect_resource_pattern_anomalies(event, state) do
    resource_usage = Map.get(event, :resource_usage, %{})
    anomalies = []
    user_id = Map.get(event, :user_id)

    if user_id != nil and map_size(resource_usage) > 0 do
      baseline = Map.get(state.baselines, user_id, %{})

      # CPU usage anomaly
      cpu_usage = Map.get(resource_usage, :cpu_percent, 0)
      baseline_cpu = Map.get(baseline, :avg_cpu_usage, 20)

      if cpu_usage > baseline_cpu * state.thresholds.cpu_usage_anomaly_threshold do
        anomalies = [
          create_anomaly(
            :resource_pattern,
            :medium,
            "Excessive CPU usage",
            %{
              current_cpu: cpu_usage,
              baseline_cpu: baseline_cpu,
              user_id: user_id
            },
            event
          )
          | anomalies
        ]
      end

      # Memory usage anomaly  
      memory_usage = Map.get(resource_usage, :memory_mb, 0)
      baseline_memory = Map.get(baseline, :avg_memory_usage, 100)

      if memory_usage > baseline_memory * state.thresholds.memory_usage_anomaly_threshold do
        anomalies = [
          create_anomaly(
            :resource_pattern,
            :medium,
            "Excessive memory usage",
            %{
              current_memory: memory_usage,
              baseline_memory: baseline_memory,
              user_id: user_id
            },
            event
          )
          | anomalies
        ]
      end
    end

    anomalies
  end

  defp detect_behavioral_pattern_anomalies(event, state) do
    anomalies = []
    user_id = Map.get(event, :user_id)
    tool_name = Map.get(event, :tool_name)

    if user_id and tool_name do
      baseline = Map.get(state.baselines, user_id, %{})
      user_tools = Map.get(baseline, :common_tools, [])

      # New tool usage detection
      if tool_name not in user_tools do
        tool_novelty_score = calculate_tool_novelty_score(tool_name, user_tools)

        if tool_novelty_score > state.thresholds.new_tool_usage_threshold do
          anomalies = [
            create_anomaly(
              :behavioral_pattern,
              :low,
              "New tool usage",
              %{
                tool_name: tool_name,
                novelty_score: tool_novelty_score,
                user_id: user_id
              },
              event
            )
            | anomalies
          ]
        end
      end

      # Behavioral deviation analysis
      deviation_score = calculate_behavioral_deviation(event, baseline)

      if deviation_score > state.thresholds.user_behavior_deviation_threshold do
        anomalies = [
          create_anomaly(
            :behavioral_pattern,
            :medium,
            "User behavior deviation",
            %{
              deviation_score: deviation_score,
              user_id: user_id
            },
            event
          )
          | anomalies
        ]
      end
    end

    anomalies
  end

  defp analyze_context_for_anomalies(context, state) do
    # Real-time context analysis
    current_anomalies = []

    # Check for active anomalies related to this context
    user_id = Map.get(context, :user_id)
    server_id = Map.get(context, :server_id)
    tool_name = Map.get(context, :tool_name)

    related_anomalies =
      state.active_anomalies
      |> Map.values()
      |> Enum.filter(fn anomaly ->
        (is_nil(user_id) or anomaly.user_id == user_id) and
          (is_nil(server_id) or anomaly.server_id == server_id) and
          (is_nil(tool_name) or anomaly.tool_name == tool_name)
      end)

    current_anomalies ++ related_anomalies
  end

  ## Helper Functions

  defp create_anomaly(type, severity, description, evidence, context) do
    %{
      id: generate_anomaly_id(),
      type: type,
      severity: severity,
      status: :detected,
      description: description,
      evidence: evidence,
      context: context,
      score: calculate_anomaly_score(type, severity, evidence),
      detected_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      user_id: Map.get(context, :user_id),
      server_id: Map.get(context, :server_id),
      tool_name: Map.get(context, :tool_name)
    }
  end

  defp generate_anomaly_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp calculate_anomaly_score(type, severity, evidence) do
    base_score =
      case severity do
        :low -> 0.3
        :medium -> 0.6
        :high -> 0.8
        :critical -> 1.0
      end

    type_modifier =
      case type do
        :parameter_pattern -> 0.2
        :behavioral_pattern -> 0.1
        :usage_pattern -> 0.15
        :access_pattern -> 0.25
        :temporal_pattern -> 0.1
        :resource_pattern -> 0.05
      end

    evidence_modifier = if map_size(evidence) > 5, do: 0.1, else: 0.0

    min(1.0, base_score + type_modifier + evidence_modifier)
  end

  defp get_recent_user_events(state, user_id, seconds) do
    cutoff = DateTime.add(DateTime.utc_now(), -seconds, :second)

    state.recent_events
    |> Enum.filter(fn event ->
      Map.get(event, :user_id) == user_id and
        DateTime.compare(Map.get(event, :timestamp, DateTime.utc_now()), cutoff) == :gt
    end)
  end

  defp detect_unusual_tool_combinations(event, state) do
    # Simplified tool combination analysis
    # In a full implementation, this would use statistical models
    []
  end

  defp find_pattern_matches(parameters, patterns) do
    parameter_strings =
      parameters
      |> Map.values()
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.downcase/1)

    patterns
    |> Enum.filter(fn pattern ->
      Enum.any?(parameter_strings, &String.contains?(&1, String.downcase(pattern)))
    end)
  end

  defp sanitize_parameters_for_logging(parameters) do
    # Remove potentially sensitive parameter values for logging
    parameters
    |> Enum.map(fn {key, value} ->
      sanitized_value =
        if String.length(to_string(value)) > 100 do
          String.slice(to_string(value), 0, 100) <> "..."
        else
          value
        end

      {key, sanitized_value}
    end)
    |> Map.new()
  end

  defp is_off_hours?(timestamp) do
    hour = timestamp.hour
    # Consider 6 AM to 10 PM as normal hours
    hour < 6 or hour > 22
  end

  defp get_user_baseline_rate(state, user_id) do
    baseline = Map.get(state.baselines, user_id, %{})
    Map.get(baseline, :avg_events_per_minute, 2.0)
  end

  defp get_sensitive_file_patterns(state) do
    state.detection_patterns
    |> Enum.find(&(&1.name == "sensitive_file_access"))
    |> case do
      nil -> []
      pattern -> pattern.patterns
    end
  end

  defp analyze_network_access_patterns(_url, _event, _state) do
    # Placeholder for network access pattern analysis
    []
  end

  defp calculate_tool_novelty_score(_tool_name, _user_tools) do
    # Simplified novelty scoring - could be enhanced with tool similarity analysis
    0.5
  end

  defp calculate_behavioral_deviation(_event, _baseline) do
    # Placeholder for behavioral deviation calculation
    0.3
  end

  defp add_anomaly_to_active(anomaly, state) do
    # Log the detected anomaly using the proper AuditLogger method
    AuditLogger.log_anomaly_detected(
      anomaly.user_id || "unknown",
      to_string(anomaly.type),
      anomaly.description,
      anomaly.severity,
      %{
        anomaly_id: anomaly.id,
        server_id: anomaly.server_id,
        tool_name: anomaly.tool_name
      }
    )

    new_active_anomalies = Map.put(state.active_anomalies, anomaly.id, anomaly)
    new_state = %{state | active_anomalies: new_active_anomalies}

    update_statistics(new_state, :anomaly_detected)
  end

  defp update_statistics(state, event_type) do
    current_stats = state.stats

    new_stats =
      case event_type do
        :event_recorded ->
          Map.update(current_stats, :events_processed, 1, &(&1 + 1))

        :anomaly_detected ->
          Map.update(current_stats, :anomalies_detected, 1, &(&1 + 1))

        _ ->
          current_stats
      end

    %{state | stats: new_stats}
  end

  defp update_anomaly_statistics(state, status) do
    current_stats = state.stats

    new_stats =
      case status do
        :false_positive ->
          Map.update(current_stats, :false_positives, 1, &(&1 + 1))

        :confirmed ->
          Map.update(current_stats, :confirmed_threats, 1, &(&1 + 1))

        _ ->
          current_stats
      end

    %{state | stats: new_stats}
  end

  defp apply_anomaly_filters(anomalies, filters) do
    Enum.reduce(filters, anomalies, fn {filter_type, filter_value}, acc ->
      Enum.filter(acc, fn anomaly ->
        case filter_type do
          :type -> anomaly.type == filter_value
          :severity -> anomaly.severity == filter_value
          :status -> anomaly.status == filter_value
          :user_id -> anomaly.user_id == filter_value
          :server_id -> anomaly.server_id == filter_value
          :tool_name -> anomaly.tool_name == filter_value
          _ -> true
        end
      end)
    end)
  end

  defp update_user_baselines(state) do
    # Update user behavior baselines based on recent activity
    # This is a simplified version - a full implementation would use statistical analysis

    user_events =
      state.recent_events
      |> Enum.group_by(&Map.get(&1, :user_id))
      |> Enum.reject(fn {user_id, _events} -> is_nil(user_id) end)

    new_baselines =
      Enum.reduce(user_events, state.baselines, fn {user_id, events}, baselines ->
        baseline = calculate_user_baseline(events)
        Map.put(baselines, user_id, baseline)
      end)

    %{state | baselines: new_baselines, last_baseline_update: DateTime.utc_now()}
  end

  defp calculate_user_baseline(events) do
    if length(events) == 0 do
      %{}
    else
      %{
        common_tools:
          events |> Enum.map(&Map.get(&1, :tool_name)) |> Enum.frequencies() |> Map.keys(),
        # Assuming events from last hour
        avg_events_per_minute: length(events) / 60.0,
        avg_cpu_usage:
          events
          |> Enum.map(&get_in(&1, [:resource_usage, :cpu_percent]))
          |> Enum.reject(&is_nil/1)
          |> average(),
        avg_memory_usage:
          events
          |> Enum.map(&get_in(&1, [:resource_usage, :memory_mb]))
          |> Enum.reject(&is_nil/1)
          |> average(),
        normal_hours_activity: calculate_normal_hours_ratio(events)
      }
    end
  end

  defp average([]), do: 0
  defp average(list), do: Enum.sum(list) / length(list)

  defp calculate_normal_hours_ratio(events) do
    return_hours_ratio =
      if length(events) == 0 do
        0.5
      else
        normal_hours_count =
          events
          |> Enum.count(fn event ->
            timestamp = Map.get(event, :timestamp, DateTime.utc_now())
            not is_off_hours?(timestamp)
          end)

        normal_hours_count / length(events)
      end

    return_hours_ratio
  end

  defp cleanup_old_anomalies(state) do
    # 7 days ago
    cutoff = DateTime.add(DateTime.utc_now(), -7 * 24 * 60 * 60, :second)

    {old_anomalies, active_anomalies} =
      Enum.split_with(state.active_anomalies, fn {_id, anomaly} ->
        anomaly.status in [:resolved, :false_positive] and
          DateTime.compare(anomaly.updated_at, cutoff) == :lt
      end)

    if length(old_anomalies) > 0 do
      Logger.info("Cleaning up #{length(old_anomalies)} old resolved anomalies")
    end

    %{state | active_anomalies: Map.new(active_anomalies)}
  end

  defp validate_thresholds(thresholds) do
    # Validate threshold values and provide defaults for missing ones
    defaults = default_thresholds()

    thresholds
    |> Enum.filter(fn {key, _value} -> Map.has_key?(defaults, key) end)
    |> Enum.filter(fn {_key, value} -> is_number(value) and value > 0 end)
    |> Map.new()
  end
end
