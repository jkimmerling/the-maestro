defmodule TheMaestro.Tools.UpdatePlan do
  @moduledoc """
  Update and persist the task plan for the current session/thread.

  Args:
    - explanation: string (optional)
    - plan: [ %{step, status} ]
  """

  alias TheMaestro.Tools.ExecOutput
  alias TheMaestro.Plans
  alias TheMaestro.Conversations
  alias TheMaestro.Events

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ []) when is_map(args) do
    plan = normalize_plan(Map.get(args, "plan") || Map.get(args, :plan))
    explanation = to_string(Map.get(args, "explanation") || Map.get(args, :explanation) || "")

    session_id = Keyword.get(opts, :session_id)
    thread_id =
      Keyword.get(opts, :thread_id) ||
        case Conversations.latest_snapshot(session_id) do
          %Conversations.ChatEntry{thread_id: tid} -> tid
          _ -> nil
        end

    cond do
      !is_binary(session_id) or session_id == "" -> {:error, "missing session_id"}
      plan == [] -> {:error, "missing plan"}
      too_many_in_progress?(plan) -> {:error, "multiple in_progress steps"}
      true ->
        :ok = Plans.put(session_id, thread_id, plan)
        _ = Events.broadcast_plan_update(session_id, thread_id, plan)

        counts = Enum.frequencies_by(plan, &(&1.status))
        summary =
          [
            maybe_line(explanation),
            "steps=#{length(plan)}",
            "pending=#{Map.get(counts, "pending", 0)}",
            "in_progress=#{Map.get(counts, "in_progress", 0)}",
            "completed=#{Map.get(counts, "completed", 0)}"
          ]
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("; ")

        {:ok, ExecOutput.format("plan stored: " <> summary, 0, 0.0)}
    end
  end

  def run(_args, _opts), do: {:error, "invalid arguments"}

  defp normalize_plan(list) when is_list(list) do
    list
    |> Enum.map(fn
      %{"step" => s, "status" => st} -> %{step: to_string(s || ""), status: normalize_status(st)}
      %{step: s, status: st} -> %{step: to_string(s || ""), status: normalize_status(st)}
      other when is_map(other) ->
        %{step: to_string(other[:step] || other["step"] || ""), status: normalize_status(other[:status] || other["status"])}
      _ -> %{step: "", status: "pending"}
    end)
    |> Enum.filter(&(String.trim(&1.step) != ""))
  end

  defp normalize_plan(_), do: []

  defp normalize_status(s) when s in ["pending", :pending], do: "pending"
  defp normalize_status(s) when s in ["in_progress", :in_progress], do: "in_progress"
  defp normalize_status(s) when s in ["completed", :completed], do: "completed"
  defp normalize_status(_), do: "pending"

  defp too_many_in_progress?(plan) do
    Enum.count(plan, &(&1.status == "in_progress")) > 1
  end

  defp maybe_line(""), do: ""
  defp maybe_line(s), do: String.trim(s)
end
