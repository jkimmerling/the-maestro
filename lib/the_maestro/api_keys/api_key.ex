defmodule TheMaestro.ApiKeys.ApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_keys" do
    field :label, :string
    field :token_hash, :string
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:label, :token_hash, :last_used_at, :revoked_at])
    |> validate_required([:label, :token_hash])
    |> unique_constraint(:token_hash)
  end
end
