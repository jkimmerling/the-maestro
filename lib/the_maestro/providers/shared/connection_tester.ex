defmodule TheMaestro.Providers.Shared.ConnectionTester do
  @moduledoc """
  Shared connection testing logic for providers.

  CRITICAL: Only extracts response handling - endpoints remain 100% provider-specific.
  Each provider still uses its own endpoint, this only standardizes the response processing.
  """

  @doc """
  Test connection using provider-specific endpoint.

  This extracts the common pattern of:
  1. Make GET request to provider-specific endpoint
  2. Check for 200 status
  3. Format error responses consistently

  The endpoint parameter MUST be provider-specific and unchanged.
  """
  @spec test_connection(Req.Request.t(), String.t()) :: :ok | {:error, term()}
  def test_connection(%Req.Request{} = req, endpoint) when is_binary(endpoint) do
    case Req.request(req, method: :get, url: endpoint) do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, format_body(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper to format response bodies consistently
  defp format_body(body) when is_binary(body), do: body
  defp format_body(body), do: Jason.encode!(body)
end
