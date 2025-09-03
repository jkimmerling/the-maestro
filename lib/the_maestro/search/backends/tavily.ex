defmodule TheMaestro.Search.Backends.Tavily do
  @moduledoc "Tavily search backend (https://tavily.com)."

  @endpoint "https://api.tavily.com/search"

  @spec available?() :: boolean()
  def available? do
    System.get_env("TAVILY_API_KEY") not in [nil, ""]
  end

  @type result :: %{summary: String.t(), sources: [map()]}

  @spec search(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def search(query, opts \\ []) when is_binary(query) do
    api_key = System.fetch_env("TAVILY_API_KEY")
    case api_key do
      :error -> {:error, :missing_api_key}
      {:ok, key} -> do_search(query, key, opts)
    end
  end

  defp do_search(query, key, opts) do
    req = Req.new(base_url: @endpoint, headers: [{"content-type", "application/json"}])

    body = %{
      "api_key" => key,
      "query" => query,
      "search_depth" => "basic",
      "max_results" => Keyword.get(opts, :max_results, 5)
    }

    case Req.post(req, json: body) do
      {:ok, %Req.Response{status: 200, body: %{"results" => results, "answer" => answer}}} ->
        sources =
          results
          |> Enum.map(fn r -> %{title: r["title"], url: r["url"], snippet: r["content"]} end)

        {:ok, %{summary: to_string(answer || ""), sources: sources}}

      {:ok, %Req.Response{status: s, body: b}} ->
        {:error, {:http_error, s, b}}

      {:error, e} -> {:error, e}
    end
  end
end
