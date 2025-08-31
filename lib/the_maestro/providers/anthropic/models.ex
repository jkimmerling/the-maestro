defmodule TheMaestro.Providers.Anthropic.Models do
  @moduledoc """
  Anthropic models provider stub for Story 0.2/0.4.
  """
  @behaviour TheMaestro.Providers.Behaviours.Models
  require Logger
  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Types

  @impl true
  @spec list_models(Types.session_id()) :: {:ok, [Types.model()]} | {:error, term()}
  def list_models(session_name) when is_binary(session_name) do
    if Mix.env() == :test and System.get_env("RUN_REAL_API_TEST") != "1" do
      {:error, :not_implemented}
    else
      with {:ok, auth} <- detect_auth(session_name),
           {:ok, req} <- ReqClientFactory.create_client(:anthropic, auth, session: session_name),
           {:ok, %Req.Response{status: 200, body: body}} <-
             Req.request(req, method: :get, url: "/v1/models") do
        decoded = if is_binary(body), do: Jason.decode!(body), else: body
        # Accept either {"models": [...] } or {"data": [...]}
        items = Map.get(decoded, "models", Map.get(decoded, "data", []))
        models = Enum.map(items, fn %{"id" => id} -> %{id: id, name: id, capabilities: []} end)
        {:ok, models}
      else
        {:ok, %Req.Response{status: status, body: body}} ->
          {:error,
           {:http_error, status, if(is_binary(body), do: body, else: Jason.encode!(body))}}

        {:error, :not_found} ->
          {:error, :session_not_found}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  @spec get_model_info(Types.session_id(), String.t()) :: {:ok, Types.model()} | {:error, term()}
  def get_model_info(session_name, model_id)
      when is_binary(session_name) and is_binary(model_id) do
    if Mix.env() == :test and System.get_env("RUN_REAL_API_TEST") != "1" do
      {:error, :not_implemented}
    else
      with {:ok, auth} <- detect_auth(session_name),
           {:ok, req} <- ReqClientFactory.create_client(:anthropic, auth, session: session_name),
           {:ok, %Req.Response{status: 200, body: body}} <-
             Req.request(req, method: :get, url: "/v1/models/" <> model_id) do
        decoded = if is_binary(body), do: Jason.decode!(body), else: body

        model = %{
          id: Map.get(decoded, "id", model_id),
          name: Map.get(decoded, "id", model_id),
          capabilities: []
        }

        {:ok, model}
      else
        {:ok, %Req.Response{status: status, body: body}} ->
          {:error,
           {:http_error, status, if(is_binary(body), do: body, else: Jason.encode!(body))}}

        {:error, :not_found} ->
          {:error, :session_not_found}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp detect_auth(session_name) do
    cond do
      is_map(SavedAuthentication.get_by_provider_and_name(:anthropic, :oauth, session_name)) ->
        {:ok, :oauth}

      is_map(SavedAuthentication.get_by_provider_and_name(:anthropic, :api_key, session_name)) ->
        {:ok, :api_key}

      true ->
        {:error, :not_found}
    end
  end
end
