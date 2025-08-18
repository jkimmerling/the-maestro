defmodule TheMaestro.MCP.Security.AuditLogger do
  @moduledoc """
  Security audit logging system for MCP operations.

  Provides comprehensive logging of security-related events for compliance,
  monitoring, and forensic analysis. Events are structured for machine
  processing and include sufficient context for investigation.

  ## Event Types

  - `:tool_execution` - Tool execution attempts and results
  - `:trust_granted` - Trust level changes and grants
  - `:trust_revoked` - Trust revocations and restrictions
  - `:access_denied` - Blocked or denied operations
  - `:confirmation_requested` - User confirmation requests
  - `:confirmation_response` - User confirmation responses
  - `:policy_violation` - Security policy violations
  - `:anomaly_detected` - Suspicious activity detection

  ## Log Destinations

  - Standard Logger (for development)
  - Structured JSON logs (for production)
  - External SIEM systems (future)
  - Database storage (for compliance)
  """

  require Logger

  defmodule SecurityEvent do
    @moduledoc """
    Security event structure for audit logging.
    """
    @type event_type ::
            :tool_execution
            | :trust_granted
            | :trust_revoked
            | :access_denied
            | :confirmation_requested
            | :confirmation_response
            | :policy_violation
            | :anomaly_detected

    @type risk_level :: :low | :medium | :high | :critical
    @type decision :: :allowed | :denied | :user_confirmed | :blocked

    @type t :: %__MODULE__{
            event_type: event_type(),
            user_id: String.t(),
            session_id: String.t() | nil,
            tool_name: String.t() | nil,
            server_id: String.t() | nil,
            parameters: map() | nil,
            risk_level: risk_level() | nil,
            decision: decision() | nil,
            reason: String.t() | nil,
            metadata: map(),
            timestamp: DateTime.t(),
            ip_address: String.t() | nil,
            user_agent: String.t() | nil
          }

    defstruct [
      :event_type,
      :user_id,
      :session_id,
      :tool_name,
      :server_id,
      :parameters,
      :risk_level,
      :decision,
      :reason,
      :timestamp,
      :ip_address,
      :user_agent,
      metadata: %{}
    ]
  end

  @doc """
  Logs a security event.

  ## Parameters

  - `event` - SecurityEvent struct with event details
  - `options` - Logging options

  ## Options

  - `:async` - Log asynchronously (default: true)
  - `:destinations` - List of log destinations (default: [:logger])
  - `:format` - Log format (:structured, :text) (default: :structured)
  """
  @spec log_event(SecurityEvent.t(), keyword()) :: :ok
  def log_event(%SecurityEvent{} = event, options \\ []) do
    async = Keyword.get(options, :async, true)
    destinations = Keyword.get(options, :destinations, [:logger])
    format = Keyword.get(options, :format, :structured)

    if async do
      Task.start(fn -> write_to_destinations(event, destinations, format) end)
    else
      write_to_destinations(event, destinations, format)
    end

    :ok
  end

  @doc """
  Logs a tool execution event.
  """
  @spec log_tool_execution(
          String.t(),
          String.t(),
          String.t(),
          map(),
          atom(),
          atom(),
          String.t() | nil,
          map()
        ) :: :ok
  def log_tool_execution(
        user_id,
        tool_name,
        server_id,
        parameters,
        risk_level,
        decision,
        reason \\ nil,
        metadata \\ %{}
      ) do
    event = %SecurityEvent{
      event_type: :tool_execution,
      user_id: user_id,
      tool_name: tool_name,
      server_id: server_id,
      parameters: sanitize_parameters_for_log(parameters),
      risk_level: risk_level,
      decision: decision,
      reason: reason,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    log_event(event)
  end

  @doc """
  Logs a trust change event.
  """
  @spec log_trust_change(atom(), String.t(), String.t(), String.t() | nil, String.t(), map()) ::
          :ok
  def log_trust_change(
        event_type,
        user_id,
        server_id,
        tool_name \\ nil,
        granted_by,
        metadata \\ %{}
      ) do
    event = %SecurityEvent{
      event_type: event_type,
      user_id: user_id,
      server_id: server_id,
      tool_name: tool_name,
      metadata: Map.put(metadata, :granted_by, granted_by),
      timestamp: DateTime.utc_now()
    }

    log_event(event)
  end

  @doc """
  Logs an access denied event.
  """
  @spec log_access_denied(String.t(), String.t(), String.t(), String.t(), atom(), map()) :: :ok
  def log_access_denied(
        user_id,
        tool_name,
        server_id,
        reason,
        risk_level \\ :medium,
        metadata \\ %{}
      ) do
    event = %SecurityEvent{
      event_type: :access_denied,
      user_id: user_id,
      tool_name: tool_name,
      server_id: server_id,
      risk_level: risk_level,
      decision: :denied,
      reason: reason,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    log_event(event)
  end

  @doc """
  Logs a user confirmation request.
  """
  @spec log_confirmation_request(String.t(), String.t(), String.t(), map(), atom(), map()) :: :ok
  def log_confirmation_request(
        user_id,
        tool_name,
        server_id,
        parameters,
        risk_level,
        metadata \\ %{}
      ) do
    event = %SecurityEvent{
      event_type: :confirmation_requested,
      user_id: user_id,
      tool_name: tool_name,
      server_id: server_id,
      parameters: sanitize_parameters_for_log(parameters),
      risk_level: risk_level,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    log_event(event)
  end

  @doc """
  Logs a user confirmation response.
  """
  @spec log_confirmation_response(String.t(), String.t(), String.t(), atom(), atom(), map()) ::
          :ok
  def log_confirmation_response(user_id, tool_name, server_id, choice, decision, metadata \\ %{}) do
    event = %SecurityEvent{
      event_type: :confirmation_response,
      user_id: user_id,
      tool_name: tool_name,
      server_id: server_id,
      decision: decision,
      metadata: Map.put(metadata, :user_choice, choice),
      timestamp: DateTime.utc_now()
    }

    log_event(event)
  end

  @doc """
  Logs a policy violation event.
  """
  @spec log_policy_violation(String.t(), String.t(), String.t(), String.t(), atom(), map()) :: :ok
  def log_policy_violation(
        user_id,
        policy_name,
        violation_type,
        description,
        risk_level \\ :high,
        metadata \\ %{}
      ) do
    event = %SecurityEvent{
      event_type: :policy_violation,
      user_id: user_id,
      reason: description,
      risk_level: risk_level,
      metadata:
        Map.merge(metadata, %{
          policy_name: policy_name,
          violation_type: violation_type
        }),
      timestamp: DateTime.utc_now()
    }

    log_event(event)
  end

  @doc """
  Logs an anomaly detection event.
  """
  @spec log_anomaly_detected(String.t(), String.t(), String.t(), atom(), map()) :: :ok
  def log_anomaly_detected(
        user_id,
        anomaly_type,
        description,
        risk_level \\ :medium,
        metadata \\ %{}
      ) do
    event = %SecurityEvent{
      event_type: :anomaly_detected,
      user_id: user_id,
      reason: description,
      risk_level: risk_level,
      metadata: Map.put(metadata, :anomaly_type, anomaly_type),
      timestamp: DateTime.utc_now()
    }

    log_event(event)
  end

  @doc """
  Queries audit logs for analysis and reporting.

  Note: In this basic implementation, this just returns a placeholder.
  A full implementation would query from persistent storage.
  """
  @spec query_events(keyword()) :: [SecurityEvent.t()]
  def query_events(filters \\ []) do
    Logger.info("Audit log query requested", filters: filters)
    # TODO: Implement actual log querying from persistent storage
    []
  end

  ## Private Functions

  defp write_to_destinations(event, destinations, format) do
    for destination <- destinations do
      write_to_destination(event, destination, format)
    end
  end

  defp write_to_destination(event, :logger, format) do
    case format do
      :structured ->
        log_structured_event(event)

      :text ->
        log_text_event(event)
    end
  end

  defp write_to_destination(event, :json_file, _format) do
    # TODO: Implement JSON file logging
    Logger.debug("Would write to JSON file", event: event)
  end

  defp write_to_destination(event, :database, _format) do
    # TODO: Implement database logging
    Logger.debug("Would write to database", event: event)
  end

  defp log_structured_event(event) do
    log_level = determine_log_level(event.risk_level, event.event_type)

    Logger.log(log_level, "Security Event",
      event_type: event.event_type,
      user_id: event.user_id,
      session_id: event.session_id,
      tool_name: event.tool_name,
      server_id: event.server_id,
      risk_level: event.risk_level,
      decision: event.decision,
      reason: event.reason,
      timestamp: event.timestamp,
      metadata: event.metadata
    )
  end

  defp log_text_event(event) do
    log_level = determine_log_level(event.risk_level, event.event_type)

    message = format_text_message(event)
    Logger.log(log_level, message)
  end

  defp determine_log_level(:critical, _), do: :error
  defp determine_log_level(:high, _), do: :warning
  defp determine_log_level(_, :access_denied), do: :warning
  defp determine_log_level(_, :policy_violation), do: :warning
  defp determine_log_level(_, _), do: :info

  defp format_text_message(event) do
    base = "Security Event [#{event.event_type}] User: #{event.user_id}"

    parts = [base]

    parts =
      if event.tool_name do
        ["Tool: #{event.tool_name}" | parts]
      else
        parts
      end

    parts =
      if event.server_id do
        ["Server: #{event.server_id}" | parts]
      else
        parts
      end

    parts =
      if event.risk_level do
        ["Risk: #{event.risk_level}" | parts]
      else
        parts
      end

    parts =
      if event.decision do
        ["Decision: #{event.decision}" | parts]
      else
        parts
      end

    parts =
      if event.reason do
        ["Reason: #{event.reason}" | parts]
      else
        parts
      end

    Enum.reverse(parts) |> Enum.join(" | ")
  end

  defp sanitize_parameters_for_log(parameters) when is_map(parameters) do
    # Remove or mask sensitive parameter values for logging
    parameters
    |> Enum.map(fn {key, value} -> {key, sanitize_parameter_value(key, value)} end)
    |> Enum.into(%{})
  end

  defp sanitize_parameters_for_log(parameters), do: parameters

  defp sanitize_parameter_value(key, value) when is_binary(key) and is_binary(value) do
    key_lower = String.downcase(key)

    cond do
      # Mask sensitive parameter types
      String.contains?(key_lower, "password") -> "[MASKED]"
      String.contains?(key_lower, "secret") -> "[MASKED]"
      String.contains?(key_lower, "token") -> "[MASKED]"
      String.contains?(key_lower, "key") -> "[MASKED]"
      String.contains?(key_lower, "auth") -> "[MASKED]"
      # Truncate very long values
      String.length(value) > 200 -> String.slice(value, 0, 200) <> "...[TRUNCATED]"
      true -> value
    end
  end

  defp sanitize_parameter_value(_key, value), do: value
end
