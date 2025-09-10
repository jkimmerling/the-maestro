defmodule TheMaestro.Providers.Http.TestCaptureAdapter do
  @moduledoc false

  @type request_opts :: keyword()

  @spec stream_request(Req.Request.t(), request_opts) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_request(req, opts \\ []) do
    headers = Enum.into(req.headers, %{})
    payload = opts[:json] || opts[:body]
    url = opts[:url]
    method = opts[:method] || :get

    send(
      self(),
      {:captured_request, %{method: method, url: url, headers: headers, body: payload}}
    )

    {:ok, []}
  end
end
