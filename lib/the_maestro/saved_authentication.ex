defmodule TheMaestro.SavedAuthentication do
  @moduledoc """
  Schema for storing encrypted OAuth tokens and API keys per provider.
  
  This table stores all authentication credentials for different providers,
  encrypted at rest using cloak_ecto for security. Supports both OAuth tokens
  and API key authentication modes.
  
  ## Fields
  
  * `provider` - The AI provider (anthropic, openai, gemini)
  * `auth_type` - Authentication type (oauth or api_key) 
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
          credentials: map(),
          expires_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "saved_authentications" do
    field :provider, Ecto.Enum, values: [:anthropic, :openai, :gemini]
    field :auth_type, Ecto.Enum, values: [:api_key, :oauth]
    field :credentials, :map
    field :expires_at, :utc_datetime

    timestamps()
  end

  @doc """
  Changeset for creating and updating saved authentications.
  
  ## Parameters
  
  * `saved_authentication` - The struct to update
  * `attrs` - Attributes to change
  
  ## Required Fields
  
  * `provider` - Must be one of [:anthropic, :openai, :gemini]
  * `auth_type` - Must be one of [:api_key, :oauth]  
  * `credentials` - Map containing the encrypted credentials
  
  ## Optional Fields
  
  * `expires_at` - DateTime for when credentials expire (required for OAuth)
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(saved_authentication, attrs) do
    saved_authentication
    |> cast(attrs, [:provider, :auth_type, :credentials, :expires_at])
    |> validate_required([:provider, :auth_type, :credentials])
    |> validate_inclusion(:provider, [:anthropic, :openai, :gemini])
    |> validate_inclusion(:auth_type, [:api_key, :oauth])
    |> validate_oauth_expiry()
    |> unique_constraint([:provider, :auth_type],
         name: "saved_authentications_provider_auth_type_index",
         message: "Authentication already exists for this provider and auth type")
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
end