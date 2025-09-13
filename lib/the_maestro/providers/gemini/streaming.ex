# credo:disable-for-this-file
defmodule TheMaestro.Providers.Gemini.Streaming do
  @moduledoc """
  Gemini streaming provider implementation.

  Uses Req + SSE adapter to stream responses from the Gemini API via
  `/v1beta/models/{model}:streamGenerateContent`.
  """

  @behaviour TheMaestro.Providers.Behaviours.Streaming
  require Logger

  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.Providers.Http.StreamingAdapter
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Types

  @impl true
  @spec stream_chat(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_chat(session_id, messages, opts \\ []) do
    Logger.debug("Gemini.Streaming.stream_chat/3 called")

    with true <- (is_list(messages) and messages != []) or {:error, :empty_messages},
         {:ok, auth_type} <- detect_auth_type(session_id),
         {:ok, req} <- ReqClientFactory.create_client(:gemini, auth_type, session: session_id) do
      model = Keyword.get(opts, :model)

      cond do
        is_nil(model) or model == "" ->
          {:error, :missing_model}

        auth_type == :api_key ->
          # API key flow uses public Generative Language API
          model_path = normalize_model_for_api(model, :genlang)

          payload = %{
            "model" => model_path,
            "contents" => ensure_gemini_contents(messages),
            "stream" => true
          }

          StreamingAdapter.stream_request(
            req,
            method: :post,
            url: "/v1beta/#{model_path}:streamGenerateContent",
            json: payload
          )

        auth_type == :oauth ->
          # Personal OAuth flow must mimic gemini-cli and use Cloud Code endpoint
          # https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse
          session_uuid = Ecto.UUID.generate()

          # Preflight token validity (handles revoked tokens that are not yet past expires_at)
          :ok = preflight_refresh_if_needed(session_id)

          case TheMaestro.Providers.Gemini.CodeAssist.ensure_project(session_id) do
            {:ok, project} when is_binary(project) and project != "" ->
              Logger.debug("Gemini OAuth project resolved: #{inspect(project)}")
              # Coerce model to a known-valid Cloud Code model
              m0 = strip_models_prefix(model)
              m = if m0 == "gemini-2.5-pro", do: m0, else: "gemini-2.5-pro"

              {contents, sys_inst} = split_system_instruction(ensure_gemini_contents(messages))

              request =
                %{
                  "contents" => contents,
                  # Keep minimal generation config; align with our default zero temperature
                  "generationConfig" => %{
                    "temperature" => 0,
                    "topP" => 1
                  },
                  "session_id" => session_uuid
                }
                |> maybe_put_system_instruction(sys_inst)
                |> maybe_put_tools(function_declarations())

              payload = %{
                "model" => m,
                "project" => project,
                "user_prompt_id" => session_uuid,
                "request" => request
              }

              req = maybe_http_debug(req, payload)

              StreamingAdapter.stream_request(
                req,
                method: :post,
                url:
                  "https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse",
                json: payload,
                timeout: Keyword.get(opts, :timeout, :infinity)
              )

            {:error, :project_required} ->
              {:error, :project_required}

            _ ->
              {:error, :missing_user_project}
          end
      end
    end
  end

  # Attempt a very cheap GET to validate the bearer token. If it returns 401,
  # force a refresh and continue. Errors are ignored so we don't block streaming.
  defp preflight_refresh_if_needed(session_name) do
    with {:ok, req} <- ReqClientFactory.create_client(:gemini, :oauth, session: session_name) do
      case Req.request(req,
             method: :get,
             url: "https://cloudcode-pa.googleapis.com/v1internal:getCodeAssistGlobalUserSetting"
           ) do
        {:ok, %Req.Response{status: 401}} ->
          _ = TheMaestro.Providers.Gemini.OAuth.refresh_tokens(session_name)
          :ok

        _ ->
          :ok
      end
    else
      _ -> :ok
    end
  end

  @doc """
  Stream a follow-up turn that supplies tool results back to Gemini via Cloud Code.

  Expects `contents` to be a list of Gemini content maps (role + parts), typically:
  [
    %{role: "user", parts: [%{"text" => last_user_text}]},
    %{role: "tool", parts: [%{"functionResponse" => %{name: name, id: id, response: map}}, ...]}
  ]
  """
  @spec stream_tool_followup(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_tool_followup(session_id, contents, opts \\ []) when is_list(contents) do
    with {:ok, :oauth} <- detect_auth_type(session_id),
         {:ok, req} <- ReqClientFactory.create_client(:gemini, :oauth, session: session_id) do
      model = Keyword.get(opts, :model) || "gemini-2.5-pro"
      session_uuid = Ecto.UUID.generate()

      case TheMaestro.Providers.Gemini.CodeAssist.ensure_project(session_id) do
        {:ok, project} when is_binary(project) and project != "" ->
          m0 = strip_models_prefix(model)
          m = if m0 == "gemini-2.5-pro", do: m0, else: "gemini-2.5-pro"

          request =
            %{
              "contents" => contents,
              "generationConfig" => %{"temperature" => 0, "topP" => 1},
              "session_id" => session_uuid
            }
            |> maybe_put_tools(function_declarations())

          payload = %{
            "model" => m,
            "project" => project,
            "user_prompt_id" => session_uuid,
            "request" => request
          }

          req = maybe_http_debug(req, payload)

          StreamingAdapter.stream_request(
            req,
            method: :post,
            url: "https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse",
            json: payload,
            timeout: Keyword.get(opts, :timeout, :infinity)
          )

        {:error, :project_required} ->
          {:error, :project_required}

        _ ->
          {:error, :missing_user_project}
      end
    else
      {:ok, :api_key} -> {:error, :tool_followup_not_supported_for_api_key}
      other -> other
    end
  end

  # -- Tools exposure for Gemini --
  # Advertise a minimal set of function declarations so the model can emit
  # functionCall parts. We keep our internal tools generic and translate at the provider layer.
  defp function_declarations do
    [
      %{
        "name" => "run_shell_command",
        "description" =>
          "Execute a shell command. Use for tasks like listing files (e.g., ls -la).",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "command" => %{"type" => "string"},
            "directory" => %{"type" => "string"}
          },
          "required" => ["command"]
        }
      },
      %{
        "name" => "list_directory",
        "description" => "List files and folders for a given path.",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{"type" => "string"},
            "ignore" => %{"type" => "array", "items" => %{"type" => "string"}},
            "respect_git_ignore" => %{"type" => "boolean"}
          },
          "required" => ["path"]
        }
      }
    ]
  end

  defp maybe_put_tools(req_map, decls) when is_list(decls) do
    Map.put(req_map, "tools", [
      %{
        # Include both naming variants to satisfy different backends
        "function_declarations" => decls,
        "functionDeclarations" => decls
      }
    ])
  end

  @impl true
  @spec parse_stream_event(map(), map()) :: {[map()], map()}
  def parse_stream_event(_event, state) do
    # Parsing is centrally handled by TheMaestro.Streaming + GeminiHandler
    {[], state}
  end

  @spec detect_auth_type(String.t()) :: {:ok, :oauth | :api_key} | {:error, term()}
  defp detect_auth_type(session_id) do
    cond do
      is_map(SavedAuthentication.get_by_provider_and_name(:gemini, :oauth, session_id)) ->
        {:ok, :oauth}

      is_map(SavedAuthentication.get_by_provider_and_name(:gemini, :api_key, session_id)) ->
        {:ok, :api_key}

      true ->
        {:error, :session_not_found}
    end
  end

  @doc false
  @spec normalize_messages([map()]) :: [map()]
  defp normalize_messages(messages) do
    Enum.map(messages, &normalize_one/1)
  end

  defp ensure_gemini_contents(messages) do
    cond do
      is_list(messages) and Enum.any?(messages, &is_map/1) and
          Enum.all?(messages, fn m -> is_map(m) and Map.has_key?(m, "parts") end) ->
        messages

      true ->
        normalize_messages(messages)
    end
  end

  defp normalize_one(msg) do
    role = Map.get(msg, "role") || Map.get(msg, :role) || "user"
    content = Map.get(msg, "content") || Map.get(msg, :content) || ""

    %{
      "role" => role,
      "parts" =>
        case content do
          s when is_binary(s) -> [%{"text" => s}]
          %{"text" => _} = part -> [part]
          %{} = part -> [part]
          _ -> []
        end
    }
  end

  # Extract first "system" message as systemInstruction and remove it from contents
  defp split_system_instruction(messages) do
    msgs =
      if is_list(messages) and Enum.all?(messages, &is_map/1) and
           Enum.any?(messages, &Map.has_key?(&1, "parts")) do
        messages
      else
        normalize_messages(messages)
      end

    {sys_msgs, rest} = Enum.split_with(msgs, fn m -> m["role"] == "system" end)

    sys_text =
      sys_msgs
      |> Enum.flat_map(fn m -> m["parts"] || [] end)
      |> Enum.map(fn p -> p["text"] || "" end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    sys_inst =
      case String.trim(sys_text) do
        "" -> nil
        txt -> %{"role" => "user", "parts" => [%{"text" => txt}]}
      end

    {rest, sys_inst}
  end

  defp maybe_put_system_instruction(map, nil), do: map

  defp maybe_put_system_instruction(map, sys_inst),
    do: Map.put(map, "systemInstruction", sys_inst)

  defp normalize_model_for_api(model, :genlang) do
    model = to_string(model)

    if String.starts_with?(model, "models/") do
      model
    else
      "models/" <> model
    end
  end

  defp strip_models_prefix(model) do
    model = to_string(model)
    String.replace_prefix(model, "models/", "")
  end

  # removed unused ensure_project_via_cloud_code/1 helper after refactor

  defp maybe_http_debug(req, payload) do
    if System.get_env("HTTP_DEBUG") in ["1", "true", "TRUE"] do
      body = Jason.encode!(payload)
      model = payload["model"]
      proj = payload["project"]
      has_sys = !!get_in(payload, ["request", "systemInstruction"])

      IO.puts("\n[GEMINI OAuth] POST /v1internal:streamGenerateContent?alt=sse")
      IO.puts("Headers: authorization=Bearer <redacted>, x-goog-api-client set")

      IO.puts(
        "Model: #{inspect(model)}  Project: #{inspect(proj)}  systemInstruction?: #{has_sys}"
      )

      IO.puts("Body: \n" <> body <> "\n")
    end

    req
  end
end
