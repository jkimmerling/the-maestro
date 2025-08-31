defmodule TheMaestro.Providers.Http.ReqConfig do
  @moduledoc """
  Centralized configuration helpers for Req-based HTTP clients.

  Provides base options shared by all provider clients. Provider-specific
  factories should merge these options and then add their own pool, base_url
  and headers.
  """

  @typedoc "Base options for Req requests"
  @type base_options :: keyword()

  @doc """
  Returns the base Req options used across provider clients.

  These can be extended per-provider with pool/base_url/headers and fine-tuned
  per call.
  """
  @spec base_options() :: base_options()
  def base_options do
    [
      # Conservative, explicit retry defaults; providers may override
      retry: [max_retries: 2, backoff_factor: 2.0],
      # Reasonable default timeouts; can be overridden per request
      receive_timeout: 60_000
    ]
  end

  @doc """
  Merges the provided options on top of the base options.
  Later values win on key conflicts.
  """
  @spec merge_with_base(keyword()) :: keyword()
  def merge_with_base(opts) when is_list(opts) do
    Keyword.merge(base_options(), opts, fn _k, _v1, v2 -> v2 end)
  end
end
