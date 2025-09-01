defmodule TheMaestro.Providers.Gemini.Streaming do
  @moduledoc """
  Gemini streaming provider stub for Story 0.2/0.5.
  """
  @behaviour TheMaestro.Providers.Behaviours.Streaming
  require Logger
  alias TheMaestro.Types
  @impl true
  @spec stream_chat(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_chat(_session_id, _messages, _opts \\ []) do
    Logger.debug("Gemini.Streaming.stream_chat/3 stub called")
    {:error, :not_implemented}
  end

  @impl true
  @spec parse_stream_event(map(), map()) :: {[map()], map()}
  def parse_stream_event(_event, state) do
    Logger.debug("Gemini.Streaming.parse_stream_event/2 stub called")
    {[], state}
  end
end
