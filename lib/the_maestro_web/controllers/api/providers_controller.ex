defmodule TheMaestroWeb.Api.ProvidersController do
  use TheMaestroWeb, :controller

  alias TheMaestro.Auth
  alias TheMaestro.Provider

  def index(conn, _params) do
    providers = Provider.list_providers() |> Enum.map(&Atom.to_string/1)
    json(conn, %{providers: providers})
  end

  def saved_auths(conn, %{"provider" => provider}) do
    list = Auth.list_saved_authentications_by_provider(provider)

    auths =
      Enum.map(list, fn sa ->
        %{id: to_string(sa.id), label: sa.name, auth_type: sa.auth_type}
      end)

    json(conn, %{auths: auths})
  end

  def models(conn, %{"auth_id" => auth_id}) do
    case TheMaestro.Chat.list_models(auth_id) do
      {:ok, models} ->
        json(conn, %{models: models})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end
end
