defmodule TheMaestro.Providers.OpenAI.Streaming do
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc """
  OpenAI streaming provider with dual-endpoint support.

  - ChatGPT Personal (OAuth): https://chatgpt.com/backend-api/codex/responses
  - Enterprise/API Key (Responses): https://api.openai.com/v1/responses
  """

  @behaviour TheMaestro.Providers.Behaviours.Streaming

  require Logger
  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.Providers.Http.StreamingAdapter
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Streaming.OpenAIHandler
  alias TheMaestro.Types

  @type mode :: :chatgpt_personal | :enterprise

  @spec stream_chat(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  @impl true
  def stream_chat(session_id, messages, opts \\ []) do
    with true <- (is_list(messages) and messages != []) or {:error, :empty_messages},
         {:ok, mode} <- detect_mode(session_id),
         {:ok, stream} <- do_stream(mode, session_id, messages, opts) do
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
  def stream_tool_followup(session_id, items, opts \\ []) when is_list(items) do
    # Implement follow-up in-line to allow adapter injection in tests
    model = Keyword.get(opts, :model) || "gpt-4o"
    adapter = Keyword.get(opts, :streaming_adapter, StreamingAdapter)

    case detect_mode(session_id) do
      {:ok, :enterprise} ->
        with {:ok, req0} <- ReqClientFactory.create_client(:openai, :api_key, session: session_id) do
          version = Application.spec(:the_maestro, :vsn) |> to_string()
          session_id_hdr = Keyword.get(opts, :session_uuid) || Ecto.UUID.generate()

          req =
            req0
            |> Req.Request.put_header("openai-beta", "responses=experimental")
            |> Req.Request.put_header("session_id", session_id_hdr)
            |> Req.Request.put_header("originator", "codex_cli_rs")
            |> Req.Request.put_header("accept", "text/event-stream")
            |> Req.Request.put_header("version", version)

          payload = %{
            "model" => model,
            "input" => items,
            "tools" => responses_tools(),
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

      {:ok, :chatgpt_personal} ->
        with %SavedAuthentication{credentials: creds} <-
               SavedAuthentication.get_by_provider_and_name(:openai, :oauth, session_id),
             {:ok, account_id} <- chatgpt_account_id_from_id_token(Map.get(creds, "id_token")),
             {:ok, req0} <- ReqClientFactory.create_client(:openai, :oauth, session: session_id) do
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

          payload = %{
            "model" => Keyword.get(opts, :model) || "gpt-5",
            "instructions" => load_instructions(),
            "input" => items,
            "tools" => responses_tools(),
            "tool_choice" => "auto",
            # ChatGPT backend expects serialized tool turns; do not parallelize follow-ups
            "parallel_tool_calls" => false,
            "store" => false,
            "stream" => true,
            "prompt_cache_key" => session_id_hdr,
            "text" => %{"verbosity" => "medium"}
          }

          if System.get_env("DEBUG_STREAM_EVENTS") == "1" do
            IO.puts("\n📌 Follow-up headers: session_id=" <> session_id_hdr)
          end

          maybe_log_payload(:openai_oauth_followup, payload)

          adapter.stream_request(req,
            method: :post,
            url: "https://chatgpt.com/backend-api/codex/responses",
            json: payload,
            timeout: Keyword.get(opts, :timeout, :infinity)
          )
        else
          nil -> {:error, :session_not_found}
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
  defp do_stream(:enterprise, session_id, messages, opts) do
    model = Keyword.get(opts, :model) || "gpt-4o"
    adapter = Keyword.get(opts, :streaming_adapter, StreamingAdapter)

    with {:ok, req0} <- ReqClientFactory.create_client(:openai, :api_key, session: session_id) do
      version = Application.spec(:the_maestro, :vsn) |> to_string()
      session_id_hdr = Keyword.get(opts, :session_uuid) || Ecto.UUID.generate()

      req =
        req0
        |> Req.Request.put_header("openai-beta", "responses=experimental")
        |> Req.Request.put_header("session_id", session_id_hdr)
        |> Req.Request.put_header("originator", "codex_cli_rs")
        |> Req.Request.put_header("accept", "text/event-stream")
        |> Req.Request.put_header("version", version)

      payload = %{
        "model" => model,
        "input" => normalize_messages_for_responses(messages),
        "tools" => responses_tools(),
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

  defp do_stream(:chatgpt_personal, session_id, messages, opts) do
    model = Keyword.get(opts, :model) || "gpt-5"
    adapter = Keyword.get(opts, :streaming_adapter, StreamingAdapter)

    with %SavedAuthentication{credentials: creds} <-
           SavedAuthentication.get_by_provider_and_name(:openai, :oauth, session_id),
         {:ok, account_id} <- chatgpt_account_id_from_id_token(Map.get(creds, "id_token")),
         {:ok, req0} <- ReqClientFactory.create_client(:openai, :oauth, session: session_id) do
      # Headers required by ChatGPT backend for responses API
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

      instructions = load_instructions()

      payload = %{
        "model" => model,
        "instructions" => instructions,
        "input" => [
          %{
            "type" => "message",
            "role" => "user",
            "content" => [
              %{"type" => "input_text", "text" => build_user_text(messages)}
            ]
          }
        ],
        "tools" => responses_tools(),
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

  defp load_instructions do
    path =
      System.get_env("CODEX_PROMPT_PATH") ||
        "source/codex/codex-rs/core/prompt.md"

    case File.read(path) do
      {:ok, contents} -> contents
      _ -> ""
    end
  end

  defp build_user_text(messages) do
    # Build a full conversation transcript so ChatGPT backend has context
    # Messages can be maps with string or atom keys: %{"role" => r, "content" => t}
    transcript =
      messages
      |> Enum.map(fn m ->
        role = Map.get(m, :role) || Map.get(m, "role") || "user"
        content = Map.get(m, :content) || Map.get(m, "content") || ""
        "#{role}: #{content}"
      end)
      |> Enum.join("\n\n")

    "<conversation>\n\n" <> transcript <> "\n\n</conversation>"
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
        |> Map.take(["model", "prompt_cache_key", "parallel_tool_calls", "store", "input"])

      IO.puts("\n📤 Payload #{inspect(tag)}: \n" <> inspect(preview))
    end
  end

  defp normalize_messages_for_responses(messages) do
    # Convert chat-style messages to Responses input format minimally
    [
      %{
        "type" => "message",
        "role" => "user",
        "content" =>
          Enum.map(messages, fn m ->
            content = Map.get(m, :content) || Map.get(m, "content") || ""
            %{"type" => "input_text", "text" => content}
          end)
      }
    ]
  end

  # Minimal tool exposure to enable function/custom tool calls
  defp responses_tools do
    [shell_tool_function(), apply_patch_function_tool()]
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
