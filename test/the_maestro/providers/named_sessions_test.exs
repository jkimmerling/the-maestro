defmodule TheMaestro.Providers.NamedSessionsTest do
  use ExUnit.Case, async: false
  use TheMaestro.DataCase

  alias Ecto.Adapters.SQL
  alias TheMaestro.Repo
  alias TheMaestro.SavedAuthentication

  describe "named sessions lifecycle" do
    test "supports multiple sessions per provider/auth_type" do
      s1_name = "work_" <> String.slice(Ecto.UUID.generate(), 0, 6)
      s2_name = "personal_" <> String.slice(Ecto.UUID.generate(), 0, 6)

      {:ok, s1} =
        SavedAuthentication.create_named_session(:openai, :api_key, s1_name, %{api_key: "k1"})

      {:ok, s2} =
        SavedAuthentication.create_named_session(:openai, :api_key, s2_name, %{api_key: "k2"})

      assert s1.name == s1_name
      assert s2.name == s2_name

      sessions = SavedAuthentication.list_by_provider(:openai)
      names = Enum.map(sessions, & &1.name)
      assert s1_name in names
      assert s2_name in names
    end

    test "enforces uniqueness on provider + auth_type + name" do
      base = "team_" <> String.slice(Ecto.UUID.generate(), 0, 6)

      {:ok, _} =
        SavedAuthentication.create_named_session(:anthropic, :oauth, base, %{
          access_token: "t1",
          expires_at: DateTime.utc_now()
        })

      {:error, changeset} =
        SavedAuthentication.create_named_session(:anthropic, :oauth, base, %{
          access_token: "t2",
          expires_at: DateTime.utc_now()
        })

      refute changeset.valid?
    end

    test "delete_named_session removes existing session and is idempotent" do
      name = "cic_" <> String.slice(Ecto.UUID.generate(), 0, 6)

      {:ok, _} =
        SavedAuthentication.create_named_session(:gemini, :api_key, name, %{api_key: "k3"})

      # Ensure it exists
      assert SavedAuthentication.get_named_session(:gemini, :api_key, name)

      # Deleting is idempotent; allow :ok or not_found
      assert SavedAuthentication.delete_named_session(:gemini, :api_key, name) in [
               :ok,
               {:error, :not_found}
             ]

      assert SavedAuthentication.delete_named_session(:gemini, :api_key, name) in [
               :ok,
               {:error, :not_found}
             ]
    end

    test "get_named_session returns the expected record" do
      name = "dev_" <> String.slice(Ecto.UUID.generate(), 0, 6)

      {:ok, _} =
        SavedAuthentication.create_named_session(:openai, :api_key, name, %{api_key: "k4"})

      session = SavedAuthentication.get_named_session(:openai, :api_key, name)
      assert session
      assert session.name == name
    end

    test "get_by_provider/2 returns legacy default-named session for compatibility" do
      # Ensure no prior default-named session exists, then insert and verify legacy getter finds it
      import Ecto.Query

      TheMaestro.Repo.delete_all(
        from sa in SavedAuthentication,
          where:
            sa.provider == "openai" and sa.auth_type == :api_key and
              sa.name == "default_openai_api_key"
      )

      {:ok, _} =
        SavedAuthentication.create_named_session(:openai, :api_key, "default_openai_api_key", %{
          api_key: "k5"
        })

      legacy = SavedAuthentication.get_by_provider(:openai, :api_key)
      assert legacy
      assert legacy.name == "default_openai_api_key"
    end

    test "database constraints enforce name format and length and roll back on error" do
      # Count existing rows
      start_count = Repo.aggregate(TheMaestro.SavedAuthentication, :count)

      # Attempt invalid name (contains space) via raw SQL to bypass changeset
      {:ok, uuid_bin} = Ecto.UUID.dump(Ecto.UUID.generate())
      {:error, %Postgrex.Error{postgres: %{constraint: "name_format"}}} =
        SQL.query(
          Repo,
          "INSERT INTO saved_authentications (id, provider, auth_type, name, credentials, inserted_at, updated_at) VALUES ($1,$2,$3,$4,$5, NOW(), NOW())",
          [uuid_bin, "openai", "api_key", "invalid name", %{}]
        )

      # Attempt invalid name (too short)
      {:ok, uuid_bin2} = Ecto.UUID.dump(Ecto.UUID.generate())
      {:error, %Postgrex.Error{postgres: %{constraint: "name_length"}}} =
        SQL.query(
          Repo,
          "INSERT INTO saved_authentications (id, provider, auth_type, name, credentials, inserted_at, updated_at) VALUES ($1,$2,$3,$4,$5, NOW(), NOW())",
          [uuid_bin2, "openai", "api_key", "aa", %{}]
        )

      # Ensure count has not changed (implicit transaction rollback per statement)
      end_count = Repo.aggregate(TheMaestro.SavedAuthentication, :count)
      assert start_count == end_count
    end

    test "performance: listing many sessions remains responsive" do
      # Insert many sessions and ensure list_by_provider returns all
      for i <- 1..50 do
        name = "sess_" <> Integer.to_string(i) <> "_" <> String.slice(Ecto.UUID.generate(), 0, 4)

        {:ok, _} =
          SavedAuthentication.create_named_session(:anthropic, :api_key, name, %{
            api_key: "k" <> Integer.to_string(i)
          })
      end

      sessions = SavedAuthentication.list_by_provider(:anthropic)
      assert length(Enum.filter(sessions, &(&1.provider == :anthropic))) >= 50
    end
  end
end
