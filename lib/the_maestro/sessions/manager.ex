defmodule TheMaestro.Sessions.Manager do
  @moduledoc """
  Session-scoped streaming manager.

  - Supervises provider streaming tasks under `TheMaestro.Sessions.TaskSup`
  - Publishes streaming events on `"session:" <> session_id` via `TheMaestro.PubSub`
  - Provides APIs to start/cancel streams and run tool follow-ups
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias TheMaestro.Streaming
  alias TheMaestro.Providers.{Anthropic, Gemini, OpenAI}

  @type state :: %{
          optional(String.t()) => %{task: pid() | nil, stream_id: String.t() | nil}
        }

  # Public API

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))

  def subscribe(session_id) when is_binary(session_id) do
    PubSub.subscribe(TheMaestro.PubSub, topic(session_id))
  end

  def start_stream(session_id, provider, session_name, provider_messages, model, opts \\ [])
      when is_binary(session_id) and is_atom(provider) do
    GenServer.call(
      __MODULE__,
      {:start_stream, session_id, provider, session_name, provider_messages, model, opts},
      30_000
    )
  end

  def run_followup(session_id, provider, session_name, items, model, opts \\ [])
      when is_binary(session_id) and is_atom(provider) do
    GenServer.call(
      __MODULE__,
      {:run_followup, session_id, provider, session_name, items, model, opts},
      30_000
    )
  end

  def cancel(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:cancel, session_id})
  end

  # GenServer
  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call(
        {:start_stream, session_id, provider, session_name, provider_messages, model, _opts},
        _from,
        st
      ) do
    st = cancel_if_running(st, session_id)
    stream_id = Ecto.UUID.generate()

    {:ok, task} =
      Task.Supervisor.start_child(TheMaestro.Sessions.TaskSup, fn ->
        result = do_call_provider(provider, session_name, provider_messages, model)

        case result do
          {:ok, stream} ->
            publish(
              session_id,
              {:ai_stream, stream_id, %{type: :thinking, metadata: %{thinking: true}}}
            )

            for msg <- Streaming.parse_stream(stream, provider, log_unknown_events: true) do
              publish(session_id, {:ai_stream, stream_id, msg})
            end

            # Gemini may not emit :done
            publish(session_id, {:ai_stream, stream_id, %{type: :done}})

          {:error, reason} ->
            publish(session_id, {:ai_stream, stream_id, %{type: :error, error: inspect(reason)}})
            publish(session_id, {:ai_stream, stream_id, %{type: :done}})
        end
      end)

    {:reply, {:ok, stream_id}, put_in(st, [session_id], %{task: task, stream_id: stream_id})}
  end

  def handle_call(
        {:run_followup, session_id, provider, session_name, items, model, _opts},
        _from,
        st
      ) do
    st = cancel_if_running(st, session_id)
    stream_id = Ecto.UUID.generate()

    {:ok, task} =
      Task.Supervisor.start_child(TheMaestro.Sessions.TaskSup, fn ->
        result =
          case provider do
            :openai ->
              OpenAI.Streaming.stream_tool_followup(session_name, items, model: model)

            :anthropic ->
              Anthropic.Streaming.stream_tool_followup(session_name, items, model: model)

            :gemini ->
              Gemini.Streaming.stream_tool_followup(session_name, items, model: model)
          end

        case result do
          {:ok, stream} ->
            for msg <- Streaming.parse_stream(stream, provider, log_unknown_events: true) do
              publish(session_id, {:ai_stream, stream_id, msg})
            end

            publish(session_id, {:ai_stream, stream_id, %{type: :done}})

          {:error, reason} ->
            publish(session_id, {:ai_stream, stream_id, %{type: :error, error: inspect(reason)}})
            publish(session_id, {:ai_stream, stream_id, %{type: :done}})
        end
      end)

    {:reply, {:ok, stream_id}, put_in(st, [session_id], %{task: task, stream_id: stream_id})}
  end

  def handle_call({:cancel, session_id}, _from, st) do
    st = cancel_if_running(st, session_id)
    {:reply, :ok, st}
  end

  defp do_call_provider(:openai, session_name, messages, model),
    do: OpenAI.Streaming.stream_chat(session_name, messages, model: model)

  defp do_call_provider(:gemini, session_name, messages, model),
    do: Gemini.Streaming.stream_chat(session_name, messages, model: model)

  defp do_call_provider(:anthropic, session_name, messages, model),
    do: Anthropic.Streaming.stream_chat(session_name, messages, model: model)

  defp do_call_provider(other, _s, _m, _model), do: {:error, {:unsupported_provider, other}}

  defp cancel_if_running(st, session_id) do
    case Map.get(st, session_id) do
      %{task: pid} when is_pid(pid) ->
        Process.exit(pid, :kill)
        Map.delete(st, session_id)

      _ ->
        st
    end
  end

  defp publish(session_id, message) do
    PubSub.broadcast(TheMaestro.PubSub, topic(session_id), message)
  end

  defp topic(session_id), do: "session:" <> session_id
end
