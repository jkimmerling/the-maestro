defmodule TheMaestro.Auth.SavedAuthentication do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "saved_authentications" do
    field :provider, :string
    field :auth_type, Ecto.Enum, values: [:api_key, :oauth]
    field :name, :string
    field :credentials, :map
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(saved_authentication, attrs) do
    saved_authentication
    |> cast(attrs, [:provider, :auth_type, :name, :credentials, :expires_at])
    |> validate_required([:provider, :auth_type, :name, :expires_at])
  end
end
