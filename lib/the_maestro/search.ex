defmodule TheMaestro.Search do
  @moduledoc "Search aggregator selecting backends by agent.tools order."
  alias TheMaestro.Search.Backends.{DuckDuckGo, Tavily}

  @default_order [:tavily, :duckduckgo]

  @spec search(map(), String.t(), keyword()) :: {:ok, %{summary: String.t(), sources: [map()]}} | {:error, term()}
  def search(agent, query, opts \\ []) do
    order = backend_order(agent)
    do_search(order, query, opts)
  end

  defp do_search([], _q, _opts), do: {:error, :no_backend_available}
  defp do_search([:tavily | rest], q, opts) do
    if Tavily.available?() do
      case Tavily.search(q, opts) do
        {:ok, _} = ok -> ok
        {:error, _} -> do_search(rest, q, opts)
      end
    else
      do_search(rest, q, opts)
    end
  end

  defp do_search([:duckduckgo | rest], q, opts) do
    case DuckDuckGo.search(q, opts) do
      {:ok, _} = ok -> ok
      {:error, _} -> do_search(rest, q, opts)
    end
  end

  defp do_search([_other | rest], q, opts), do: do_search(rest, q, opts)

  defp backend_order(agent) do
    tools = Map.get(agent, :tools) || Map.get(agent, "tools") || %{}
    order =
      tools
      |> Map.get("search_backends", @default_order)
      |> normalize_order()

    if order == [], do: @default_order, else: order
  end

  defp normalize_order(list) when is_list(list) do
    Enum.map(list, fn
      "tavily" -> :tavily
      "duckduckgo" -> :duckduckgo
      a when is_atom(a) -> a
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  defp normalize_order(_), do: @default_order
end
