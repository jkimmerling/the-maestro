defmodule TheMaestro.Prompts.EngineeringTools.ToolPalette do
  @moduledoc """
  Represents a collection of available engineering tools organized by category.
  """

  defstruct [
    :available_tools,
    :automation_level,
    :ui_complexity,
    :help_level,
    :skill_level_filter,
    :recommended_tools,
    :recently_used
  ]

  @type t :: %__MODULE__{
          available_tools: map(),
          automation_level: atom(),
          ui_complexity: atom(),
          help_level: atom(),
          skill_level_filter: atom() | nil,
          recommended_tools: list(map()) | nil,
          recently_used: list(map()) | nil
        }
end
