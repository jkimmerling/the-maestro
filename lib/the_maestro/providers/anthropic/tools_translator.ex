defmodule TheMaestro.Providers.Anthropic.ToolsTranslator do
  @moduledoc """
  Translate registry tools to Anthropic Messages `tools: [%{name, input_schema}]`,
  and tool results to user `tool_result` content blocks.
  See docs/tool-specs/anthropic_tool_specs.md.
  """
  @doc "Return Anthropic `tools` from registry tools."
  @spec declare_tools([map()]) :: [map()]
  def declare_tools(tools) when is_list(tools) do
    Enum.map(tools, fn t ->
      %{
        name: t.name || t[:name],
        description: t.description || t[:description],
        input_schema: t.parameters || t[:parameters]
      }
    end)
  end
  @doc "Return a user message with `tool_result` content for a tool result."
  @spec tool_result(map()) :: map()
  def tool_result(%{call_id: id, text: text}) do
    %{
      "role" => "user",
      "content" => [
        %{"type" => "tool_result", "tool_use_id" => id, "content" => text}
      ]
    }
  end
end
