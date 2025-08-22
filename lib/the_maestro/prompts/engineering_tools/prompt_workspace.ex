defmodule TheMaestro.Prompts.EngineeringTools.PromptWorkspace do
  @moduledoc """
  Represents a prompt engineering workspace with project context, templates, and tools.
  """

  defstruct [
    :workspace_id,
    :user_id,
    :project_name,
    :domain,
    :tech_stack,
    :created_at,
    :last_accessed,
    :domain_templates,
    :tech_stack_tools,
    :data_processing_tools,
    :preferences,
    :team_context,
    :collaboration_config,
    :integration_config,
    :current_projects,
    :recent_templates,
    :project_type
  ]

  @type t :: %__MODULE__{
          workspace_id: String.t(),
          user_id: String.t(),
          project_name: String.t(),
          domain: atom(),
          tech_stack: list(String.t()),
          created_at: DateTime.t(),
          last_accessed: DateTime.t(),
          domain_templates: map() | list(String.t()),
          tech_stack_tools: map(),
          data_processing_tools: map(),
          preferences: map(),
          team_context: map() | nil,
          collaboration_config: map() | nil,
          integration_config: map() | nil,
          current_projects: list(map()) | nil,
          recent_templates: list(String.t()) | nil,
          project_type: atom() | nil
        }
end