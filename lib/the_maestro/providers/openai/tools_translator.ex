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

  @spec declare_tools_enterprise([map()]) :: [map()]
  def declare_tools_enterprise(tools) when is_list(tools) do
    Enum.map(tools, &to_openai_enterprise_tool/1)
  end

  @spec declare_tools_chatgpt([map()]) :: [map()]
  def declare_tools_chatgpt(tools) when is_list(tools) do
    Enum.map(tools, &to_openai_chatgpt_tool/1)
  end

  defp to_openai_enterprise_tool(%{name: name, description: desc, parameters: schema}) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => desc,
        "parameters" => schema
      }
    }
  end

  defp to_openai_enterprise_tool(%{"name" => name, "description" => desc, "parameters" => schema}) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => desc,
        "parameters" => schema
      }
    }
  end

  # ChatGPT Personal (codex/responses) has historically required top-level name/parameters
  # and, in some variants, a function wrapper/type. Provide both for compatibility.
  defp to_openai_chatgpt_tool(%{name: name, description: desc, parameters: schema}) do
    %{
      "type" => "function",
      "name" => name,
      "description" => desc,
      "parameters" => schema,
      "function" => %{"name" => name, "description" => desc, "parameters" => schema}
    }
  end

  defp to_openai_chatgpt_tool(%{"name" => name, "description" => desc, "parameters" => schema}) do
    %{
      "type" => "function",
      "name" => name,
      "description" => desc,
      "parameters" => schema,
      "function" => %{"name" => name, "description" => desc, "parameters" => schema}
    }
  end
end
