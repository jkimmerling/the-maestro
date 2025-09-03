defmodule TheMaestro.Providers.OpenAI.ToolsTranslator do
  @moduledoc """
  Translate registry tools to OpenAI Responses `tools[]` (function tools),
  and tool results to `function_call_output` items.
  See docs/tool-specs/codex_tool_specs-codex.md.
  """
  @doc "Return Responses API `tools[]` entries from registry tools."
  @spec declare_tools([map()]) :: [map()]
  def declare_tools(tools) when is_list(tools) do
    Enum.map(tools, fn t ->
      %{
        "type" => "function",
        "function" => %{
          "name" => t.name || t[:name],
          "description" => t.description || t[:description],
          "parameters" => t.parameters || t[:parameters]
        }
      }
    end)
  end
  @doc "Return an input[] `function_call_output` item for the tool result."
  @spec function_call_output(map()) :: map()
  def function_call_output(%{name: name, call_id: id, text: text}) do
    %{"type" => "function_call_output", "call_id" => id, "name" => name, "output" => text}
  end
end
