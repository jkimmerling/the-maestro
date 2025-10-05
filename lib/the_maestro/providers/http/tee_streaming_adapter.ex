defmodule TheMaestro.Providers.Http.TeeStreamingAdapter do
  @moduledoc "Thin tee around StreamingAdapter that logs full JSON payloads (including input items) for debugging."

  alias TheMaestro.Providers.Http.StreamingAdapter, as: Real

  @spec stream_request(Req.Request.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_request(req, opts) do
    payload = Keyword.get(opts, :json)
    tag = Keyword.get(opts, :tag, :tee)

    if is_map(payload) do
      io = [
        "\n=== TEE(",
        to_string(tag),
        ") OpenAI request payload ===\n",
        Jason.encode_to_iodata!(payload),
        "\n=== END TEE ===\n"
      ]

      IO.binwrite(:stdio, IO.iodata_to_binary(io))
    end

    Real.stream_request(req, opts)
  end
end
