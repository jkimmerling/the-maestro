defmodule TheMaestroWeb.Api.PromptsController do
  use TheMaestroWeb, :controller
  alias TheMaestro.SuppliedContext

  def library(conn, params) do
    include_shared = truthy?(Map.get(params, "include_shared", "true"))
    only_defaults = truthy?(Map.get(params, "only_defaults", "false"))
    group_by_family = truthy?(Map.get(params, "group_by_family", "false"))

    providers = [:openai, :anthropic, :gemini]

    by_provider =
      Enum.reduce(providers, %{}, fn provider, acc ->
        list =
          SuppliedContext.list_system_prompts(provider,
            include_shared: include_shared,
            only_defaults: only_defaults,
            group_by_family: group_by_family
          )

        Map.put(acc, Atom.to_string(provider), Enum.map(list, &prompt_to_map/1))
      end)

    json(conn, %{library: by_provider})
  end

  defp prompt_to_map(prompt) do
    %{
      id: prompt.id,
      provider: Atom.to_string(prompt.provider || :shared),
      name: prompt.name,
      version: prompt.version,
      immutable: !!prompt.immutable,
      is_default: !!prompt.is_default,
      labels: prompt.labels || %{},
      metadata: prompt.metadata || %{}
    }
  end

  defp truthy?(val) do
    case val do
      true -> true
      "true" -> true
      "1" -> true
      1 -> true
      _ -> false
    end
  end
end
