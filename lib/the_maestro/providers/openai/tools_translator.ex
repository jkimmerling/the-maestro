defmodule TheMaestro.Providers.OpenAI.ToolsTranslator do
  @moduledoc """
  Translate registry tool declarations into OpenAI Responses API `tools` entries.

  Input is a list of maps returned by `TheMaestro.Tools.Registry.list_tools/1`, each with:
  - name: string
  - description: string
  - parameters: JSON-Schema map (object)

  Output matches OpenAI Responses tools format:
    [%{"type" => "function", "function" => %{"name" => name, "description" => desc, "parameters" => schema}}]
  """

  @spec declare_tools([map()]) :: [map()]
  def declare_tools(tools) when is_list(tools) do
    Enum.map(tools, &to_openai_tool/1)
  end

  defp to_openai_tool(%{name: name, description: desc, parameters: schema}) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => desc,
        "parameters" => schema
      }
    }
  end

  defp to_openai_tool(%{"name" => name, "description" => desc, "parameters" => schema}) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => desc,
        "parameters" => schema
      }
    }
  end
end
