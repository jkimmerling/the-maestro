defmodule TheMaestro.Tools.TodoWrite do
  @moduledoc """
  Update the in-memory todo list for the current session.

  Args:
    - todos: [ %{content, activeForm, status} ]
  """

  alias TheMaestro.Todos
  alias TheMaestro.Tools.ExecOutput

  @valid_statuses ["pending", "in_progress", "completed"]

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    thread_id = Keyword.get(opts, :thread_id)

    if is_binary(session_id),
      do: do_run(args, session_id, thread_id),
      else: {:error, "missing session_id"}
  end

  defp do_run(args, session_id, thread_id) do
    with {:ok, todos} <- resolve_todos(args) do
      # Clear list if all completed, else store provided list
      new_list = if Enum.all?(todos, &(&1.status == "completed")), do: [], else: todos
      :ok = Todos.put(session_id, thread_id, new_list)
      {:ok, ExecOutput.format("todos updated: #{length(new_list)} items", 0, 0.0)}
    end
  end

  defp resolve_todos(args) do
    case Map.get(args, "todos") || Map.get(args, :todos) do
      list when is_list(list) and list != [] ->
        items = Enum.map(list, &normalize_item/1)

        if Enum.all?(items, &valid_item?/1) do
          {:ok, items}
        else
          {:error, "invalid todos"}
        end

      _ ->
        {:error, "missing todos"}
    end
  end

  defp normalize_item(%{content: c, activeForm: a, status: s}) do
    %{content: to_string(c || ""), activeForm: to_string(a || ""), status: normalize_status(s)}
  end

  defp normalize_item(%{"content" => c, "activeForm" => a, "status" => s}) do
    %{content: to_string(c || ""), activeForm: to_string(a || ""), status: normalize_status(s)}
  end

  defp normalize_item(other) when is_map(other) do
    %{
      content: to_string(other[:content] || other["content"] || ""),
      activeForm: to_string(other[:activeForm] || other["activeForm"] || ""),
      status: normalize_status(other[:status] || other["status"])
    }
  end

  defp normalize_status(s) when s in ["pending", :pending], do: "pending"
  defp normalize_status(s) when s in ["in_progress", :in_progress], do: "in_progress"
  defp normalize_status(s) when s in ["completed", :completed], do: "completed"
  defp normalize_status(_), do: "pending"

  defp valid_item?(%{content: c, activeForm: a, status: s}) do
    is_binary(c) and String.trim(c) != "" and is_binary(a) and String.trim(a) != "" and
      s in @valid_statuses
  end
end
