defmodule TheMaestro.Providers.Auth.CredentialStore do
  @moduledoc """
  Secure storage and management of provider credentials.

  This module handles the encryption, storage, and retrieval of authentication
  credentials for different LLM providers. Credentials are encrypted at rest
  and indexed for efficient retrieval.
  """

  import Ecto.Query
  alias TheMaestro.Repo
  alias TheMaestro.Providers.Auth.ProviderAuth

  require Logger

  defmodule ProviderCredential do
    @moduledoc """
    Schema for storing encrypted provider credentials.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}

    schema "provider_credentials" do
      field :user_id, :string
      field :provider, :string
      field :auth_method, :string
      field :credentials, :string
      field :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    def changeset(credential, attrs) do
      credential
      |> cast(attrs, [:user_id, :provider, :auth_method, :credentials, :expires_at])
      |> validate_required([:user_id, :provider, :auth_method, :credentials])
      |> validate_inclusion(:provider, ["anthropic", "google", "openai"])
      |> validate_inclusion(:auth_method, ["oauth", "api_key"])
      |> unique_constraint([:user_id, :provider, :auth_method])
    end
  end

  @doc """
  Stores encrypted credentials for a user and provider.

  ## Parameters
    - `user_id`: User identifier
    - `provider`: Provider identifier
    - `method`: Authentication method
    - `credentials`: Raw credentials to encrypt and store

  ## Returns
    - `{:ok, stored_credentials}`: Successfully stored
    - `{:error, reason}`: Storage failed
  """
  @spec store_credentials(String.t(), ProviderAuth.provider(), ProviderAuth.auth_method(), map()) ::
          {:ok, map()} | {:error, term()}
  def store_credentials(user_id, provider, method, credentials) do
    encrypted_creds = encrypt_credentials(credentials)
    expires_at = extract_expiry_time(credentials)

    attrs = %{
      user_id: user_id,
      provider: Atom.to_string(provider),
      auth_method: Atom.to_string(method),
      credentials: encrypted_creds,
      expires_at: expires_at
    }

    changeset = ProviderCredential.changeset(%ProviderCredential{}, attrs)

    case Repo.insert(changeset, 
           on_conflict: {:replace, [:credentials, :expires_at, :updated_at]}, 
           conflict_target: [:user_id, :provider, :auth_method]) do
      {:ok, stored} ->
        Logger.info("Stored credentials for user #{user_id}, provider #{provider}")
        {:ok, decode_stored_credential(stored)}

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error("Failed to store credentials: #{inspect(changeset.errors)}")
        {:error, :storage_failed}

      {:error, reason} ->
        Logger.error("Database error storing credentials: #{inspect(reason)}")
        {:error, :database_error}
    end
  end

  @doc """
  Retrieves and decrypts credentials for a user and provider.

  ## Parameters
    - `user_id`: User identifier
    - `provider`: Provider identifier
    - `method`: Optional specific authentication method

  ## Returns
    - `{:ok, credential_data}`: Credentials found and decrypted
    - `{:error, :not_found}`: No credentials found
    - `{:error, reason}`: Retrieval/decryption failed
  """
  @spec get_credentials(String.t(), ProviderAuth.provider(), ProviderAuth.auth_method() | nil) ::
          {:ok, map()} | {:error, term()}
  def get_credentials(user_id, provider, method \\ nil) do
    query = base_credential_query(user_id, provider, method)

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
            {:ok, decode_stored_credential(updated)}

          {:error, reason} ->
            Logger.error("Failed to update credentials: #{inspect(reason)}")
            {:error, :update_failed}
        end
    end
  end

  @doc """
  Deletes stored credentials.

  ## Parameters
    - `user_id`: User identifier
    - `provider`: Provider identifier
    - `method`: Optional specific authentication method to delete

  ## Returns
    - `:ok`: Credentials deleted
    - `{:error, reason}`: Deletion failed
  """
  @spec delete_credentials(String.t(), ProviderAuth.provider(), ProviderAuth.auth_method() | nil) ::
          :ok | {:error, term()}
  def delete_credentials(user_id, provider, method \\ nil) do
    query = base_credential_query(user_id, provider, method)

    case Repo.delete_all(query) do
      {count, _} when count > 0 ->
        Logger.info("Deleted #{count} credentials for user #{user_id}, provider #{provider}")
        :ok

      {0, _} ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all stored credentials for a user (without sensitive data).

  ## Parameters
    - `user_id`: User identifier

  ## Returns
    List of credential summaries
  """
  @spec list_user_credentials(String.t()) :: [map()]
  def list_user_credentials(user_id) do
    query = from c in ProviderCredential,
            where: c.user_id == ^user_id,
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

  defp base_credential_query(user_id, provider, method) do
    query = from c in ProviderCredential,
            where: c.user_id == ^user_id and c.provider == ^Atom.to_string(provider)

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
        user_id: credential.user_id,
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
    {:ok, decrypted_creds} = decrypt_credentials(credential.credentials)
    
    %{
      id: credential.id,
      user_id: credential.user_id,
      provider: String.to_atom(credential.provider),
      auth_method: String.to_atom(credential.auth_method),
      credentials: decrypted_creds,
      expires_at: credential.expires_at,
      updated_at: credential.updated_at
    }
  end

  defp encrypt_credentials(credentials) do
    # Use application-level encryption key
    key = get_encryption_key()
    plaintext = Jason.encode!(credentials)
    
    # Simple encryption using :crypto.crypto_one_time
    # In production, consider using a more robust encryption scheme
    iv = :crypto.strong_rand_bytes(16)
    ciphertext = :crypto.crypto_one_time(:aes_256_cbc, key, iv, plaintext, true)
    
    # Combine IV and ciphertext
    Base.encode64(iv <> ciphertext)
  end

  defp decrypt_credentials(encrypted_data) do
    try do
      key = get_encryption_key()
      data = Base.decode64!(encrypted_data)
      
      # Extract IV (first 16 bytes) and ciphertext
      <<iv::binary-16, ciphertext::binary>> = data
      plaintext = :crypto.crypto_one_time(:aes_256_cbc, key, iv, ciphertext, false)
      
      case Jason.decode(plaintext) do
        {:ok, credentials} -> {:ok, credentials}
        {:error, _} -> {:error, :decryption_failed}
      end
    rescue
      _ -> {:error, :decryption_failed}
    end
  end

  defp get_encryption_key do
    # Get encryption key from application config or generate one
    # In production, this should be a secure, persistent key
    Application.get_env(:the_maestro, :credential_encryption_key) ||
      :crypto.hash(:sha256, "the_maestro_default_key_change_in_production")
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