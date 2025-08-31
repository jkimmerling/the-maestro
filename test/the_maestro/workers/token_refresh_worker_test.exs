defmodule TheMaestro.Workers.TokenRefreshWorkerTest do
  use ExUnit.Case, async: true
  use TheMaestro.DataCase
  use Oban.Testing, repo: TheMaestro.Repo

  alias Oban.Job
  alias TheMaestro.Auth.OAuthToken
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Workers.TokenRefreshWorker

  setup do
    # Ensure no leftover req_request_fun between tests
    on_exit(fn -> Application.delete_env(:the_maestro, :req_request_fun) end)
    :ok
  end

  describe "perform/1" do
    setup do
      # Clean up any existing saved authentications
      Repo.delete_all(SavedAuthentication)
      :ok
    end

    test "successfully performs token refresh for valid OAuth token" do
      # Create valid OAuth token in database
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, saved_auth} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(%{
          provider: :anthropic,
          auth_type: :oauth,
          name: "test_session",
          credentials: %{
            "access_token" => "sk-ant-oat01-old-token",
            "refresh_token" => "sk-ant-oar01-refresh-token",
            "token_type" => "Bearer"
          },
          expires_at: expires_at
        })
        |> Repo.insert()

      # Inject Req request function for successful token refresh
      Application.put_env(:the_maestro, :req_request_fun, fn _req, opts ->
        assert Keyword.get(opts, :method) == :post
        assert Keyword.get(opts, :url) == "https://auth.anthropic.com/oauth/token"
        body = Keyword.get(opts, :json)
        assert body["grant_type"] == "refresh_token"
        assert body["refresh_token"] == "sk-ant-oar01-refresh-token"

        {:ok,
         %Req.Response{
           status: 200,
           body:
             %{
               "access_token" => "sk-ant-oat01-new-token",
               "refresh_token" => "sk-ant-oar01-new-refresh",
               "expires_in" => 3600,
               "token_type" => "Bearer",
               "scope" => "user:profile user:inference"
             }
         }}
      end)

      # Create and execute Oban job
      job = %Job{
        args: %{
          "provider" => "anthropic",
          "auth_id" => to_string(saved_auth.id),
          "retry_count" => 0
        }
      }

      assert :ok = TokenRefreshWorker.perform(job)

      # Verify database was updated with new token
      updated_auth = Repo.get!(SavedAuthentication, saved_auth.id)
      assert updated_auth.credentials["access_token"] == "sk-ant-oat01-new-token"
      assert updated_auth.credentials["refresh_token"] == "sk-ant-oar01-new-refresh"
    end

    test "returns error when OAuth token not found" do
      job = %Job{
        args: %{
          "provider" => "anthropic",
          "auth_id" => "nonexistent-id",
          "retry_count" => 0
        }
      }

      assert {:error, :not_found} = TokenRefreshWorker.perform(job)
    end

    test "handles network errors gracefully" do
      # Create valid OAuth token in database
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, saved_auth} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(%{
          provider: :anthropic,
          auth_type: :oauth,
          name: "test_session",
          credentials: %{
            "access_token" => "sk-ant-oat01-test",
            "refresh_token" => "sk-ant-oar01-test",
            "token_type" => "Bearer"
          },
          expires_at: expires_at
        })
        |> Repo.insert()

      # Inject Req request function to return network error
      Application.put_env(:the_maestro, :req_request_fun, fn _req, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      job = %Job{
        args: %{
          "provider" => "anthropic",
          "auth_id" => to_string(saved_auth.id),
          "retry_count" => 0
        }
      }

      assert {:error, :network_error} = TokenRefreshWorker.perform(job)
    end

    test "handles invalid refresh token response" do
      # Create OAuth token with invalid refresh token
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, saved_auth} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(%{
          provider: :anthropic,
          auth_type: :oauth,
          name: "test_session",
          credentials: %{
            "access_token" => "sk-ant-oat01-test",
            "refresh_token" => "sk-ant-oar01-invalid",
            "token_type" => "Bearer"
          },
          expires_at: expires_at
        })
        |> Repo.insert()

      # Inject Req request function to return 401 (invalid refresh token)
      Application.put_env(:the_maestro, :req_request_fun, fn _req, _opts ->
        {:ok, %Req.Response{status: 401, body: %{"error" => "invalid_grant"}}}
      end)

      job = %Job{
        args: %{
          "provider" => "anthropic",
          "auth_id" => to_string(saved_auth.id),
          "retry_count" => 0
        }
      }

      assert {:error, :invalid_refresh_token} = TokenRefreshWorker.perform(job)
    end

    test "handles missing client_id configuration" do
      # Temporarily remove client_id from config
      original_config = Application.get_env(:the_maestro, :anthropic_oauth_client_id)
      Application.delete_env(:the_maestro, :anthropic_oauth_client_id)

      # Create valid OAuth token in database
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, saved_auth} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(%{
          provider: :anthropic,
          auth_type: :oauth,
          name: "test_session",
          credentials: %{
            "access_token" => "sk-ant-oat01-test",
            "refresh_token" => "sk-ant-oar01-test",
            "token_type" => "Bearer"
          },
          expires_at: expires_at
        })
        |> Repo.insert()

      job = %Job{
        args: %{
          "provider" => "anthropic",
          "auth_id" => to_string(saved_auth.id),
          "retry_count" => 0
        }
      }

      assert {:error, :missing_client_id} = TokenRefreshWorker.perform(job)

      # Restore config
      if original_config do
        Application.put_env(:the_maestro, :anthropic_oauth_client_id, original_config)
      end
    end

    test "validates job arguments properly" do
      # Test missing provider
      job = %Job{args: %{"auth_id" => "test", "retry_count" => 0}}
      assert {:error, :missing_required_field} = TokenRefreshWorker.perform(job)

      # Test missing auth_id
      job = %Job{args: %{"provider" => "anthropic", "retry_count" => 0}}
      assert {:error, :missing_required_field} = TokenRefreshWorker.perform(job)

      # Test invalid field types
      job = %Job{args: %{"provider" => 123, "auth_id" => "test", "retry_count" => 0}}
      assert {:error, :invalid_field_type} = TokenRefreshWorker.perform(job)
    end
  end

  describe "schedule_refresh_job/2" do
    test "schedules refresh job with correct timing" do
      provider = "anthropic"
      # 1 hour from now
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      result = TokenRefreshWorker.schedule_refresh_job(provider, expires_at)
      {:ok, job} = result

      assert %Oban.Job{} = job
      assert job.args["provider"] == provider
      # Placeholder from current implementation
      assert job.args["auth_id"] == "temp_auth_id"
      assert job.args["retry_count"] == 0

      # Should be scheduled at 80% of token lifetime (48 minutes from now)
      # 20% of 3600 = 720 seconds
      expected_schedule_time = DateTime.add(expires_at, -720, :second)

      # Allow 5 second tolerance for test timing
      time_diff = DateTime.diff(job.scheduled_at, expected_schedule_time, :second)
      assert abs(time_diff) <= 5
    end

    test "respects minimum refresh time of 5 minutes" do
      provider = "anthropic"
      # Token expires in 10 minutes
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      {:ok, job} = TokenRefreshWorker.schedule_refresh_job(provider, expires_at)

      # Should be scheduled 5 minutes before expiry (minimum), not 80% (2 minutes)
      # 5 minutes before
      expected_schedule_time = DateTime.add(expires_at, -300, :second)

      time_diff = DateTime.diff(job.scheduled_at, expected_schedule_time, :second)
      assert abs(time_diff) <= 5
    end

    test "limits scheduling to maximum 24 hours in advance" do
      provider = "anthropic"
      # Token expires in 48 hours
      expires_at = DateTime.add(DateTime.utc_now(), 48 * 3600, :second)

      {:ok, job} = TokenRefreshWorker.schedule_refresh_job(provider, expires_at)

      # Should be scheduled maximum 24 hours from now, not 38.4 hours (80% of 48)
      max_schedule_time = DateTime.add(DateTime.utc_now(), 24 * 3600, :second)

      # Job should be scheduled at or before the 24-hour limit
      assert DateTime.compare(job.scheduled_at, max_schedule_time) in [:lt, :eq]
    end
  end

  describe "refresh_token_for_provider/2" do
    setup do
      Repo.delete_all(SavedAuthentication)
      # Setup test client_id
      Application.put_env(:the_maestro, :anthropic_oauth_client_id, "test-client-id")
      :ok
    end

    test "successfully refreshes token and updates database" do
      # Create OAuth token in database
      expires_at = DateTime.add(DateTime.utc_now(), 1800, :second)

      {:ok, saved_auth} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(%{
          provider: :anthropic,
          auth_type: :oauth,
          name: "test_session",
          credentials: %{
            "access_token" => "sk-ant-oat01-current",
            "refresh_token" => "sk-ant-oar01-current",
            "token_type" => "Bearer"
          },
          expires_at: expires_at
        })
        |> Repo.insert()

      # Mock successful HTTPoison response
      expect(HTTPoisonMock, :post, fn
        "https://auth.anthropic.com/oauth/token", body, _ ->
          decoded = Jason.decode!(body)
          assert decoded["refresh_token"] == "sk-ant-oar01-current"

          {:ok,
           %HTTPoison.Response{
             status_code: 200,
             body:
               Jason.encode!(%{
                 "access_token" => "sk-ant-oat01-refreshed",
                 "refresh_token" => "sk-ant-oar01-refreshed",
                 "expires_in" => 7200,
                 "token_type" => "Bearer"
               })
           }}
      end)

      assert {:ok, %OAuthToken{} = oauth_token} =
               TokenRefreshWorker.refresh_token_for_provider(
                 "anthropic",
                 to_string(saved_auth.id)
               )

      assert oauth_token.access_token == "sk-ant-oat01-refreshed"
      assert oauth_token.refresh_token == "sk-ant-oar01-refreshed"

      # Verify database was updated
      updated_auth = Repo.get!(SavedAuthentication, saved_auth.id)
      assert updated_auth.credentials["access_token"] == "sk-ant-oat01-refreshed"
      assert updated_auth.credentials["refresh_token"] == "sk-ant-oar01-refreshed"
    end

    test "returns error when no OAuth token exists" do
      assert {:error, :not_found} =
               TokenRefreshWorker.refresh_token_for_provider("anthropic", "nonexistent")
    end

    test "returns error when refresh token is missing" do
      # Create OAuth token without refresh token
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, saved_auth} =
        %SavedAuthentication{}
        |> SavedAuthentication.changeset(%{
          provider: :anthropic,
          auth_type: :oauth,
          name: "test_session",
          credentials: %{
            "access_token" => "sk-ant-oat01-no-refresh",
            "token_type" => "Bearer"
            # No refresh_token field
          },
          expires_at: expires_at
        })
        |> Repo.insert()

      assert {:error, :no_refresh_token} =
               TokenRefreshWorker.refresh_token_for_provider(
                 "anthropic",
                 to_string(saved_auth.id)
               )
    end

    test "handles unsupported provider" do
      assert {:error, {:unsupported_provider, "unsupported"}} =
               TokenRefreshWorker.refresh_token_for_provider("unsupported", "test-id")
    end
  end
end
