defmodule TheMaestro.Providers.OpenAI.Streaming do
  @moduledoc """
  OpenAI streaming provider stub.

  Integrate Req streaming adapter in Story 0.2 and complete OpenAI logic in 0.3.
  """
  @behaviour TheMaestro.Providers.Behaviours.Streaming
  require Logger
  @impl true
  def stream_chat(_session_id, _messages, _opts \\ []) do
    Logger.debug("OpenAI.Streaming.stream_chat/3 stub called")
    {:error, :not_implemented}
  end

  @impl true
  def parse_stream_event(_event, state) do
    Logger.debug("OpenAI.Streaming.parse_stream_event/2 stub called")
    {[], state}
  end
end
