defmodule TheMaestro.Providers.Anthropic.ToolsTranslator do
  @moduledoc """
  Translate registry tools into Anthropic Messages API tool declarations.

  Anthropic expects tools as a list of maps with name, description, and input_schema.
  """

  @spec declare_tools([map()]) :: [map()]
  def declare_tools(tools) when is_list(tools) do
    Enum.map(tools, &to_anthropic_tool/1)
  end

  defp to_anthropic_tool(%{name: name, description: desc, parameters: schema}) do
    %{
      "type" => "tool",
      "name" => name,
      "description" => desc,
      "input_schema" => schema
    }
  end

  defp to_anthropic_tool(%{"name" => name, "description" => desc, "parameters" => schema}) do
    %{
      "type" => "tool",
      "name" => name,
      "description" => desc,
      "input_schema" => schema
    }
  end
end
