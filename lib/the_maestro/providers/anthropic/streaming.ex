defmodule TheMaestro.Providers.Anthropic.Streaming do
  @moduledoc """
  Anthropic streaming provider stub for Story 0.2/0.4.
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
    Logger.debug("Anthropic.Streaming.stream_chat/3 called")

    with true <- (is_list(messages) and messages != []) or {:error, :empty_messages},
         {:ok, auth_type} <- detect_auth_type(session_id),
         {:ok, req} <- ReqClientFactory.create_client(:anthropic, auth_type, session: session_id) do
      model = Keyword.get(opts, :model)

      if is_nil(model) do
        {:error, :missing_model}
      else
        base_body = %{
          "model" => model,
          "messages" => messages,
          "max_tokens" => Keyword.get(opts, :max_tokens, 512),
          "stream" => true
        }

        tools = Keyword.get(opts, :tools, [])
        tool_names = Enum.map(tools, fn t -> Map.get(t, :name) || Map.get(t, "name") end)
        Logger.debug("Anthropic: model=#{model} tools=#{inspect(tool_names)}")

        # Claude Code parity: add system prompt for OAuth tokens
        body =
          case auth_type do
            :oauth ->
              Map.put(
                base_body,
                "system",
                "You are Claude Code, Anthropic's official CLI for Claude."
              )

            _ ->
              base_body
          end

        body = maybe_put_tools(body, tools)

        StreamingAdapter.stream_request(req, method: :post, url: "/v1/messages", json: body)
      end
    end
  end

  @impl true
  @spec parse_stream_event(map(), map()) :: {[map()], map()}
  def parse_stream_event(_event, state) do
    Logger.debug("Anthropic.Streaming.parse_stream_event/2 stub called")
    {[], state}
  end

  defp maybe_put_tools(body, tools) when is_list(tools) and tools != [] do
    body
    |> Map.put("tools", tools)
    |> Map.put("tool_choice", "auto")
  end

  defp maybe_put_tools(body, _), do: body

  @spec detect_auth_type(String.t()) :: {:ok, :oauth | :api_key} | {:error, term()}
  defp detect_auth_type(session_id) do
    cond do
      is_map(SavedAuthentication.get_by_provider_and_name(:anthropic, :oauth, session_id)) ->
        {:ok, :oauth}

      is_map(SavedAuthentication.get_by_provider_and_name(:anthropic, :api_key, session_id)) ->
        {:ok, :api_key}

      true ->
        {:error, :session_not_found}
    end
  end
end
