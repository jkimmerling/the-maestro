defmodule TheMaestro.Providers.Anthropic.Streaming do
  @moduledoc """
  Anthropic streaming provider stub for Story 0.2/0.4.
  """
  @behaviour TheMaestro.Providers.Behaviours.Streaming
  require Logger
  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.Providers.Http.StreamingAdapter
  alias TheMaestro.Types

  @impl true
  @spec stream_chat(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_chat(session_id, messages, opts \\ []) do
    Logger.debug("Anthropic.Streaming.stream_chat/3 called")

    with true <- (is_list(messages) and messages != []) or {:error, :empty_messages},
         auth_type <- Keyword.get(opts, :auth_type, :api_key),
         {:ok, req} <- ReqClientFactory.create_client(:anthropic, auth_type, session: session_id) do
      model = Keyword.get(opts, :model)

      if is_nil(model) do
        {:error, :missing_model}
      else
        body = %{
          "model" => model,
          "messages" => messages,
          "stream" => true
        }

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
end
