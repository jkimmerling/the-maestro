defmodule TheMaestro.SavedAuthenticationTest do
  use ExUnit.Case, async: true
  use TheMaestro.DataCase

  alias TheMaestro.SavedAuthentication

  describe "changeset/2" do
    test "valid OAuth changeset with all required fields" do
      valid_attrs = %{
        provider: :anthropic,
        auth_type: :oauth,
        name: "test_session",
        credentials: %{
          "access_token" => "sk-ant-oat01-test-token",
          "refresh_token" => "sk-ant-oar01-test-refresh",
          "token_type" => "Bearer",
          "scope" => "user:profile user:inference"
        },
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      changeset = SavedAuthentication.changeset(%SavedAuthentication{}, valid_attrs)

      assert changeset.valid?
      refute changeset.errors != []
    end

    test "valid API key changeset" do
      valid_attrs = %{
        provider: :anthropic,
        auth_type: :api_key,
        name: "test_api_session",
        credentials: %{
          "api_key" => "sk-ant-api03-test-key"
        }
        # No expires_at needed for API keys
      }

      changeset = SavedAuthentication.changeset(%SavedAuthentication{}, valid_attrs)

      assert changeset.valid?
      refute changeset.errors != []
    end

    test "requires provider field" do
      invalid_attrs = %{
        auth_type: :oauth,
        credentials: %{"access_token" => "token"},
        expires_at: DateTime.utc_now()
      }

      changeset = SavedAuthentication.changeset(%SavedAuthentication{}, invalid_attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset)[:provider]
    end

    test "requires auth_type field" do
      invalid_attrs = %{
        provider: :anthropic,
        name: "test_session",
        credentials: %{"access_token" => "token"}
      }

      changeset = SavedAuthentication.changeset(%SavedAuthentication{}, invalid_attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset)[:auth_type]
    end

    test "requires credentials field" do
      invalid_attrs = %{
        provider: :anthropic,
        auth_type: :oauth,
        name: "test_session",
        expires_at: DateTime.utc_now()
      }

      changeset = SavedAuthentication.changeset(%SavedAuthentication{}, invalid_attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset)[:credentials]
    end

    test "accepts dynamic provider values (no inclusion list)" do
      attrs = %{
        provider: :new_provider,
        auth_type: :oauth,
        name: "test_session",
        credentials: %{"access_token" => "token"},
        expires_at: DateTime.utc_now()
      }

      changeset = SavedAuthentication.changeset(%SavedAuthentication{}, attrs)
      assert changeset.valid?
      refute changeset.errors != []
    end

    test "validates auth_type inclusion" do
      invalid_attrs = %{
        provider: :anthropic,
        auth_type: :invalid_auth,
        name: "test_session",
        credentials: %{"access_token" => "token"}
      }

      changeset = SavedAuthentication.changeset(%SavedAuthentication{}, invalid_attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset)[:auth_type]
    end

    test "requires expires_at for OAuth authentication" do
      invalid_attrs = %{
        provider: :anthropic,
        auth_type: :oauth,
        name: "test_session",
        credentials: %{
          "access_token" => "sk-ant-oat01-token",
          "refresh_token" => "sk-ant-oar01-refresh"
        }
        # Missing expires_at
      }

      changeset = SavedAuthentication.changeset(%SavedAuthentication{}, invalid_attrs)

      refute changeset.valid?
      assert "is required for OAuth authentication" in errors_on(changeset)[:expires_at]
    end

    test "allows nil expires_at for API key authentication" do
      valid_attrs = %{
        provider: :anthropic,
        auth_type: :api_key,
        name: "test_session",
        credentials: %{"api_key" => "sk-ant-api03-key"},
        expires_at: nil
      }

      changeset = SavedAuthentication.changeset(%SavedAuthentication{}, valid_attrs)

      assert changeset.valid?
    end

    test "accepts all valid providers" do
      for provider <- [:anthropic, :openai, :gemini] do
        attrs = %{
          provider: provider,
          auth_type: :api_key,
          name: "test_session_#{provider}",
          credentials: %{"api_key" => "test-key-#{provider}"}
        }

        changeset = SavedAuthentication.changeset(%SavedAuthentication{}, attrs)
        assert changeset.valid?, "#{provider} should be a valid provider"
      end
    end

    test "accepts both auth types" do
      base_attrs = %{
        provider: :anthropic,
        name: "test_session",
        credentials: %{"access_token" => "token"}
      }

      # Test API key auth type
      api_key_attrs = Map.put(base_attrs, :auth_type, :api_key)
      changeset = SavedAuthentication.changeset(%SavedAuthentication{}, api_key_attrs)
      assert changeset.valid?

      # Test OAuth auth type (with expires_at)
      oauth_attrs =
        base_attrs
        |> Map.put(:auth_type, :oauth)
        |> Map.put(:expires_at, DateTime.utc_now())

      changeset = SavedAuthentication.changeset(%SavedAuthentication{}, oauth_attrs)
      assert changeset.valid?
    end
  end

  describe "database operations" do
    test "successfully inserts valid OAuth authentication" do
      valid_attrs = %{
        provider: :anthropic,
        auth_type: :oauth,
        name: "test_session",
        credentials: %{
          "access_token" => "sk-ant-oat01-db-test",
          "refresh_token" => "sk-ant-oar01-db-test",
          "token_type" => "Bearer"
        },
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      {:ok, saved_auth} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(valid_attrs)
        |> Repo.insert()

      assert saved_auth.id
      assert saved_auth.provider == :anthropic
      assert saved_auth.auth_type == :oauth
      assert saved_auth.credentials["access_token"] == "sk-ant-oat01-db-test"
      assert saved_auth.inserted_at
      assert saved_auth.updated_at
    end

    test "successfully inserts valid API key authentication" do
      valid_attrs = %{
        provider: :openai,
        auth_type: :api_key,
        name: "test_session",
        credentials: %{
          "api_key" => "sk-openai-test-key"
        }
      }

      {:ok, saved_auth} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(valid_attrs)
        |> Repo.insert()

      assert saved_auth.id
      assert saved_auth.provider == :openai
      assert saved_auth.auth_type == :api_key
      assert saved_auth.credentials["api_key"] == "sk-openai-test-key"
      assert is_nil(saved_auth.expires_at)
    end

    test "enforces unique constraint on provider, auth_type, and name" do
      attrs = %{
        provider: :anthropic,
        auth_type: :oauth,
        name: "test_session",
        credentials: %{"access_token" => "token1"},
        expires_at: DateTime.utc_now()
      }

      # Insert first record
      {:ok, _} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(attrs)
        |> Repo.insert()

      # Try to insert duplicate with same name
      duplicate_attrs = %{attrs | credentials: %{"access_token" => "token2"}}

      {:error, changeset} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(duplicate_attrs)
        |> Repo.insert()

      refute changeset.valid?

      # Should allow same provider/auth_type with different name
      different_name_attrs = %{
        attrs
        | name: "different_session",
          credentials: %{"access_token" => "token3"}
      }

      {:ok, _} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(different_name_attrs)
        |> Repo.insert()
    end

    test "allows same provider with different auth types" do
      # Insert OAuth token
      oauth_attrs = %{
        provider: :anthropic,
        auth_type: :oauth,
        name: "oauth_session",
        credentials: %{"access_token" => "oauth-token"},
        expires_at: DateTime.utc_now()
      }

      {:ok, _oauth_auth} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(oauth_attrs)
        |> Repo.insert()

      # Insert API key for same provider - should succeed
      api_key_attrs = %{
        provider: :anthropic,
        auth_type: :api_key,
        name: "api_key_session",
        credentials: %{"api_key" => "api-key-token"}
      }

      {:ok, api_auth} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(api_key_attrs)
        |> Repo.insert()

      assert api_auth.provider == :anthropic
      assert api_auth.auth_type == :api_key
    end

    test "credentials are stored as JSONB map" do
      complex_credentials = %{
        "access_token" => "sk-ant-oat01-complex",
        "refresh_token" => "sk-ant-oar01-complex",
        "token_type" => "Bearer",
        "scope" => "user:profile user:inference",
        "metadata" => %{
          "issued_at" => "2023-12-01T10:00:00Z",
          "client_id" => "test-client"
        }
      }

      {:ok, saved_auth} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(%{
          provider: :anthropic,
          auth_type: :oauth,
          name: "complex_session",
          credentials: complex_credentials,
          expires_at: DateTime.utc_now()
        })
        |> Repo.insert()

      # Reload from database
      reloaded = Repo.get!(SavedAuthentication, saved_auth.id)

      assert reloaded.credentials["access_token"] == "sk-ant-oat01-complex"
      assert reloaded.credentials["metadata"]["client_id"] == "test-client"
      assert is_map(reloaded.credentials["metadata"])
    end

    test "querying by provider and auth_type" do
      # Insert multiple authentications
      providers_and_types = [
        {:anthropic, :oauth},
        {:anthropic, :api_key},
        {:openai, :api_key},
        {:gemini, :api_key}
      ]

      for {provider, auth_type} <- providers_and_types do
        attrs = %{
          provider: provider,
          auth_type: auth_type,
          name: "session_#{provider}_#{auth_type}",
          credentials: %{"token" => "#{provider}-#{auth_type}"}
        }

        attrs =
          if auth_type == :oauth do
            Map.put(attrs, :expires_at, DateTime.utc_now())
          else
            attrs
          end

        {:ok, _} =
          %SavedAuthentication{}
          |> SavedAuthentication.changeset(attrs)
          |> Repo.insert()
      end

      # Query for specific provider, auth type, and name
      anthropic_oauth =
        Repo.get_by(SavedAuthentication,
          provider: :anthropic,
          auth_type: :oauth,
          name: "session_anthropic_oauth"
        )

      assert anthropic_oauth
      assert anthropic_oauth.credentials["token"] == "anthropic-oauth"

      # Query for all authentications for a provider
      anthropic_auths =
        Repo.all(
          from sa in SavedAuthentication,
            where: sa.provider == :anthropic
        )

      assert length(anthropic_auths) == 2
      auth_types = Enum.map(anthropic_auths, & &1.auth_type)
      assert :oauth in auth_types
      assert :api_key in auth_types
    end
  end
end
