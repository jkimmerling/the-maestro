defmodule TheMaestro.Providers.Gemini.ToolsTranslator do
  @moduledoc """
  Translate provider-agnostic tool registry into Gemini functionDeclarations,
  and translate tool results into `functionResponse` parts for continuation.

  This is a compilable stub; shapes must follow docs/tool-specs/gemini_tool_specs-codex.md.
  """
  @doc "Return Gemini `functionDeclarations` from registry tools."
  @spec declare_tools([map()]) :: [map()]
  def declare_tools(tools) when is_list(tools) do
    Enum.map(tools, fn t ->
      %{
        name: t.name || t[:name],
        description: t.description || t[:description],
        parameters: t.parameters || t[:parameters]
      }
    end)
  end
  @doc "Return a Gemini `functionResponse` user part for a given tool result."
  @spec function_response(map()) :: map()
  def function_response(%{name: name, call_id: id, text: text}) do
    %{
      "role" => "user",
      "parts" => [
        %{"functionResponse" => %{"name" => name, "id" => id, "response" => %{"output" => text}}}
      ]
    }
  end
end
