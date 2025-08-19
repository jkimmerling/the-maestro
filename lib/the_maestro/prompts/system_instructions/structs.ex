defmodule TheMaestro.Prompts.SystemInstructions.AssemblyContext do
  @moduledoc """
  Context structure for instruction assembly process.
  """
  
  defstruct [
    :base_instructions,
    :available_tools,
    :mcp_servers,
    :environment,
    :task_context,
    :provider_info,
    :security_context,
    assembled_instructions: "",
    validation_errors: []
  ]

  @type t :: %__MODULE__{
    base_instructions: String.t() | nil,
    available_tools: list(),
    mcp_servers: list(),
    environment: map() | nil,
    task_context: TaskContext.t() | nil,
    provider_info: map() | nil,
    security_context: map() | nil,
    assembled_instructions: String.t(),
    validation_errors: list()
  }
end

defmodule TheMaestro.Prompts.SystemInstructions.TaskContext do
  @moduledoc """
  Context information about the current task being performed.
  """
  
  defstruct [
    :primary_task_type,
    :complexity_level,
    :required_capabilities,
    :time_sensitivity,
    :risk_level,
    :collaboration_mode
  ]

  @type t :: %__MODULE__{
    primary_task_type: atom(),
    complexity_level: :low | :moderate | :high,
    required_capabilities: list(atom()),
    time_sensitivity: :urgent | :normal | :flexible,
    risk_level: :low | :medium | :high | :critical,
    collaboration_mode: :autonomous | :collaborative | :guided
  }
end