defmodule TheMaestro.Providers.OpenAI.Streaming do
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

    with {:ok, req0} <- ReqClientFactory.create_client(:openai, :api_key, session: session_id) do
      version = Application.spec(:the_maestro, :vsn) |> to_string()
      req = Req.Request.put_header(req0, "version", version)

      payload = %{
        "model" => model,
        "input" => normalize_messages_for_responses(messages),
        "stream" => true
      }

      payload = maybe_put_tools(payload, Keyword.get(opts, :tools))

      StreamingAdapter.stream_request(req,
        method: :post,
        url: "/v1/responses",
        json: payload,
        timeout: Keyword.get(opts, :timeout, :infinity)
      )
    end
  end

  defp do_stream(:chatgpt_personal, session_id, messages, opts) do
    model = Keyword.get(opts, :model) || "gpt-5"

    with %SavedAuthentication{credentials: creds} <-
           SavedAuthentication.get_by_provider_and_name(:openai, :oauth, session_id),
         {:ok, account_id} <- chatgpt_account_id_from_id_token(Map.get(creds, "id_token")),
         {:ok, req0} <- ReqClientFactory.create_client(:openai, :oauth, session: session_id) do
      # Headers required by ChatGPT backend for responses API
      req =
        req0
        |> Req.Request.put_header("openai-beta", "responses=experimental")
        |> Req.Request.put_header("user-agent", chatgpt_user_agent())
        |> Req.Request.put_header("content-type", "application/json")
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
        # tools added below if provided
        "parallel_tool_calls" => true,
        "store" => false,
        "stream" => true,
        "text" => %{"verbosity" => "medium"}
      }

      payload = maybe_put_tools(payload, Keyword.get(opts, :tools))

      StreamingAdapter.stream_request(req,
        method: :post,
        url: "https://chatgpt.com/backend-api/codex/responses",
        json: payload,
        timeout: Keyword.get(opts, :timeout, :infinity)
      )
    else
      nil -> {:error, :session_not_found}
    end
  end

  defp maybe_put_tools(payload, tools) when is_list(tools) and tools != [] do
    payload
    |> Map.put("tools", tools)
    |> Map.put("tool_choice", "auto")
  end

  defp maybe_put_tools(payload, _), do: payload

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
