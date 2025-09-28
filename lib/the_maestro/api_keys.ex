defmodule TheMaestro.ApiKeys do
  @moduledoc "API key management (DB-backed)."
  import Ecto.Query, warn: false
  alias TheMaestro.ApiKeys.ApiKey
  alias TheMaestro.Repo

  def list_keys do
    Repo.all(from k in ApiKey, order_by: [desc: k.inserted_at])
  end

  def get_key!(id), do: Repo.get!(ApiKey, id)

  def create_key!(label) when is_binary(label) do
    token = Base.encode32(:crypto.strong_rand_bytes(20), case: :lower, padding: false)
    hash = hash_token(token)
    changeset =
      %ApiKey{}
      |> ApiKey.changeset(%{label: label, token_hash: hash})
    key = Repo.insert!(changeset)
    {key, token}
  end

  def revoke!(%ApiKey{} = key) do
    key |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update!()
  end

  def rotate!(%ApiKey{} = key) do
    token = Base.encode32(:crypto.strong_rand_bytes(20), case: :lower, padding: false)
    hash = hash_token(token)
    key = key |> Ecto.Changeset.change(token_hash: hash, revoked_at: nil) |> Repo.update!()
    {key, token}
  end

  def mark_used!(%ApiKey{} = key) do
    key |> Ecto.Changeset.change(last_used_at: DateTime.utc_now()) |> Repo.update!()
  end

  def lookup_valid_by_token(token) when is_binary(token) do
    hash = hash_token(token)
    Repo.one(from k in ApiKey, where: is_nil(k.revoked_at) and k.token_hash == ^hash)
  end

  def hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end
end
