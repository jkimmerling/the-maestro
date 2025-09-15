defmodule TheMaestro.Providers.Gemini.Streaming do
  @moduledoc """
  Gemini streaming provider implementation.

  Uses Req + SSE adapter to stream responses from the Gemini API via
  `/v1beta/models/{model}:streamGenerateContent`.
  """

  @behaviour TheMaestro.Providers.Behaviours.Streaming
  require Logger

  alias TheMaestro.Conversations
  alias TheMaestro.MCP.Registry, as: MCPRegistry
  alias TheMaestro.Providers.Gemini.CodeAssist
  alias TheMaestro.Providers.Gemini.OAuth, as: GemOAuth
  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.Providers.Http.StreamingAdapter
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Types

  @dialyzer {:nowarn_function, resolve_decl_session_id: 2}
  @dialyzer {:nowarn_function, stream_chat: 3}
  @dialyzer :no_match

  @impl true
  @spec stream_chat(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_chat(session_name, messages, opts \\ []) do
    Logger.debug("Gemini.Streaming.stream_chat/3 called")

    with {:ok, ^messages} <- validate_messages(messages),
         {:ok, auth_type} <- detect_auth_type(session_name),
         {:ok, req} <- ReqClientFactory.create_client(:gemini, auth_type, session: session_name) do
      do_stream_chat(auth_type, req, session_name, messages, opts)
    end
  end

  defp validate_messages(messages) when is_list(messages) and messages != [], do: {:ok, messages}
  defp validate_messages(_), do: {:error, :empty_messages}

  defp do_stream_chat(:api_key, req, _session_name, messages, opts) do
    model = Keyword.get(opts, :model)
    if is_nil(model) or model == "" do
      {:error, :missing_model}
    else
      model_path = normalize_model_for_api(model, :genlang)
      payload = %{"model" => model_path, "contents" => ensure_gemini_contents(messages), "stream" => true}
      StreamingAdapter.stream_request(req, method: :post, url: "/v1beta/#{model_path}:streamGenerateContent", json: payload)
    end
  end

  defp do_stream_chat(:oauth, req, session_name, messages, opts) do
    model = Keyword.get(opts, :model)
    if is_nil(model) or model == "" do
      {:error, :missing_model}
    else
      session_uuid = Ecto.UUID.generate()
      :ok = preflight_refresh_if_needed(session_name)
      case CodeAssist.ensure_project(session_name) do
        {:ok, project} when is_binary(project) and project != "" ->
          stream_oauth_with_project(req, session_name, messages, opts, model, session_uuid, project)
        {:error, :project_required} -> {:error, :project_required}
        _ -> {:error, :missing_user_project}
      end
    end
  end

  defp stream_oauth_with_project(req, session_name, messages, opts, model, session_uuid, project) do
    Logger.debug("Gemini OAuth project resolved: #{inspect(project)}")
    m0 = strip_models_prefix(model)
    m = if m0 == "gemini-2.5-pro", do: m0, else: "gemini-2.5-pro"
    base_contents = ensure_gemini_contents(messages)
    env_msg = build_env_context_message(session_name)
    base_contents = [env_msg | base_contents]
    {contents, sys_inst} = split_system_instruction(base_contents)
    decl_session_id = Keyword.get(opts, :decl_session_id) || resolve_decl_session_id(session_name, :oauth)
    request = %{"contents" => contents, "generationConfig" => %{"temperature" => 0, "topP" => 1}, "session_id" => session_uuid}
    |> maybe_put_system_instruction(sys_inst)
    |> maybe_put_tools(function_declarations_for_session(decl_session_id))
    payload = %{"model" => m, "project" => project, "user_prompt_id" => session_uuid, "request" => request}
    req = maybe_http_debug(req, payload)
    StreamingAdapter.stream_request(req, method: :post, url: "https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse", json: payload, timeout: Keyword.get(opts, :timeout, :infinity))
  end

  # Attempt a very cheap GET to validate the bearer token. If it returns 401,
  # force a refresh and continue. Errors are ignored so we don't block streaming.
  defp preflight_refresh_if_needed(session_name) do
    case ReqClientFactory.create_client(:gemini, :oauth, session: session_name) do
      {:ok, req} ->
        case Req.request(req,
               method: :get,
               url: "https://cloudcode-pa.googleapis.com/v1internal:getCodeAssistGlobalUserSetting"
             ) do
          {:ok, %Req.Response{status: 401}} ->
            _ = GemOAuth.refresh_tokens(session_name)
            :ok

          _ ->
            :ok
        end

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
  def stream_tool_followup(session_name, contents, opts \\ []) when is_list(contents) do
    with {:ok, :oauth} <- detect_auth_type(session_name),
         {:ok, req} <- ReqClientFactory.create_client(:gemini, :oauth, session: session_name) do
      model = Keyword.get(opts, :model) || "gemini-2.5-pro"
      session_uuid = Ecto.UUID.generate()

      case CodeAssist.ensure_project(session_name) do
        {:ok, project} when is_binary(project) and project != "" ->
          m0 = strip_models_prefix(model)
          m = if m0 == "gemini-2.5-pro", do: m0, else: "gemini-2.5-pro"

          decl_session_id =
            Keyword.get(opts, :decl_session_id) || resolve_decl_session_id(session_name, :oauth)

          request =
            %{
              "contents" => contents,
              "generationConfig" => %{"temperature" => 0, "topP" => 1},
              "session_id" => session_uuid
            }
            |> maybe_put_tools(function_declarations_for_session(decl_session_id))

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
  # Merge built-ins with MCP-declared tools for this session.
  defp function_declarations_for_session(session_id) do
    mcp_tools = MCPRegistry.to_gemini_decls(session_id)
    builtins = built_in_function_declarations()
    # prefer MCP if name collides
    names = MapSet.new(Enum.map(mcp_tools, & &1["name"]))
    builtins_filtered = Enum.reject(builtins, fn d -> MapSet.member?(names, d["name"]) end)
    decls = mcp_tools ++ builtins_filtered

    Logger.debug(
      "[Gemini] Injected tools for session=#{session_id}: #{length(decls)} (mcp=#{length(mcp_tools)}, builtins=#{length(builtins_filtered)})"
    )

    decls
  end

  # Resolve the Conversations session UUID for use by MCP.Registry.
  # The first parameter to this module is actually the SavedAuthentication session name.
  defp resolve_decl_session_id(session_name, auth_type) when is_binary(session_name) do
    sa = SavedAuthentication.get_by_provider_and_name(:gemini, auth_type, session_name)

    case sa do
      %SavedAuthentication{} = found ->
        case Conversations.latest_session_for_auth_id(found.id) do
          %Conversations.Session{id: id} -> id
          _ -> session_name
        end

      _ ->
        # fall back; MCP.Registry will return [] and we’ll inject built-ins only
        session_name
    end
  end

  defp built_in_function_declarations do
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
    valid? = is_list(messages) and Enum.any?(messages, &is_map/1) and Enum.all?(messages, fn m -> is_map(m) and Map.has_key?(m, "parts") end)
    if valid?, do: messages, else: normalize_messages(messages)
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

  defp build_env_context_message(session_name) do
    # Resolve Conversations session id for cwd lookup
    session_id = resolve_decl_session_id(session_name, :oauth)
    cwd = safe_session_cwd(session_id)

    text = """
    <environment_context>
      <cwd>#{cwd}</cwd>
    </environment_context>
    """

    %{"role" => "user", "parts" => [%{"text" => String.trim(text)}]}
  end

  defp safe_session_cwd(session_id) do
    case Ecto.UUID.cast(session_id) do
      :error ->
        File.cwd!() |> Path.expand()

      {:ok, _} ->
        try do
          case Conversations.get_session_with_auth!(session_id) do
            %Conversations.Session{working_dir: wd} when is_binary(wd) and wd != "" ->
              Path.expand(wd)

            _ ->
              File.cwd!() |> Path.expand()
          end
        rescue
          _ -> File.cwd!() |> Path.expand()
        end
    end
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
