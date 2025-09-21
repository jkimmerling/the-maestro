defmodule TheMaestro.Tools.WebFetch do
  @moduledoc """
  Fetch a URL and return text content for analysis. Uses Req.
  """

  alias TheMaestro.Tools.ExecOutput

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, _opts \\ []) when is_map(args) do
    url = Map.get(args, "url") || Map.get(args, :url)

    if is_binary(url) and String.starts_with?(url, "http") do
      started = System.monotonic_time(:millisecond)

      try do
        resp =
          Req.get!(
            url: url,
            headers: [{"user-agent", "TheMaestro/1.0 tool-runtime"}],
            receive_timeout: 15_000
          )

        body = to_string(resp.body || "")
        duration = (System.monotonic_time(:millisecond) - started) / 1000
        out = "#{resp.status}\n\n" <> String.slice(body, 0, 60_000)
        {:ok, ExecOutput.format(out, 0, duration)}
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:error, "invalid url"}
    end
  end

  def run(_, _), do: {:error, "invalid arguments"}
end
