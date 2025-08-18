defmodule TheMaestro.MCP.Security.ConfirmationEngine do
  @moduledoc """
  Confirmation flow engine for MCP tool execution security.

  Orchestrates the complete security confirmation flow including:
  - Risk assessment
  - Trust evaluation
  - User confirmation dialog presentation
  - Decision processing and persistence
  - Security event logging

  ## Confirmation Flow

  1. **Risk Assessment**: Analyze tool and parameters for security risks
  2. **Trust Evaluation**: Check server and tool trust levels
  3. **Decision Logic**: Determine if confirmation is required
  4. **User Interaction**: Present confirmation dialog if needed
  5. **Decision Processing**: Handle user choice and update trust
  6. **Event Logging**: Log security events for audit trail

  ## User Choices

  - `:execute_once` - Allow this execution only
  - `:always_allow_tool` - Add tool to whitelist
  - `:always_trust_server` - Trust entire server
  - `:block_tool` - Add tool to blacklist
  - `:cancel` - Abort execution
  """

  require Logger

  alias TheMaestro.MCP.Security.{
    RiskAssessor,
    RiskAssessment,
    TrustManager
  }

  @type confirmation_choice ::
          :execute_once | :always_allow_tool | :always_trust_server | :block_tool | :cancel
  @type confirmation_context :: %{
          user_id: String.t(),
          session_id: String.t(),
          interface: :web | :tui | :headless
        }

  defmodule ConfirmationRequest do
    @moduledoc """
    Confirmation request data structure.
    """
    @type t :: %__MODULE__{
            tool: map(),
            parameters: map(),
            context: map(),
            risk_assessment: RiskAssessment.t(),
            requires_confirmation: boolean(),
            reason: String.t()
          }

    defstruct [
      :tool,
      :parameters,
      :context,
      :risk_assessment,
      :requires_confirmation,
      :reason
    ]
  end

  defmodule ConfirmationResult do
    @moduledoc """
    Result of confirmation flow processing.
    """
    alias TheMaestro.MCP.Security.ConfirmationEngine

    @type t :: %__MODULE__{
            decision: :allow | :deny,
            choice: ConfirmationEngine.confirmation_choice() | nil,
            trust_updated: boolean(),
            audit_logged: boolean(),
            message: String.t()
          }

    defstruct [
      :decision,
      :choice,
      :message,
      trust_updated: false,
      audit_logged: false
    ]
  end

  @doc """
  Evaluates if tool execution requires confirmation.

  Performs risk assessment and trust evaluation to determine if user
  confirmation is needed before allowing tool execution.

  ## Parameters

  - `tool` - Tool information map
  - `parameters` - Tool parameters
  - `context` - Security context

  ## Returns

  `ConfirmationRequest.t()` with assessment results
  """
  @spec evaluate_confirmation_requirement(map(), map(), map()) :: ConfirmationRequest.t()
  def evaluate_confirmation_requirement(tool, parameters, context) do
    # Perform risk assessment
    risk_assessment = RiskAssessor.assess_risk(tool, parameters)

    # Check trust manager
    trust_manager_pid = get_trust_manager_pid()

    requires_trust_confirmation =
      GenServer.call(
        trust_manager_pid,
        {:requires_confirmation, tool, parameters, context}
      )

    # Determine overall confirmation requirement
    requires_confirmation =
      determine_confirmation_requirement(
        risk_assessment,
        requires_trust_confirmation,
        context
      )

    reason = build_confirmation_reason(risk_assessment, requires_trust_confirmation)

    %ConfirmationRequest{
      tool: tool,
      parameters: parameters,
      context: context,
      risk_assessment: risk_assessment,
      requires_confirmation: requires_confirmation,
      reason: reason
    }
  end

  @doc """
  Processes user confirmation choice and updates trust accordingly.

  ## Parameters

  - `request` - Confirmation request from evaluation
  - `choice` - User's choice
  - `context` - Confirmation context

  ## Returns

  `ConfirmationResult.t()` with processing results
  """
  @spec process_confirmation_choice(
          ConfirmationRequest.t(),
          confirmation_choice(),
          confirmation_context()
        ) :: ConfirmationResult.t()
  def process_confirmation_choice(request, choice, context) do
    Logger.info("Processing confirmation choice",
      choice: choice,
      tool: request.tool.name || "unknown",
      server_id: request.tool.server_id || "unknown",
      user_id: context.user_id
    )

    result =
      case choice do
        :execute_once ->
          %ConfirmationResult{
            decision: :allow,
            choice: choice,
            message: "Execution allowed for this instance only"
          }

        :always_allow_tool ->
          update_tool_trust(request, :whitelist, context)

          %ConfirmationResult{
            decision: :allow,
            choice: choice,
            trust_updated: true,
            message: "Tool added to whitelist and execution allowed"
          }

        :always_trust_server ->
          update_server_trust(request, :trusted, context)

          %ConfirmationResult{
            decision: :allow,
            choice: choice,
            trust_updated: true,
            message: "Server trusted and execution allowed"
          }

        :block_tool ->
          update_tool_trust(request, :blacklist, context)

          %ConfirmationResult{
            decision: :deny,
            choice: choice,
            trust_updated: true,
            message: "Tool blocked and added to blacklist"
          }

        :cancel ->
          %ConfirmationResult{
            decision: :deny,
            choice: choice,
            message: "Execution cancelled by user"
          }
      end

    # Log security event
    log_security_event(request, result, context)

    %{result | audit_logged: true}
  end

  @doc """
  Handles automatic security decisions for headless/batch operations.

  Uses policy settings to make security decisions without user interaction.
  """
  @spec handle_headless_security(ConfirmationRequest.t(), map()) :: ConfirmationResult.t()
  def handle_headless_security(request, policy_settings \\ %{}) do
    auto_block_high_risk = Map.get(policy_settings, :auto_block_high_risk, true)

    result =
      cond do
        # Auto-block critical risk operations
        request.risk_assessment.risk_level == :critical ->
          %ConfirmationResult{
            decision: :deny,
            message: "Critical risk operation blocked by security policy"
          }

        # Auto-block high risk if policy enabled
        request.risk_assessment.risk_level == :high and auto_block_high_risk ->
          %ConfirmationResult{
            decision: :deny,
            message: "High risk operation blocked by security policy"
          }

        # Allow low/medium risk operations
        true ->
          %ConfirmationResult{
            decision: :allow,
            message: "Operation allowed by security policy"
          }
      end

    # Log the automatic decision
    context = %{
      user_id: "system",
      session_id: "headless",
      interface: :headless
    }

    log_security_event(request, result, context)

    %{result | audit_logged: true}
  end

  ## Private Functions

  defp get_trust_manager_pid do
    # In production, this would get the trust manager from supervision tree
    # For now, we'll handle the case where it doesn't exist
    case Process.whereis(TrustManager) do
      nil ->
        # Start a temporary trust manager if needed
        {:ok, pid} = TrustManager.start_link([])
        pid

      pid ->
        pid
    end
  end

  defp determine_confirmation_requirement(risk_assessment, requires_trust_confirmation, _context) do
    # Confirmation is required if either risk or trust evaluation says so
    RiskAssessment.requires_confirmation?(risk_assessment) or requires_trust_confirmation
  end

  defp build_confirmation_reason(risk_assessment, requires_trust_confirmation) do
    reasons = []

    reasons =
      if RiskAssessment.requires_confirmation?(risk_assessment) do
        ["Risk level: #{risk_assessment.risk_level}" | reasons]
      else
        reasons
      end

    reasons =
      if requires_trust_confirmation do
        ["Trust verification required" | reasons]
      else
        reasons
      end

    case reasons do
      [] -> "No confirmation required"
      reasons -> Enum.join(reasons, ", ")
    end
  end

  defp update_tool_trust(request, action, context) do
    trust_manager_pid = get_trust_manager_pid()
    server_id = request.tool.server_id || request.tool[:server_id]
    tool_name = request.tool.name || request.tool[:name]
    user_id = context.user_id

    case action do
      :whitelist ->
        GenServer.call(trust_manager_pid, {:whitelist_tool, server_id, tool_name, user_id})

      :blacklist ->
        GenServer.call(trust_manager_pid, {:blacklist_tool, server_id, tool_name, user_id})
    end
  end

  defp update_server_trust(request, trust_level, context) do
    trust_manager_pid = get_trust_manager_pid()
    server_id = request.tool.server_id || request.tool[:server_id]
    user_id = context.user_id

    GenServer.call(trust_manager_pid, {:grant_server_trust, server_id, trust_level, user_id})
  end

  defp log_security_event(request, result, context) do
    # For now, just log to Logger
    # In full implementation, would use AuditLogger module
    Logger.info("Security decision made",
      tool: request.tool.name || "unknown",
      server_id: request.tool.server_id || "unknown",
      decision: result.decision,
      choice: result.choice,
      risk_level: request.risk_assessment.risk_level,
      user_id: context.user_id,
      session_id: context.session_id,
      interface: context.interface
    )
  end
end
