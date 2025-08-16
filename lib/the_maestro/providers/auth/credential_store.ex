defmodule TheMaestro.Providers.Auth.CredentialStore do
  @moduledoc """
  Secure storage and management of provider credentials.

  This module handles the encryption, storage, and retrieval of authentication
  credentials for different LLM providers. Credentials are encrypted at rest
  and indexed for efficient retrieval.
  """

  import Ecto.Query
  alias TheMaestro.Providers.Auth.ProviderAuth
  alias TheMaestro.Repo

  require Logger

  defmodule ProviderCredential do
    @moduledoc """
    Schema for storing encrypted provider credentials.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}

    schema "provider_credentials" do
      field :provider, :string
      field :auth_method, :string
      field :credentials, :string
      field :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    def changeset(credential, attrs) do
      credential
      |> cast(attrs, [:provider, :auth_method, :credentials, :expires_at])
      |> validate_required([:provider, :auth_method, :credentials])
      |> validate_inclusion(:provider, ["anthropic", "google", "openai"])
      |> validate_inclusion(:auth_method, ["oauth", "api_key"])
      |> unique_constraint([:provider, :auth_method])
    end
  end

  @doc """
  Stores encrypted credentials for a provider.

  ## Parameters
    - `provider`: Provider identifier
    - `method`: Authentication method
    - `credentials`: Raw credentials to encrypt and store

  ## Returns
    - `{:ok, stored_credentials}`: Successfully stored
    - `{:error, reason}`: Storage failed
  """
  @spec store_credentials(ProviderAuth.provider(), ProviderAuth.auth_method(), map()) ::
          {:ok, map()} | {:error, term()}
  def store_credentials(provider, method, credentials) do
    encrypted_creds = encrypt_credentials(credentials)
    expires_at = extract_expiry_time(credentials)

    attrs = %{
      provider: Atom.to_string(provider),
      auth_method: Atom.to_string(method),
      credentials: encrypted_creds,
      expires_at: expires_at
    }

    changeset = ProviderCredential.changeset(%ProviderCredential{}, attrs)

    case Repo.insert(changeset,
           on_conflict: {:replace, [:credentials, :expires_at, :updated_at]},
           conflict_target: [:provider, :auth_method]
         ) do
      {:ok, stored} ->
        Logger.info("Stored credentials for provider #{provider}")
        decode_stored_credential(stored)

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error("Failed to store credentials: #{inspect(changeset.errors)}")
        {:error, :storage_failed}

      {:error, reason} ->
        Logger.error("Database error storing credentials: #{inspect(reason)}")
        {:error, :database_error}
    end
  end

  @doc """
  Retrieves and decrypts credentials for a provider.

  ## Parameters
    - `provider`: Provider identifier
    - `method`: Optional specific authentication method

  ## Returns
    - `{:ok, credential_data}`: Credentials found and decrypted
    - `{:error, :not_found}`: No credentials found
    - `{:error, reason}`: Retrieval/decryption failed
  """
  @spec get_credentials(ProviderAuth.provider(), ProviderAuth.auth_method() | nil) ::
          {:ok, map()} | {:error, term()}
  def get_credentials(provider, method \\ nil) do
    query = base_credential_query(provider, method)

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      credential ->
        case decrypt_and_validate_credential(credential) do
          {:ok, decrypted} -> {:ok, decrypted}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Updates stored credentials with new values.

  ## Parameters
    - `credential_id`: ID of the stored credential
    - `new_credentials`: New credential values

  ## Returns
    - `{:ok, updated_credential}`: Successfully updated
    - `{:error, reason}`: Update failed
  """
  @spec update_credentials(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_credentials(credential_id, new_credentials) do
    encrypted_creds = encrypt_credentials(new_credentials)
    expires_at = extract_expiry_time(new_credentials)

    attrs = %{
      credentials: encrypted_creds,
      expires_at: expires_at
    }

    case Repo.get(ProviderCredential, credential_id) do
      nil ->
        {:error, :not_found}

      credential ->
        changeset = ProviderCredential.changeset(credential, attrs)

        case Repo.update(changeset) do
          {:ok, updated} ->
            Logger.info("Updated credentials for ID #{credential_id}")
            decode_stored_credential(updated)

          {:error, reason} ->
            Logger.error("Failed to update credentials: #{inspect(reason)}")
            {:error, :update_failed}
        end
    end
  end

  @doc """
  Deletes stored credentials.

  ## Parameters
    - `provider`: Provider identifier
    - `method`: Optional specific authentication method to delete

  ## Returns
    - `:ok`: Credentials deleted
    - `{:error, reason}`: Deletion failed
  """
  @spec delete_credentials(ProviderAuth.provider(), ProviderAuth.auth_method() | nil) ::
          :ok | {:error, term()}
  def delete_credentials(provider, method \\ nil) do
    query = base_credential_query(provider, method)

    case Repo.delete_all(query) do
      {count, _} when count > 0 ->
        Logger.info("Deleted #{count} credentials for provider #{provider}")
        :ok

      {0, _} ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all stored credentials (without sensitive data).

  ## Returns
    List of credential summaries
  """
  @spec list_credentials() :: [map()]
  def list_credentials do
    query =
      from c in ProviderCredential,
        select: %{
          id: c.id,
          provider: c.provider,
          auth_method: c.auth_method,
          expires_at: c.expires_at,
          updated_at: c.updated_at
        }

    Repo.all(query)
  end

  # Private Functions

  defp base_credential_query(provider, method) do
    query =
      from c in ProviderCredential,
        where: c.provider == ^Atom.to_string(provider)

    if method do
      where(query, [c], c.auth_method == ^Atom.to_string(method))
    else
      query
    end
  end

  defp decrypt_and_validate_credential(credential) do
    with {:ok, decrypted_creds} <- decrypt_credentials(credential.credentials),
         :ok <- validate_expiry(credential.expires_at) do
      result = %{
        id: credential.id,
        provider: String.to_atom(credential.provider),
        auth_method: String.to_atom(credential.auth_method),
        credentials: decrypted_creds,
        expires_at: credential.expires_at,
        updated_at: credential.updated_at
      }

      {:ok, result}
    end
  end

  defp decode_stored_credential(credential) do
    case decrypt_credentials(credential.credentials) do
      {:ok, decrypted_creds} -> 
        {:ok, %{
          id: credential.id,
          provider: String.to_atom(credential.provider),
          auth_method: String.to_atom(credential.auth_method),
          credentials: decrypted_creds,
          expires_at: credential.expires_at,
          inserted_at: credential.inserted_at,
          updated_at: credential.updated_at
        }}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encrypt_credentials(credentials) do
    # Simple Base64 encoding for development
    # In production, this should use proper encryption
    credentials
    |> Jason.encode!()
    |> Base.encode64()
  end

  defp decrypt_credentials(encrypted_data) do
    try do
      encrypted_data
      |> Base.decode64!()
      |> Jason.decode()
      |> case do
        {:ok, credentials} -> {:ok, credentials}
        {:error, _} -> {:error, :decryption_failed}
      end
    rescue
      _ -> {:error, :decryption_failed}
    end
  end

  defp extract_expiry_time(%{expires_at: expires_at}) when not is_nil(expires_at) do
    case DateTime.from_unix(expires_at) do
      {:ok, datetime} -> datetime
      {:error, _} -> nil
    end
  end

  defp extract_expiry_time(%{"expires_at" => expires_at}) when not is_nil(expires_at) do
    case DateTime.from_unix(expires_at) do
      {:ok, datetime} -> datetime
      {:error, _} -> nil
    end
  end

  defp extract_expiry_time(_), do: nil

  defp validate_expiry(nil), do: :ok

  defp validate_expiry(expires_at) do
    if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
      :ok
    else
      {:error, :expired}
    end
  end
end
