defmodule TheMaestro.Domain.CombinedChat do
  @moduledoc """
  Versioned value object for the combined chat payload we persist in ChatEntry.

  Stored as JSONB; this module provides helpers to map to/from the canonical
  shape and reserve room for evolution via `version`.
  """

  @enforce_keys [:version, :messages]
  defstruct version: "v1", messages: [], events: [], threads: nil

  @type t :: %__MODULE__{
          version: String.t(),
          messages: [map()],
          events: [map()],
          threads: map() | nil
        }

  @spec new(keyword() | map()) :: t()
  def new(opts) when is_list(opts), do: struct!(__MODULE__, Enum.into(opts, %{}))
  def new(%{} = map), do: from_map(map)

  @spec from_map(map()) :: t()
  def from_map(%{} = map) do
    %__MODULE__{
      version: Map.get(map, "version") || Map.get(map, :version) || "v1",
      messages: Map.get(map, "messages") || Map.get(map, :messages) || [],
      events: Map.get(map, "events") || Map.get(map, :events) || [],
      threads: threads_from(map)
    }
  end

  defp threads_from(map) do
    case Map.get(map, "threads") || Map.get(map, :threads) do
      %{} = t -> t
      _ -> nil
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = cc) do
    base = %{"version" => cc.version, "messages" => cc.messages, "events" => cc.events}

    if is_map(cc.threads) do
      Map.put(base, "threads", cc.threads)
    else
      base
    end
  end

  @type frame_map :: map()

  @doc "Put or replace the frames for a given thread/turn index in a v2 structure."
  @spec put_turn_frames(t() | map(), String.t(), non_neg_integer(), [frame_map]) :: t()
  def put_turn_frames(%__MODULE__{} = cc, thread_id, turn_index, frames)
      when is_binary(thread_id) and is_integer(turn_index) and is_list(frames) do
    threads = cc.threads || %{}
    updated = Map.update(threads, thread_id, %{"turns" => [%{"turn_index" => turn_index, "frames" => frames}]}, fn thread ->
      turns = thread["turns"] || []
      upsert_turn(turns, turn_index, frames)
      |> then(&Map.put(thread, "turns", &1))
    end)

    %__MODULE__{cc | version: "v2", threads: updated}
  end

  def put_turn_frames(%{} = map, thread_id, turn_index, frames),
    do: put_turn_frames(from_map(map), thread_id, turn_index, frames)

  @doc "Get frames for a given thread/turn index from a v2 structure."
  @spec get_turn_frames(t() | map(), String.t(), non_neg_integer()) :: [frame_map]
  def get_turn_frames(%__MODULE__{} = cc, thread_id, turn_index)
      when is_binary(thread_id) and is_integer(turn_index) do
    with %{} = threads <- cc.threads,
         %{"turns" => turns} <- Map.get(threads, thread_id),
         %{"frames" => frames} <- Enum.find(turns, &match_turn_index?(&1, turn_index)),
         true <- is_list(frames) do
      frames
    else
      _ -> []
    end
  end

  defp upsert_turn(turns, idx, frames) do
    case Enum.find_index(turns, &match_turn_index?(&1, idx)) do
      nil -> turns ++ [%{"turn_index" => idx, "frames" => frames}]
      i -> List.replace_at(turns, i, %{"turn_index" => idx, "frames" => frames})
    end
  end

  defp match_turn_index?(%{"turn_index" => i}, idx), do: i == idx
  defp match_turn_index?(%{turn_index: i}, idx), do: i == idx
  defp match_turn_index?(_, _), do: false

  def get_turn_frames(%{} = map, thread_id, turn_index),
    do: get_turn_frames(from_map(map), thread_id, turn_index)

  @doc "Backfill thread turns/frames from legacy messages if missing."
  @spec backfill_for_thread(map() | t(), String.t()) :: map()
  def backfill_for_thread(cc, thread_id) when is_binary(thread_id) do
    cc = if match?(%__MODULE__{}, cc), do: cc, else: from_map(cc)

    has_frames? = is_map(cc.threads) and is_map(cc.threads[thread_id])

    if has_frames? do
      to_map(cc)
    else
      turns = build_turns_from_messages(cc.messages || [])
      cc
      |> Map.put(:version, "v2")
      |> Map.put(:threads, %{thread_id => %{"turns" => turns}})
      |> to_map()
  end
  end

  defp build_turns_from_messages(messages) when is_list(messages) do
    Enum.reduce(messages, {[], %{turn_index: 0, frames: [], fidx: 0}}, fn m, {acc, cur} ->
      role = to_string(m["role"] || m[:role] || "assistant")
      text = message_text(m)

      case role do
        "user" -> add_user(acc, cur, text)
        "assistant" -> {acc, add_frame(cur, "assistant", "assistant_text", %{"delta" => text})}
        "tool" -> {acc, add_frame(cur, "tool", "tool_result", %{"preview" => text})}
        _ -> {acc, add_frame(cur, role, "message", %{"text" => text})}
      end
    end)
    |> then(fn {acc, cur} ->
      acc = if cur.frames == [], do: acc, else: [%{"turn_index" => cur.turn_index, "frames" => cur.frames} | acc]
      Enum.reverse(acc)
    end)
  end

  alias TheMaestro.Domain.TurnFrame

  defp frame(%{fidx: fidx}, role, kind, payload) do
    TurnFrame.new!(%{
      id: Ecto.UUID.generate(),
      idx: fidx,
      at_ms: System.monotonic_time(:millisecond),
      role: role,
      kind: kind,
      payload: payload,
      thought?: kind == "assistant_thinking",
      collapsed?: kind in ["assistant_thinking", "function_call"]
    })
    |> TurnFrame.to_map()
  end

  defp message_text(m) do
    content = List.wrap(m["content"] || m[:content] || [])
    case List.first(content) do
      %{"text" => t} -> to_string(t)
      %{text: t} -> to_string(t)
      _ -> ""
    end
  end

  defp add_user(acc, cur, text) do
    acc = if cur.frames == [], do: acc, else: [%{"turn_index" => cur.turn_index, "frames" => cur.frames} | acc]
    new_tix = if cur.frames == [], do: cur.turn_index, else: cur.turn_index + 1
    frame = frame(%{fidx: 0}, "user", "user_text", %{"text" => text})
    {acc, %{turn_index: new_tix, frames: [frame], fidx: 1}}
  end

  defp add_frame(cur, role, kind, payload) do
    frame = frame(cur, role, kind, payload)
    %{cur | frames: cur.frames ++ [frame], fidx: cur.fidx + 1}
  end
end
