defmodule TheMaestro.Providers.Anthropic.Streaming do
  @moduledoc """
  Anthropic streaming provider stub for Story 0.2/0.4.
  """
  @behaviour TheMaestro.Providers.Behaviours.Streaming
  require Logger
  @impl true
  def stream_chat(_session_id, _messages, _opts \\ []) do
    Logger.debug("Anthropic.Streaming.stream_chat/3 stub called")
    {:error, :not_implemented}
  end
end
