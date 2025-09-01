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

      if is_nil(model) or model == "" do
        {:error, :missing_model}
      else
        payload = %{
          "model" => model,
          "contents" => normalize_messages(messages),
          "stream" => true
        }

        StreamingAdapter.stream_request(
          req,
          method: :post,
          url: "/v1beta/models/#{model}:streamGenerateContent",
          json: payload
        )
      end
    end
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
    Enum.map(messages, fn msg ->
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
    end)
  end
end
