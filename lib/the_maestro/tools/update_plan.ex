defmodule TheMaestro.Tools.UpdatePlan do
  @moduledoc """
  Update and persist the task plan for the current session/thread.

  Args:
    - explanation: string (optional)
    - plan: [ %{step, status} ]
  """

  alias TheMaestro.Conversations
  alias TheMaestro.Events
  alias TheMaestro.Plans
  alias TheMaestro.Tools.ExecOutput

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ [])

  def run(args, opts) when is_map(args) do
    plan = normalize_plan(Map.get(args, "plan") || Map.get(args, :plan))
    explanation = to_string(Map.get(args, "explanation") || Map.get(args, :explanation) || "")
    session_id = Keyword.get(opts, :session_id)
    thread_id = resolve_thread_id(Keyword.get(opts, :thread_id), session_id)

    with :ok <- validate_session(session_id),
         :ok <- validate_plan(plan),
         :ok <- ensure_single_in_progress(plan),
         :ok <- persist_plan(session_id, thread_id, plan) do
      {:ok, ExecOutput.format("plan stored: " <> summarize(plan, explanation), 0, 0.0)}
    end
  end

  def run(_args, _opts), do: {:error, "invalid arguments"}

  defp normalize_plan(list) when is_list(list) do
    list
    |> Enum.map(fn
      %{"step" => s, "status" => st} ->
        %{step: to_string(s || ""), status: normalize_status(st)}

      %{step: s, status: st} ->
        %{step: to_string(s || ""), status: normalize_status(st)}

      other when is_map(other) ->
        %{
          step: to_string(other[:step] || other["step"] || ""),
          status: normalize_status(other[:status] || other["status"])
        }

      _ ->
        %{step: "", status: "pending"}
    end)
    |> Enum.filter(&(String.trim(&1.step) != ""))
  end

  defp normalize_plan(_), do: []

  defp normalize_status(s) when s in ["pending", :pending], do: "pending"
  defp normalize_status(s) when s in ["in_progress", :in_progress], do: "in_progress"
  defp normalize_status(s) when s in ["completed", :completed], do: "completed"
  defp normalize_status(_), do: "pending"

  defp resolve_thread_id(nil, session_id) do
    case Conversations.latest_snapshot(session_id) do
      %Conversations.ChatEntry{thread_id: tid} -> tid
      _ -> nil
    end
  end

  defp resolve_thread_id(tid, _), do: tid

  defp validate_session(session_id) when is_binary(session_id) and session_id != "", do: :ok
  defp validate_session(_), do: {:error, "missing session_id"}

  defp validate_plan([]), do: {:error, "missing plan"}
  defp validate_plan(_), do: :ok

  defp ensure_single_in_progress(plan) do
    if Enum.count(plan, &(&1.status == "in_progress")) > 1 do
      {:error, "multiple in_progress steps"}
    else
      :ok
    end
  end

  defp persist_plan(session_id, thread_id, plan) do
    :ok = Plans.put(session_id, thread_id, plan)
    _ = Events.broadcast_plan_update(session_id, thread_id, plan)
    :ok
  end

  defp summarize(plan, explanation) do
    counts = Enum.frequencies_by(plan, & &1.status)

    [
      maybe_line(explanation),
      "steps=#{length(plan)}",
      "pending=#{Map.get(counts, "pending", 0)}",
      "in_progress=#{Map.get(counts, "in_progress", 0)}",
      "completed=#{Map.get(counts, "completed", 0)}"
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
  end

  defp maybe_line(""), do: ""
  defp maybe_line(s), do: String.trim(s)
end
