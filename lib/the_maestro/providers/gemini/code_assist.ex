# credo:disable-for-this-file
defmodule TheMaestro.Providers.Gemini.CodeAssist do
  @moduledoc """
  Minimal Cloud Code (Gemini Code Assist) client to discover the project ID
  used by the official gemini-cli for personal OAuth.

  Flow mirrors gemini-cli/packages/core/src/code_assist/setup.ts:
  - POST v1internal:loadCodeAssist to discover current tier and project
  - If needed, POST v1internal:onboardUser (poll) to provision default project
  - Persist discovered project in SavedAuthentication credentials as "user_project"
  """

  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.SavedAuthentication

  @cloud_code_base "https://cloudcode-pa.googleapis.com"

  @spec ensure_project(String.t()) :: {:ok, String.t()} | {:error, term()}
  def ensure_project(session_name) when is_binary(session_name) do
    case current_saved_project(session_name) do
      {:ok, proj} -> {:ok, proj}
      _ -> discover_and_persist_project(session_name)
    end
  end

  defp current_saved_project(session_name) do
    case SavedAuthentication.get_by_provider_and_name(:gemini, :oauth, session_name) do
      %SavedAuthentication{credentials: %{"user_project" => p}} when is_binary(p) and p != "" ->
        {:ok, p}

      _ ->
        case System.get_env("GEMINI_USER_PROJECT") || System.get_env("GOOGLE_CLOUD_PROJECT") do
          p when is_binary(p) and p != "" -> {:ok, p}
          _ -> {:error, :not_found}
        end
    end
  end

  defp discover_and_persist_project(session_name) do
    with {:ok, req} <- ReqClientFactory.create_client(:gemini, :oauth, session: session_name) do
      case discover_project_via_cloud_code(req) do
        {:ok, proj} ->
          _ = persist_project(session_name, proj)
          {:ok, proj}

        {:error, {:http_error, 401, _body}} ->
          # Access token likely expired or revoked; attempt a single refresh and retry
          _ = TheMaestro.Providers.Gemini.OAuth.refresh_tokens(session_name)

          with {:ok, req2} <-
                 ReqClientFactory.create_client(:gemini, :oauth, session: session_name) do
            case discover_project_via_cloud_code(req2) do
              {:ok, proj} ->
                _ = persist_project(session_name, proj)
                {:ok, proj}

              other ->
                other
            end
          else
            other -> other
          end

        other ->
          other
      end
    end
  end

  defp discover_project_via_cloud_code(req) do
    project_env = System.get_env("GEMINI_USER_PROJECT") || System.get_env("GOOGLE_CLOUD_PROJECT")

    body = %{
      "cloudaicompanionProject" => project_env,
      "metadata" => %{
        "ideType" => "IDE_UNSPECIFIED",
        "platform" => "PLATFORM_UNSPECIFIED",
        "pluginType" => "GEMINI",
        "duetProject" => project_env
      }
    }

    case Req.request(req,
           method: :post,
           url: @cloud_code_base <> "/v1internal:loadCodeAssist",
           json: body
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        decoded = if is_binary(body), do: Jason.decode!(body), else: body

        case decoded do
          %{"cloudaicompanionProject" => proj} when is_binary(proj) and proj != "" ->
            {:ok, proj}

          %{"currentTier" => _tier} ->
            # Non-free tier: try to auto-select a project if none set in env
            cond do
              is_binary(project_env) and project_env != "" -> {:ok, project_env}
              true -> auto_select_and_set_project(req)
            end

          %{"allowedTiers" => allowed} when is_list(allowed) ->
            tier_id = default_tier_id(allowed)
            # FREE uses managed project; paid tiers need a real project. If env not set,
            # try automatic discovery to satisfy the required feature (no manual env).
            if tier_id == "FREE" do
              onboard_for_tier_poll(req, tier_id, nil)
            else
              case (project_env && project_env != "" && project_env) ||
                     auto_select_and_set_project(req) do
                {:ok, proj} ->
                  onboard_for_tier_poll(req, tier_id, proj)

                proj when is_binary(proj) and proj != "" ->
                  onboard_for_tier_poll(req, tier_id, proj)

                _ ->
                  {:error, :project_required}
              end
            end

          _ ->
            {:error, :unexpected_response}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, safe_body(body)}}

      {:error, reason} ->
        {:error, {:request_error, reason}}
    end
  end

  defp default_tier_id(allowed) do
    case Enum.find(allowed, &match?(%{"isDefault" => true}, &1)) do
      %{"id" => id} -> id
      _ -> "FREE"
    end
  end

  defp onboard_for_tier_poll(req, tier_id, project_env) do
    # Build request payload per gemini-cli behavior
    base_body = %{
      "tierId" => tier_id,
      "metadata" => %{
        "ideType" => "IDE_UNSPECIFIED",
        "platform" => "PLATFORM_UNSPECIFIED",
        "pluginType" => "GEMINI"
      }
    }

    body =
      if tier_id == "FREE" do
        Map.put(base_body, "cloudaicompanionProject", nil)
      else
        base_body
        |> Map.put("cloudaicompanionProject", project_env)
        |> put_in(["metadata", "duetProject"], project_env)
      end

    # Poll until the long-running operation completes, like gemini-cli
    max_attempts = String.to_integer(System.get_env("GEMINI_CA_ONBOARD_ATTEMPTS") || "10")
    delay_ms = String.to_integer(System.get_env("GEMINI_CA_ONBOARD_DELAY_MS") || "2000")

    Enum.reduce_while(1..max_attempts, {:error, :lro_incomplete}, fn _attempt, _acc ->
      case Req.request(req,
             method: :post,
             url: @cloud_code_base <> "/v1internal:onboardUser",
             json: body
           ) do
        {:ok, %Req.Response{status: 200, body: b}} ->
          case parse_onboard_lro(b) do
            {:ok, proj} ->
              {:halt, {:ok, proj}}

            {:error, :lro_incomplete} ->
              Process.sleep(delay_ms)
              {:cont, {:error, :lro_incomplete}}

            {:error, other} ->
              {:halt, {:error, other}}
          end

        {:ok, %Req.Response{status: status, body: b}} ->
          {:halt, {:error, {:http_error, status, safe_body(b)}}}

        {:error, reason} ->
          {:halt, {:error, {:request_error, reason}}}
      end
    end)
  end

  defp parse_onboard_lro(body) when is_binary(body),
    do: body |> Jason.decode!() |> parse_onboard_lro()

  defp parse_onboard_lro(%{
         "done" => true,
         "response" => %{"cloudaicompanionProject" => %{"id" => id}}
       })
       when is_binary(id) and id != "" do
    {:ok, id}
  end

  defp parse_onboard_lro(%{"done" => false}), do: {:error, :lro_incomplete}
  defp parse_onboard_lro(_), do: {:error, :unexpected_response}

  defp persist_project(session_name, project) do
    saved = SavedAuthentication.get_by_provider_and_name(:gemini, :oauth, session_name)

    if match?(%SavedAuthentication{}, saved) do
      %SavedAuthentication{credentials: creds, expires_at: exp} = saved
      new_creds = Map.put(creds, "user_project", project)

      _ =
        SavedAuthentication.upsert_named_session(:gemini, :oauth, session_name, %{
          credentials: new_creds,
          expires_at: exp
        })
    end

    :ok
  end

  # ===== Automatic project selection for non-free tiers =====
  # Try to get a preferred project without user env:
  # 1) Read Code Assist global user setting
  # 2) Otherwise, list active GCP projects via Cloud Resource Manager and pick the first
  # 3) Set Code Assist global user setting for future requests
  # Returns {:ok, project_id} or {:error, :project_required}
  defp auto_select_and_set_project(req) do
    with {:ok, proj} <- get_global_user_project(req) do
      {:ok, proj}
    else
      _ ->
        case list_active_projects(req) do
          {:ok, [proj | _]} ->
            _ = set_global_user_project(req, proj)
            {:ok, proj}

          _ ->
            {:error, :project_required}
        end
    end
  end

  defp get_global_user_project(req) do
    case Req.request(req,
           method: :get,
           url: @cloud_code_base <> "/v1internal:getCodeAssistGlobalUserSetting"
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        decoded = if is_binary(body), do: Jason.decode!(body), else: body

        case decoded do
          %{"cloudaicompanionProject" => proj} when is_binary(proj) and proj != "" ->
            {:ok, proj}

          _ ->
            {:error, :not_set}
        end

      _ ->
        {:error, :not_set}
    end
  end

  defp set_global_user_project(req, project_id) when is_binary(project_id) do
    body = %{"cloudaicompanionProject" => project_id, "freeTierDataCollectionOptin" => false}

    case Req.request(req,
           method: :post,
           url: @cloud_code_base <> "/v1internal:setCodeAssistGlobalUserSetting",
           json: body
         ) do
      {:ok, %Req.Response{status: 200}} -> :ok
      _ -> :ok
    end
  end

  defp list_active_projects(req) do
    base = "https://cloudresourcemanager.googleapis.com/v3/projects"

    collect = fn page_token, acc ->
      params =
        [stateFilter: "ACTIVE", pageSize: 200]
        |> then(fn p -> if page_token, do: [{:pageToken, page_token} | p], else: p end)

      case Req.request(req, method: :get, url: base, params: params) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          decoded = if is_binary(body), do: Jason.decode!(body), else: body

          projects =
            (decoded["projects"] || [])
            |> Enum.map(fn p -> p["projectId"] || p["name"] end)
            |> Enum.filter(&is_binary/1)

          next = decoded["nextPageToken"]
          {:ok, {next, acc ++ projects}}

        {:ok, %Req.Response{status: _}} ->
          {:error, acc}

        {:error, _} ->
          {:error, acc}
      end
    end

    # Iterate up to 5 pages defensively
    result =
      Enum.reduce_while(1..5, {:ok, {nil, []}}, fn _i, {:ok, {token, acc}} ->
        case collect.(token, acc) do
          {:ok, {nil, acc2}} -> {:halt, {:ok, acc2}}
          {:ok, {next, acc2}} -> {:cont, {:ok, {next, acc2}}}
          {:error, acc2} -> {:halt, {:ok, acc2}}
        end
      end)

    case result do
      {:ok, []} -> {:error, :none}
      {:ok, list} -> {:ok, list}
      _ -> {:error, :none}
    end
  end

  defp safe_body(body) when is_binary(body), do: body
  defp safe_body(%{} = body), do: Jason.encode!(body)
  defp safe_body(other), do: inspect(other)
end
