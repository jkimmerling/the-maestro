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
    with {:ok, req} <- ReqClientFactory.create_client(:gemini, :oauth, session: session_name),
         {:ok, proj} <- discover_project_via_cloud_code(req) do
      _ = persist_project(session_name, proj)
      {:ok, proj}
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
            # Tier set but project missing; require env project like gemini-cli
            if is_binary(project_env) and project_env != "" do
              {:ok, project_env}
            else
              {:error, :project_required}
            end

          %{"allowedTiers" => allowed} when is_list(allowed) ->
            tier_id = default_tier_id(allowed)
            onboard_for_tier(req, tier_id, project_env)

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

  defp onboard_for_tier(req, tier_id, project_env) do
    body =
      if tier_id == "FREE" do
        %{
          "tierId" => tier_id,
          "cloudaicompanionProject" => nil,
          "metadata" => %{
            "ideType" => "IDE_UNSPECIFIED",
            "platform" => "PLATFORM_UNSPECIFIED",
            "pluginType" => "GEMINI"
          }
        }
      else
        %{
          "tierId" => tier_id,
          "cloudaicompanionProject" => project_env,
          "metadata" => %{
            "ideType" => "IDE_UNSPECIFIED",
            "platform" => "PLATFORM_UNSPECIFIED",
            "pluginType" => "GEMINI",
            "duetProject" => project_env
          }
        }
      end

    with {:ok, %Req.Response{status: 200, body: body}} <-
           Req.request(req,
             method: :post,
             url: @cloud_code_base <> "/v1internal:onboardUser",
             json: body
           ),
         {:ok, proj} <- parse_onboard_lro(body) do
      {:ok, proj}
    else
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, safe_body(body)}}

      {:error, reason} ->
        {:error, {:request_error, reason}}

      other ->
        other
    end
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
    case SavedAuthentication.get_by_provider_and_name(:gemini, :oauth, session_name) do
      %SavedAuthentication{credentials: creds, expires_at: exp} ->
        new_creds = Map.put(creds || %{}, "user_project", project)

        _ =
          SavedAuthentication.upsert_named_session(:gemini, :oauth, session_name, %{
            credentials: new_creds,
            expires_at: exp
          })

        :ok

      _ ->
        :ok
    end
  end

  defp safe_body(body) when is_binary(body), do: body
  defp safe_body(%{} = body), do: Jason.encode!(body)
  defp safe_body(other), do: inspect(other)
end
