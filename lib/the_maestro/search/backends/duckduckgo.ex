defmodule TheMaestro.Search.Backends.DuckDuckGo do
  @moduledoc "DuckDuckGo HTML scraping fallback (lightweight, no external deps)."

  @endpoint "https://html.duckduckgo.com/html/"

  @spec available?() :: boolean()
  def available?, do: true

  @type result :: %{summary: String.t(), sources: [map()]}

  @spec search(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def search(query, opts \\ []) do
    req =
      Req.new(
        url: @endpoint,
        headers: [{"user-agent", "TheMaestro/1.0 (DuckDuckGo Fallback)"}],
        params: [q: query]
      )

    case Req.get(req) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, %{summary: summarize(body, opts), sources: extract_sources(body)}}

      {:ok, %Req.Response{status: s, body: b}} ->
        {:error, {:http_error, s, b}}

      {:error, e} -> {:error, e}
    end
  end

  defp extract_sources(html) when is_binary(html) do
    # Very light extraction: anchor tags in results container
    # This is intentionally simple to avoid dependencies.
    Regex.scan(~r/<a[^>]+class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)<\/a>/i, html)
    |> Enum.map(fn [_, url, title_html] ->
      title = title_html |> strip_tags() |> String.trim()
      %{title: title, url: url}
    end)
    |> Enum.take(5)
  end

  defp strip_tags(s), do: Regex.replace(~r/<[^>]*>/, s, "")

  defp summarize(_body, _opts), do: ""
end
