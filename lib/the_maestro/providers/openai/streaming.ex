defmodule TheMaestro.Providers.OpenAI.Streaming do
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc """
  OpenAI streaming provider with dual-endpoint support.

  - ChatGPT Personal (OAuth): https://chatgpt.com/backend-api/codex/responses
  - Enterprise/API Key (Responses): https://api.openai.com/v1/responses
  """

  @behaviour TheMaestro.Providers.Behaviours.Streaming

  require Logger
  alias TheMaestro.Conversations
  alias TheMaestro.MCP.Registry, as: MCPRegistry
  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.Providers.Http.StreamingAdapter
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Streaming.OpenAIHandler
  alias TheMaestro.SystemPrompts
  alias TheMaestro.SystemPrompts.Defaults, as: PromptDefaults
  alias TheMaestro.Types

  @dialyzer {:nowarn_function, resolve_decl_session_id: 1}
  @dialyzer {:nowarn_function, normalize_instructions_for_chatgpt: 1}

  @type mode :: :chatgpt_personal | :enterprise

  @spec stream_chat(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  @impl true
  def stream_chat(session_name, messages, opts \\ []) do
    with true <- (is_list(messages) and messages != []) or {:error, :empty_messages},
         {:ok, mode} <- detect_mode(session_name),
         {:ok, stream} <- do_stream(mode, session_name, messages, opts) do
      {:ok, stream}
    else
      {:error, _} = err -> err
    end
  end

  @doc """
  Stream a follow-up turn consisting of ResponseItems (e.g., function_call_output),
  mirroring Codex's second turn after executing tools.

  `items` must be a list of maps like:
    %{"type" => "function_call_output", "call_id" => call_id, "output" => json_string}
  """
  @spec stream_tool_followup(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_tool_followup(session_name, items, opts \\ []) when is_list(items) do
    model = Keyword.get(opts, :model) || "gpt-4o"
    adapter = Keyword.get(opts, :streaming_adapter, StreamingAdapter)

    case detect_mode(session_name) do
      {:ok, mode} ->
        case build_followup_request(mode, session_name, items, Keyword.put(opts, :model, model)) do
          {:ok, req, url, payload, timeout} ->
            adapter.stream_request(req, method: :post, url: url, json: payload, timeout: timeout)

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  # ===== Internal helpers =====

  @spec detect_mode(String.t()) :: {:ok, mode()} | {:error, term()}
  defp detect_mode(session_id) do
    cond do
      is_map(SavedAuthentication.get_by_provider_and_name(:openai, :api_key, session_id)) ->
        {:ok, :enterprise}

      is_map(SavedAuthentication.get_by_provider_and_name(:openai, :oauth, session_id)) ->
        {:ok, :chatgpt_personal}

      true ->
        {:error, :session_not_found}
    end
  end

  @spec do_stream(mode(), String.t(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  defp do_stream(:enterprise, session_name, messages, opts) do
    model = Keyword.get(opts, :model) || "gpt-4o"
    adapter = Keyword.get(opts, :streaming_adapter, StreamingAdapter)

    with {:ok, req0} <- ReqClientFactory.create_client(:openai, :api_key, session: session_name) do
      version = Application.spec(:the_maestro, :vsn) |> to_string()
      session_id_hdr = Keyword.get(opts, :session_uuid) || Ecto.UUID.generate()

      decl_session_id = Keyword.get(opts, :decl_session_id)
      instructions = resolve_instruction_items(decl_session_id)
      instructions = normalize_instructions_for_chatgpt(instructions)

      req =
        req0
        |> Req.Request.put_header("openai-beta", "responses=experimental")
        |> Req.Request.put_header("session_id", session_id_hdr)
        |> Req.Request.put_header("originator", "codex_cli_rs")
        |> Req.Request.put_header("accept", "text/event-stream")
        |> Req.Request.put_header("version", version)

      env_msg = build_env_context_message(session_name)
      input_items = [env_msg | itemize_messages_for_responses(messages)]

      payload = %{
        "model" => model,
        "instructions" => instructions,
        "input" => input_items,
        "tools" => tools_for_session(Keyword.get(opts, :decl_session_id) || session_name),
        "tool_choice" => "auto",
        "parallel_tool_calls" => true,
        "stream" => true,
        "prompt_cache_key" => session_id_hdr
      }

      adapter.stream_request(req,
        method: :post,
        url: "/v1/responses",
        json: payload,
        timeout: Keyword.get(opts, :timeout, :infinity)
      )
    end
  end

  defp do_stream(:chatgpt_personal, session_name, messages, opts) do
    model = Keyword.get(opts, :model) || "gpt-5"
    adapter = Keyword.get(opts, :streaming_adapter, StreamingAdapter)

    with %SavedAuthentication{credentials: creds} <-
           SavedAuthentication.get_by_provider_and_name(:openai, :oauth, session_name),
         {:ok, account_id} <- chatgpt_account_id_from_id_token(Map.get(creds, "id_token")),
         {:ok, req0} <- ReqClientFactory.create_client(:openai, :oauth, session: session_name) do
      # Headers required by ChatGPT backend for responses API
      session_id_hdr = Keyword.get(opts, :session_uuid) || Ecto.UUID.generate()

      decl_session_id = Keyword.get(opts, :decl_session_id)
      instructions = resolve_instruction_items(decl_session_id)
      instructions = normalize_instructions_for_chatgpt(instructions)

      req =
        req0
        |> Req.Request.put_header("openai-beta", "responses=experimental")
        |> Req.Request.put_header("user-agent", chatgpt_user_agent())
        |> Req.Request.put_header("content-type", "application/json")
        |> Req.Request.put_header("accept", "text/event-stream")
        |> Req.Request.put_header("session_id", session_id_hdr)
        |> Req.Request.put_header("originator", "codex_cli_rs")
        |> Req.Request.put_header("chatgpt-account-id", account_id)

      env_msg = build_env_context_message(session_name)
      input_items = [env_msg | itemize_messages_for_responses(messages)]

      payload = %{
        "model" => model,
        "instructions" => instructions,
        "input" => input_items,
        "tools" => tools_for_session(Keyword.get(opts, :decl_session_id) || session_name),
        "tool_choice" => "auto",
        "parallel_tool_calls" => false,
        "store" => false,
        "stream" => true,
        "prompt_cache_key" => session_id_hdr,
        "text" => %{"verbosity" => "medium"}
      }

      maybe_log_payload(:openai_oauth_initial, payload)

      adapter.stream_request(req,
        method: :post,
        url: "https://chatgpt.com/backend-api/codex/responses",
        json: payload,
        timeout: Keyword.get(opts, :timeout, :infinity)
      )
    else
      nil -> {:error, :session_not_found}
    end
  end

  # Removed unused do_followup_stream/4 (follow-up handled inline in stream_tool_followup/3)

  defp chatgpt_user_agent do
    # Align with test script default
    "TheMaestro/1.0 (Conversation Test)"
  end

  defp resolve_instruction_items(nil), do: fallback_instruction_items()

  defp resolve_instruction_items(session_id) when is_binary(session_id) do
    case SystemPrompts.resolve_for_session(session_id, :openai) do
      {:ok, resolved} ->
        instructions =
          SystemPrompts.render_for_provider(:openai, %{prompts: Map.get(resolved, :prompts, [])})

        if instructions == [] do
          Logger.warning(
            "openai instructions resolved empty for session #{session_id}; using defaults"
          )

          fallback_instruction_items()
        else
          instructions
        end
    end
  rescue
    exception ->
      Logger.error("openai instructions resolution raised #{inspect(exception)}")

      fallback_instruction_items()
  end

  defp resolve_instruction_items(_), do: fallback_instruction_items()

  defp fallback_instruction_items, do: PromptDefaults.openai_segments()

  # ChatGPT backend is stricter than the public Responses API and expects
  # instructions as a single string. Our renderer emits a list of segments.
  # To maximize compatibility, collapse segments into a single string for
  # the chatgpt.com backend while keeping list-of-segments for enterprise.
  defp normalize_instructions_for_chatgpt(value) do
    cond do
      is_list(value) ->
        value
        |> Enum.map(fn
          %{"text" => t} when is_binary(t) -> t
          %{:text => t} when is_binary(t) -> t
          bin when is_binary(bin) -> bin
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")

      is_binary(value) -> value
      true -> ""
    end
  end

  # Convert a list of chat-style messages into Responses API message items,
  # preserving role and using input_text/output_text appropriately.
  defp itemize_messages_for_responses(messages) when is_list(messages) do
    Enum.flat_map(messages, fn m ->
      role = Map.get(m, :role) || Map.get(m, "role") || "user"
      content = Map.get(m, :content) || Map.get(m, "content") || ""

      case normalize_text_from_content(content) do
        "" -> []
        txt -> [to_responses_message(role, txt)]
      end
    end)
  end

  defp itemize_messages_for_responses(_), do: []

  defp to_responses_message(role, text) do
    part_type = if role == "assistant", do: "output_text", else: "input_text"

    %{
      "type" => "message",
      "role" => role,
      "content" => [%{"type" => part_type, "text" => text}]
    }
  end

  defp normalize_text_from_content(content) when is_binary(content), do: content
  defp normalize_text_from_content(%{"text" => txt}) when is_binary(txt), do: txt
  defp normalize_text_from_content(%{text: txt}) when is_binary(txt), do: txt

  defp normalize_text_from_content(%{} = map) do
    txt = map[:text] || map["text"]
    if is_binary(txt), do: txt, else: ""
  end

  defp normalize_text_from_content(list) when is_list(list) do
    list
    |> Enum.map(&normalize_text_from_content/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp normalize_text_from_content(_), do: ""

  defp build_env_context_message(session_name) do
    session_id = resolve_decl_session_id(session_name)
    cwd = safe_session_cwd(session_id)

    text = """
    <environment_context>
      <cwd>#{cwd}</cwd>
    </environment_context>
    """

    to_responses_message("user", String.trim(text))
  end

  defp safe_session_cwd(session_id) do
    case Ecto.UUID.cast(session_id) do
      :error ->
        File.cwd!() |> Path.expand()

      {:ok, _} ->
        try do
          case TheMaestro.Conversations.get_session_with_auth!(session_id) do
            %TheMaestro.Conversations.Session{working_dir: wd} when is_binary(wd) and wd != "" ->
              Path.expand(wd)

            _ ->
              File.cwd!() |> Path.expand()
          end
        rescue
          _ -> File.cwd!() |> Path.expand()
        end
    end
  end

  defp maybe_log_payload(tag, payload) do
    if System.get_env("DEBUG_STREAM_EVENTS") == "1" do
      preview =
        payload
        |> Map.update("input", [], fn items ->
          Enum.map(items, fn
            %{"type" => t, "call_id" => cid} = it when is_binary(cid) ->
              Map.take(it, ["type", "call_id"]) |> Map.put("_type", t)

            %{"type" => t} ->
              %{"_type" => t}

            other ->
              other
          end)
        end)
        |> Map.put(
          "tools_preview",
          Enum.map(Map.get(payload, "tools", []), fn t ->
            %{
              "type" => t["type"],
              "name" => t["name"]
            }
          end)
        )
        |> Map.take([
          "model",
          "prompt_cache_key",
          "parallel_tool_calls",
          "store",
          "input",
          "tools_preview"
        ])

      IO.puts("\n📤 Payload #{inspect(tag)}: \n" <> inspect(preview))
    end
  end

  # legacy collapsed form no longer used

  # Build OpenAI Responses tool list for this session merging built-ins + MCP
  defp tools_for_session(session_id) do
    decl_session_id = resolve_decl_session_id(session_id)
    mcp = MCPRegistry.to_openai_decls(decl_session_id)
    builtins = [shell_tool_function(), apply_patch_function_tool()]

    # prefer MCP when names collide
    names = MapSet.new(Enum.map(mcp, & &1["name"]))
    builtins_filtered = Enum.reject(builtins, fn d -> MapSet.member?(names, d["name"]) end)
    mcp ++ builtins_filtered
  end

  # -- follow-up builders (extracted to reduce complexity) --
  defp build_followup_request(:enterprise, session_name, items, opts) do
    with {:ok, req0} <- ReqClientFactory.create_client(:openai, :api_key, session: session_name) do
      session_id_hdr = Keyword.get(opts, :session_uuid) || Ecto.UUID.generate()
      version = Application.spec(:the_maestro, :vsn) |> to_string()

      req =
        req0
        |> Req.Request.put_header("openai-beta", "responses=experimental")
        |> Req.Request.put_header("session_id", session_id_hdr)
        |> Req.Request.put_header("originator", "codex_cli_rs")
        |> Req.Request.put_header("accept", "text/event-stream")
        |> Req.Request.put_header("version", version)

      instructions =
        resolve_instruction_items(Keyword.get(opts, :decl_session_id))
        |> normalize_instructions_for_chatgpt()

      payload =
        followup_payload_common(
          Keyword.get(opts, :model, "gpt-4o"),
          items,
          tools_for_session(Keyword.get(opts, :decl_session_id) || session_name),
          session_id_hdr,
          instructions,
          parallel?: true,
          store?: nil
        )

      {:ok, req, "/v1/responses", payload, Keyword.get(opts, :timeout, :infinity)}
    end
  end

  defp build_followup_request(:chatgpt_personal, session_name, items, opts) do
    with %SavedAuthentication{credentials: creds} <-
           SavedAuthentication.get_by_provider_and_name(:openai, :oauth, session_name),
         {:ok, account_id} <- chatgpt_account_id_from_id_token(Map.get(creds, "id_token")),
         {:ok, req0} <- ReqClientFactory.create_client(:openai, :oauth, session: session_name) do
      session_id_hdr = Keyword.get(opts, :session_uuid) || Ecto.UUID.generate()

      req =
        req0
        |> Req.Request.put_header("openai-beta", "responses=experimental")
        |> Req.Request.put_header("user-agent", chatgpt_user_agent())
        |> Req.Request.put_header("content-type", "application/json")
        |> Req.Request.put_header("accept", "text/event-stream")
        |> Req.Request.put_header("session_id", session_id_hdr)
        |> Req.Request.put_header("originator", "codex_cli_rs")
        |> Req.Request.put_header("chatgpt-account-id", account_id)

      instructions = resolve_instruction_items(Keyword.get(opts, :decl_session_id))

      payload =
        followup_payload_common(
          Keyword.get(opts, :model, "gpt-5"),
          items,
          tools_for_session(Keyword.get(opts, :decl_session_id) || session_name),
          session_id_hdr,
          instructions,
          parallel?: false,
          store?: false
        )
        |> Map.put("text", %{"verbosity" => "medium"})

      if System.get_env("DEBUG_STREAM_EVENTS") == "1" do
        IO.puts("\n📌 Follow-up headers: session_id=" <> session_id_hdr)
      end

      maybe_log_payload(:openai_oauth_followup, payload)

      {:ok, req, "https://chatgpt.com/backend-api/codex/responses", payload,
       Keyword.get(opts, :timeout, :infinity)}
    else
      nil -> {:error, :session_not_found}
    end
  end

  defp followup_payload_common(model, items, tools, cache_key, instructions, opts) do
    %{
      "model" => model,
      "instructions" => instructions,
      "input" => items,
      "tools" => tools,
      "tool_choice" => "auto",
      "parallel_tool_calls" => Keyword.get(opts, :parallel?, true),
      "stream" => true,
      "prompt_cache_key" => cache_key
    }
    |> maybe_put_store(Keyword.get(opts, :store?))
  end

  defp maybe_put_store(map, nil), do: map
  defp maybe_put_store(map, val), do: Map.put(map, "store", val)

  # Resolve the Conversations session UUID from the SavedAuthentication name that
  # we receive in provider calls. This mirrors the Gemini implementation so MCP
  # registry lookups use the correct session id.
  defp resolve_decl_session_id(session_name) when is_binary(session_name) do
    sa =
      SavedAuthentication.get_by_provider_and_name(:openai, :oauth, session_name) ||
        SavedAuthentication.get_by_provider_and_name(:openai, :api_key, session_name)

    case sa do
      %SavedAuthentication{} = found ->
        case Conversations.latest_session_for_auth_id(found.id) do
          %Conversations.Session{id: id} -> id
          _ -> session_name
        end

      _ ->
        session_name
    end
  end

  defp shell_tool_function do
    %{
      "type" => "function",
      "name" => "shell",
      "description" => "Runs a shell command and returns its output",
      "strict" => false,
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "command" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "The command to execute"
          },
          "workdir" => %{
            "type" => "string",
            "description" => "The working directory to execute the command in"
          },
          "timeout_ms" => %{
            "type" => "number",
            "description" => "The timeout for the command in milliseconds"
          }
        },
        "required" => ["command"],
        "additionalProperties" => false
      }
    }
  end

  defp apply_patch_function_tool do
    %{
      "type" => "function",
      "name" => "apply_patch",
      "description" => "Use the `apply_patch` tool to edit files.",
      "strict" => false,
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "input" => %{
            "type" => "string",
            "description" => "The entire contents of the apply_patch command"
          }
        },
        "required" => ["input"],
        "additionalProperties" => false
      }
    }
  end

  @spec chatgpt_account_id_from_id_token(binary() | nil) :: {:ok, binary()} | {:error, term()}
  defp chatgpt_account_id_from_id_token(nil), do: {:error, :missing_id_token}

  defp chatgpt_account_id_from_id_token(id_token) when is_binary(id_token) do
    with [_, payload, _] <- String.split(id_token, "."),
         {:ok, decoded} <- Base.url_decode64(payload, padding: false),
         {:ok, claims} <- Jason.decode(decoded),
         account_id when is_binary(account_id) <-
           get_in(claims, ["https://api.openai.com/auth", "chatgpt_account_id"]) do
      {:ok, account_id}
    else
      _ -> {:error, :account_id_not_found}
    end
  end

  @impl true
  @spec parse_stream_event(map(), map()) :: {[map()], map()}
  def parse_stream_event(event, state) do
    messages = OpenAIHandler.handle_event(event, [])
    {messages, state}
  end
end
