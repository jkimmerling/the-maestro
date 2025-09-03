defmodule TheMaestro.Providers.Gemini.ToolsTranslator do
  @moduledoc """
  Translate registry tools into Gemini function_declarations.
  """

  @spec declare_tools([map()]) :: [map()]
  def declare_tools(tools) when is_list(tools) do
    %{"function_declarations" => Enum.map(tools, &to_function_decl/1)}
    |> List.wrap()
  end

  defp to_function_decl(%{name: name, description: desc, parameters: schema}) do
    %{"name" => name, "description" => desc, "parameters" => schema}
  end

  defp to_function_decl(%{"name" => name, "description" => desc, "parameters" => schema}) do
    %{"name" => name, "description" => desc, "parameters" => schema}
  end
end
