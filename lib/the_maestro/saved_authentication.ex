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
          provider: :anthropic | :openai | :gemini,
          auth_type: :api_key | :oauth,
          name: String.t(),
          credentials: map(),
          expires_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "saved_authentications" do
    field :provider, Ecto.Enum, values: [:anthropic, :openai, :gemini]
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
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(saved_authentication, attrs) do
    saved_authentication
    |> cast(attrs, [:provider, :auth_type, :name, :credentials, :expires_at])
    |> validate_required([:provider, :auth_type, :name, :credentials])
    |> validate_inclusion(:provider, [:anthropic, :openai, :gemini])
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
      where: sa.provider == ^provider and sa.auth_type == ^auth_type and sa.name == ^name
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
      where: sa.provider == ^provider,
      order_by: [asc: sa.auth_type, asc: sa.name]
    )
    |> Repo.all()
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
  @spec create_named_session(atom(), atom(), String.t(), map()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create_named_session(provider, auth_type, name, attrs) do
    alias TheMaestro.Repo

    full_attrs =
      attrs
      |> Map.put(:provider, provider)
      |> Map.put(:auth_type, auth_type)
      |> Map.put(:name, name)

    %__MODULE__{}
    |> changeset(full_attrs)
    |> Repo.insert()
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
  @spec upsert_named_session(atom(), atom(), String.t(), map()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def upsert_named_session(provider, auth_type, name, attrs) do
    alias TheMaestro.Repo

    full_attrs =
      attrs
      |> Map.put(:provider, provider)
      |> Map.put(:auth_type, auth_type)
      |> Map.put(:name, name)

    %__MODULE__{}
    |> changeset(full_attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:credentials, :expires_at, :updated_at]},
      conflict_target: [:provider, :auth_type, :name]
    )
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

    case get_by_provider_and_name(provider, auth_type, name) do
      nil ->
        {:error, :not_found}

      saved_auth ->
        case Repo.delete(saved_auth) do
          {:ok, _} -> :ok
          error -> error
        end
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
end
