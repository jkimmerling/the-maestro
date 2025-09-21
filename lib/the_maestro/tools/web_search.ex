defmodule TheMaestro.Tools.WebSearch do
  @moduledoc """
  Web search tool with configurable backend. Default: Tavily.
  """

  alias TheMaestro.Tools.ExecOutput

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, _opts \\ []) do
    backend = Application.get_env(:the_maestro, :web_search_backend, :tavily)

    case backend do
      :tavily -> run_tavily(args)
      other -> {:error, "unsupported web_search backend: #{inspect(other)}"}
    end
  end

  defp run_tavily(args) do
    api_key =
      Application.get_env(:the_maestro, :tavily_api_key) ||
        System.get_env("TAVILY_API_KEY")

    q = Map.get(args, "query") || Map.get(args, :query)
    depth = Map.get(args, "search_depth") || "basic"
    allowed = Map.get(args, "allowed_domains") || Map.get(args, :allowed_domains) || []
    blocked = Map.get(args, "blocked_domains") || Map.get(args, :blocked_domains) || []

    cond do
      is_nil(api_key) or api_key == "" ->
        {:error, "tavily api key missing"}

      !is_binary(q) or String.trim(q) == "" ->
        {:error, "missing query"}

      true ->
        started = System.monotonic_time(:millisecond)
        url = "https://api.tavily.com/search"
        payload =
          %{
            api_key: api_key,
            query: q,
            search_depth: depth
          }
          |> maybe_put(:include_domains, sanitize_domains(allowed))
          |> maybe_put(:exclude_domains, sanitize_domains(blocked))

        try do
          resp = Req.post!(url: url, json: payload, receive_timeout: 20_000)
          duration = (System.monotonic_time(:millisecond) - started) / 1000
          out = Jason.encode!(resp.body)
          {:ok, ExecOutput.format(out, 0, duration)}
        rescue
          e -> {:error, Exception.message(e)}
        end
    end
  end

  defp sanitize_domains(list) when is_list(list) do
    Enum.flat_map(list, fn
      s when is_binary(s) ->
        trimmed = String.trim(s)
        if trimmed == "" do
          []
        else
          [trimmed]
        end
      _ -> []
    end)
  end

  defp sanitize_domains(_), do: []

  defp maybe_put(map, _k, []), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end
