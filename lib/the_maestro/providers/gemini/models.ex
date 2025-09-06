# credo:disable-for-this-file
defmodule TheMaestro.Providers.Gemini.Models do
  @moduledoc """
  Gemini models provider implementation (initial) using Req.
  """
  @behaviour TheMaestro.Providers.Behaviours.Models
  require Logger
  alias TheMaestro.Models.Model
  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Types

  @impl true
  @spec list_models(Types.session_id()) :: {:ok, [Model.t()]} | {:error, term()}
  def list_models(session_name) when is_binary(session_name) do
    if Mix.env() == :test and System.get_env("RUN_REAL_API_TEST") != "1" do
      {:error, :not_implemented}
    else
      case detect_auth(session_name) do
        {:ok, :oauth} ->
          {:ok, [%Model{id: "gemini-2.5-pro", name: "gemini-2.5-pro", capabilities: []}]}

        {:ok, :api_key} ->
          with {:ok, req} <-
                 ReqClientFactory.create_client(:gemini, :api_key, session: session_name),
               {:ok, %Req.Response{status: 200, body: body}} <-
                 Req.request(req, method: :get, url: "/v1beta/models") do
            decoded = if is_binary(body), do: Jason.decode!(body), else: body
            items = Map.get(decoded, "models", [])

            models =
              Enum.map(items, fn %{"name" => id} -> %Model{id: id, name: id, capabilities: []} end)

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

        {:error, :not_found} ->
          {:error, :session_not_found}
      end
    end
  end

  @impl true
  @spec get_model_info(Types.session_id(), String.t()) :: {:ok, Model.t()} | {:error, term()}
  def get_model_info(session_name, model_id)
      when is_binary(session_name) and is_binary(model_id) do
    if Mix.env() == :test and System.get_env("RUN_REAL_API_TEST") != "1" do
      {:error, :not_implemented}
    else
      with {:ok, auth} <- detect_auth(session_name),
           {:ok, req} <- ReqClientFactory.create_client(:gemini, auth, session: session_name),
           {:ok, %Req.Response{status: 200, body: body}} <-
             Req.request(req, method: :get, url: "/v1beta/" <> model_id) do
        decoded = if is_binary(body), do: Jason.decode!(body), else: body
        id = Map.get(decoded, "name", model_id)
        {:ok, %Model{id: id, name: id, capabilities: []}}
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
      is_map(SavedAuthentication.get_by_provider_and_name(:gemini, :oauth, session_name)) ->
        {:ok, :oauth}

      is_map(SavedAuthentication.get_by_provider_and_name(:gemini, :api_key, session_name)) ->
        {:ok, :api_key}

      true ->
        {:error, :not_found}
    end
  end
end
