defmodule TheMaestro.SavedAuthentication do
  @moduledoc """
  Schema for storing encrypted OAuth tokens and API keys per provider with named sessions.

  This table stores all authentication credentials for different providers,
  encrypted at rest using cloak_ecto for security. Supports both OAuth tokens
  and API key authentication modes with multiple named sessions per provider/auth_type.

  ## Fields

  * `provider` - The AI provider (anthropic, openai, gemini)
  * `auth_type` - Authentication type (oauth or api_key) 
  * `name` - User-defined session name (e.g., "work_claude", "personal_gpt")
  * `credentials` - Encrypted JSONB storing the actual credentials
  * `expires_at` - When the credentials expire (for OAuth tokens)

  ## Examples

      # OAuth token credentials structure
      %{
        "access_token" => "sk-ant-oat01-...",
        "refresh_token" => "sk-ant-oar01-...",
        "token_type" => "Bearer",
        "scope" => "user:profile user:inference"
      }
      
      # API key credentials structure  
      %{
        "api_key" => "sk-ant-api03-..."
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          provider: atom(),
          auth_type: :api_key | :oauth,
          name: String.t(),
          credentials: map(),
          expires_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @typedoc "Attributes for changesets - ALL keys must be atoms"
  @type attrs :: %{optional(atom()) => any()}

  schema "saved_authentications" do
    field :provider, TheMaestro.EctoTypes.Provider
    field :auth_type, Ecto.Enum, values: [:api_key, :oauth]
    field :name, :string
    field :credentials, :map
    field :expires_at, :utc_datetime

    timestamps()
  end

  @doc """
  Changeset for creating and updating saved authentications with named sessions.

  ## Parameters

  * `saved_authentication` - The struct to update
  * `attrs` - Attributes to change

  ## Required Fields

  * `provider` - Must be one of [:anthropic, :openai, :gemini]
  * `auth_type` - Must be one of [:api_key, :oauth]  
  * `name` - Session name (3-50 characters, alphanumeric + underscore/hyphen)
  * `credentials` - Map containing the encrypted credentials

  ## Optional Fields

  * `expires_at` - DateTime for when credentials expire (required for OAuth)
  """
  @spec changeset(t(), attrs() | map()) :: Ecto.Changeset.t()
  def changeset(saved_authentication, attrs) do
    # Ensure all keys are atoms
    atomized_attrs = atomize_keys(attrs)

    saved_authentication
    |> cast(atomized_attrs, [:provider, :auth_type, :name, :credentials, :expires_at])
    |> validate_required([:provider, :auth_type, :name, :credentials])
    # provider is a dynamic value; validated by domain flows during usage
    |> validate_inclusion(:auth_type, [:api_key, :oauth])
    |> validate_name()
    |> validate_oauth_expiry()
    |> unique_constraint([:provider, :auth_type, :name],
      name: "saved_authentications_provider_auth_type_name_index",
      message: "Authentication already exists for this provider, auth type, and name"
    )
  end

  # Validate session name format and length
  defp validate_name(changeset) do
    changeset
    |> validate_format(:name, ~r/^[a-zA-Z0-9_-]+$/,
      message: "must contain only letters, numbers, underscores, and hyphens"
    )
    |> validate_length(:name, min: 3, max: 50)
  end

  # Validate that OAuth tokens have an expiry date
  defp validate_oauth_expiry(%Ecto.Changeset{} = changeset) do
    auth_type = get_field(changeset, :auth_type)
    expires_at = get_field(changeset, :expires_at)

    case {auth_type, expires_at} do
      {:oauth, nil} ->
        add_error(changeset, :expires_at, "is required for OAuth authentication")

      _ ->
        changeset
    end
  end

  # Helper to ensure all map keys are atoms
  # Only converts known keys that are safe to atomize
  @doc false
  @spec atomize_keys(map()) :: map()
  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {"provider", value} -> {:provider, value}
      {"auth_type", value} -> {:auth_type, value}
      {"name", value} -> {:name, value}
      {"credentials", value} -> {:credentials, value}
      {"expires_at", value} -> {:expires_at, value}
      {key, value} when is_atom(key) -> {key, value}
      # Keep unknown string keys as-is (they'll be ignored by cast anyway)
      {key, value} -> {key, value}
    end)
    |> Enum.into(%{})
  end

  # ===== Named Session Helper Functions =====

  @doc """
  Gets a saved authentication by provider, auth type, and session name.

  ## Parameters

  * `provider` - The provider atom (:anthropic, :openai, :gemini)
  * `auth_type` - The authentication type (:oauth, :api_key)
  * `name` - The session name

  ## Returns

  Returns the SavedAuthentication struct or nil if not found.
  """
  @spec get_by_provider_and_name(atom(), atom(), String.t()) :: t() | nil
  def get_by_provider_and_name(provider, auth_type, name) do
    alias TheMaestro.Repo
    import Ecto.Query

    from(sa in __MODULE__,
      where:
        sa.provider == ^provider_to_db(provider) and sa.auth_type == ^auth_type and
          sa.name == ^name
    )
    |> Repo.one()
  end

  @doc """
  Lists all saved authentications for a given provider.

  ## Parameters

  * `provider` - The provider atom (:anthropic, :openai, :gemini)

  ## Returns

  Returns a list of SavedAuthentication structs.
  """
  @spec list_by_provider(atom()) :: [t()]
  def list_by_provider(provider) do
    alias TheMaestro.Repo
    import Ecto.Query

    from(sa in __MODULE__,
      where: sa.provider == ^provider_to_db(provider),
      order_by: [asc: sa.auth_type, asc: sa.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists all saved authentications across all providers.

  Results are ordered by `inserted_at` descending, then by provider/auth_type/name
  for stable display in UIs.
  """
  @spec list_all() :: [t()]
  def list_all do
    alias TheMaestro.Repo
    import Ecto.Query

    from(sa in __MODULE__,
      order_by: [desc: sa.inserted_at, asc: sa.provider, asc: sa.auth_type, asc: sa.name]
    )
    |> Repo.all()
  end

  @doc """
  Fetches a single saved authentication by id.
  Raises if not found.
  """
  @spec get!(integer()) :: t()
  def get!(id) when is_integer(id) do
    alias TheMaestro.Repo
    Repo.get!(__MODULE__, id)
  end

  @doc """
  Updates a saved authentication record.

  Only `name`, `credentials`, and `expires_at` are expected to change post‑creation.
  Provider and auth_type are treated as immutable for existing records.
  """
  @spec update(t(), attrs()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(%__MODULE__{} = saved_auth, attrs) do
    alias TheMaestro.Repo

    saved_auth
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a new named session for the given provider and auth type.

  ## Parameters

  * `provider` - The provider atom (:anthropic, :openai, :gemini)
  * `auth_type` - The authentication type (:oauth, :api_key)
  * `name` - The session name
  * `attrs` - Additional attributes (credentials, expires_at, etc.)

  ## Returns

  Returns {:ok, saved_authentication} or {:error, changeset}.
  """
  @spec create_named_session(atom(), atom(), String.t(), attrs()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  @dialyzer {:nowarn_function, create_named_session: 4}
  def create_named_session(provider, auth_type, name, attrs) do
    alias TheMaestro.Repo
    alias TheMaestro.Workers.TokenRefreshWorker

    atomized = atomize_keys(attrs)
    normalized = normalize_credentials_for_auth(auth_type, atomized)

    full_attrs =
      normalized
      |> Map.put(:provider, provider)
      |> Map.put(:auth_type, auth_type)
      |> Map.put(:name, name)

    with {:ok, saved} <- %__MODULE__{} |> changeset(full_attrs) |> Repo.insert() do
      if auth_type == :oauth do
        _ = TokenRefreshWorker.schedule_for_auth(saved)
      end

      {:ok, saved}
    end
  end

  @doc """
  Upserts a named session - creates or updates as needed.

  ## Parameters

  * `provider` - The provider atom (:anthropic, :openai, :gemini)
  * `auth_type` - The authentication type (:oauth, :api_key)
  * `name` - The session name
  * `attrs` - Attributes to set or update

  ## Returns

  Returns {:ok, saved_authentication} or {:error, changeset}.
  """
  @spec upsert_named_session(atom(), atom(), String.t(), attrs()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  @dialyzer {:nowarn_function, upsert_named_session: 4}
  def upsert_named_session(provider, auth_type, name, attrs) do
    alias TheMaestro.Repo
    alias TheMaestro.Workers.TokenRefreshWorker

    atomized = atomize_keys(attrs)
    normalized = normalize_credentials_for_auth(auth_type, atomized)

    full_attrs =
      normalized
      |> Map.put(:provider, provider)
      |> Map.put(:auth_type, auth_type)
      |> Map.put(:name, name)

    with {:ok, saved} <-
           %__MODULE__{}
           |> changeset(full_attrs)
           |> Repo.insert(
             on_conflict: {:replace, [:credentials, :expires_at, :updated_at]},
             conflict_target: [:provider, :auth_type, :name]
           ) do
      if auth_type == :oauth do
        _ = TokenRefreshWorker.schedule_for_auth(saved)
      end

      {:ok, saved}
    end
  end

  @doc """
  Deletes a named session by provider, auth type, and name.

  ## Parameters

  * `provider` - The provider atom (:anthropic, :openai, :gemini)
  * `auth_type` - The authentication type (:oauth, :api_key)
  * `name` - The session name

  ## Returns

  Returns :ok or {:error, reason}.
  """
  @spec delete_named_session(atom(), atom(), String.t()) :: :ok | {:error, term()}
  def delete_named_session(provider, auth_type, name) do
    alias TheMaestro.Repo
    alias TheMaestro.Workers.TokenRefreshWorker

    case get_by_provider_and_name(provider, auth_type, name) do
      nil ->
        {:error, :not_found}

      saved_auth ->
        if auth_type == :oauth do
          _ = TokenRefreshWorker.cancel_for_auth(saved_auth)
        end

        case Repo.delete(saved_auth) do
          {:ok, _} -> :ok
          error -> error
        end
    end
  end

  @doc """
  Clones an existing named session into a new session name for the same provider/auth_type.

  Returns {:ok, cloned} or {:error, reason}.
  """
  @spec clone_named_session(atom(), atom(), String.t(), String.t()) ::
          {:ok, t()} | {:error, term()}
  def clone_named_session(provider, auth_type, from_name, to_name) do
    alias TheMaestro.Repo

    case get_by_provider_and_name(provider, auth_type, from_name) do
      nil ->
        {:error, :source_session_not_found}

      %__MODULE__{credentials: creds, expires_at: exp} ->
        create_named_session(provider, auth_type, to_name, %{credentials: creds, expires_at: exp})
    end
  end

  @doc """
  Gets a legacy saved authentication (for backwards compatibility).
  Uses "default_{provider}_{auth_type}" as the session name.

  ## Parameters

  * `provider` - The provider atom (:anthropic, :openai, :gemini)
  * `auth_type` - The authentication type (:oauth, :api_key)

  ## Returns

  Returns the SavedAuthentication struct or nil if not found.
  """
  @spec get_by_provider(atom(), atom()) :: t() | nil
  def get_by_provider(provider, auth_type) do
    name = "default_#{provider}_#{auth_type}"
    get_by_provider_and_name(provider, auth_type, name)
  end

  @doc """
  Gets a named session (alias of get_by_provider_and_name/3).
  """
  @spec get_named_session(atom(), atom(), String.t()) :: t() | nil
  def get_named_session(provider, auth_type, name) do
    get_by_provider_and_name(provider, auth_type, name)
  end

  # ===== Internal helpers =====

  @doc false
  @spec normalize_credentials_for_auth(atom(), map()) :: map()
  defp normalize_credentials_for_auth(:api_key, attrs) when is_map(attrs) do
    cond do
      credentials_present?(attrs) -> attrs
      api_key = extract_api_key(attrs) -> Map.put(attrs, :credentials, %{"api_key" => api_key})
      true -> attrs
    end
  end

  defp normalize_credentials_for_auth(:oauth, attrs) when is_map(attrs) do
    cond do
      credentials_present?(attrs) -> attrs
      (cred = oauth_tokens_from(attrs)) != %{} -> Map.put(attrs, :credentials, cred)
      true -> attrs
    end
  end

  defp normalize_credentials_for_auth(_other, attrs), do: attrs

  defp credentials_present?(attrs) do
    (Map.has_key?(attrs, :credentials) and is_map(attrs[:credentials])) or
      (Map.has_key?(attrs, "credentials") and is_map(attrs["credentials"]))
  end

  defp extract_api_key(attrs), do: attrs[:api_key] || attrs["api_key"]

  defp oauth_tokens_from(attrs) do
    %{}
    |> put_if_present("access_token", attrs[:access_token] || attrs["access_token"])
    |> put_if_present("refresh_token", attrs[:refresh_token] || attrs["refresh_token"])
    |> put_if_present("token_type", attrs[:token_type] || attrs["token_type"])
    |> put_if_present("scope", attrs[:scope] || attrs["scope"])
  end

  defp put_if_present(map, _k, nil), do: map
  defp put_if_present(map, k, v), do: Map.put(map, k, v)
  defp provider_to_db(p) when is_atom(p), do: Atom.to_string(p)
  defp provider_to_db(p) when is_binary(p), do: p
end
