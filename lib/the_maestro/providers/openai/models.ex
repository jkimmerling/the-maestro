# credo:disable-for-this-file
defmodule TheMaestro.Providers.OpenAI.Models do
  @moduledoc """
  OpenAI models provider stub.

  Uses Req client in Story 0.2; completed in 0.3.
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
        {:ok, :api_key} ->
          with {:ok, req} <-
                 ReqClientFactory.create_client(:openai, :api_key, session: session_name),
               {:ok, %Req.Response{status: 200, body: body}} <-
                 Req.request(req, method: :get, url: "/v1/models") do
            decoded = if is_binary(body), do: Jason.decode!(body), else: body

            models =
              decoded
              |> Map.get("data", [])
              |> Enum.map(fn %{"id" => id} -> %Model{id: id, name: id, capabilities: []} end)

            {:ok, models}
          else
            {:error, :not_found} ->
              {:error, :session_not_found}

            {:ok, %Req.Response{status: status, body: body}} ->
              {:error,
               {:http_error, status, if(is_binary(body), do: body, else: Jason.encode!(body))}}

            {:error, reason} ->
              {:error, reason}
          end

        {:ok, :oauth} ->
          # ChatGPT personal OAuth tokens cannot access /v1/models; use ChatGPT backend defaults.
          # Provide a minimal, sane set compatible with our streaming defaults.
          {:ok,
           [
             %Model{id: "gpt-5", name: "gpt-5", capabilities: []},
             %Model{id: "gpt-4o", name: "gpt-4o", capabilities: []}
           ]}

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
           {:ok, req} <- ReqClientFactory.create_client(:openai, auth, session: session_name),
           {:ok, %Req.Response{status: 200, body: body}} <-
             Req.request(req, method: :get, url: "/v1/models/" <> model_id) do
        decoded = if is_binary(body), do: Jason.decode!(body), else: body

        model = %Model{
          id: Map.get(decoded, "id", model_id),
          name: Map.get(decoded, "id", model_id),
          capabilities: []
        }

        {:ok, model}
      else
        {:error, :not_found} ->
          {:error, :session_not_found}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error,
           {:http_error, status, if(is_binary(body), do: body, else: Jason.encode!(body))}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp detect_auth(session_name) do
    cond do
      is_map(SavedAuthentication.get_by_provider_and_name(:openai, :api_key, session_name)) ->
        {:ok, :api_key}

      is_map(SavedAuthentication.get_by_provider_and_name(:openai, :oauth, session_name)) ->
        {:ok, :oauth}

      true ->
        {:error, :not_found}
    end
  end
end
