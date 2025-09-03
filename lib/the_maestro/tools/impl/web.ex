defmodule TheMaestro.Tools.Impl.Web do
  @moduledoc """
  Minimal web fetch tool using Req. Intended for summarization upstream.
  """

  @spec fetch_urls(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def fetch_urls(prompt, _opts) when is_binary(prompt) do
    urls = extract_urls(prompt)

    texts =
      urls
      |> Enum.map(&fetch_one/1)
      |> Enum.map(fn
        {:ok, {url, body}} -> "# #{url}\n\n" <> body
        {:error, {url, _}} -> "# #{url}\n\n[error fetching]"
      end)

    {:ok, Enum.join(texts, "\n\n")}
  end

  defp fetch_one(url) do
    req = Req.new()

    case Req.get(req, url: url) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        text = if is_binary(body), do: body, else: Jason.encode!(body)
        {:ok, {url, String.slice(text, 0, 50_000)}}

      other ->
        {:error, {url, other}}
    end
  end

  defp extract_urls(prompt) do
    Regex.scan(~r/https?:\/\/[\w\-\.\/?#%&=]+/i, prompt)
    |> Enum.map(&List.first/1)
    |> Enum.uniq()
  end
end
