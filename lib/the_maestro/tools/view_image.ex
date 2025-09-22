defmodule TheMaestro.Tools.ViewImage do
  @moduledoc """
  Acknowledge a local image path for this turn.

  Args:
    - path: string (absolute or workspace-relative)
  """

  alias TheMaestro.Conversations
  alias TheMaestro.Events
  alias TheMaestro.Images
  alias TheMaestro.Tools.{ExecOutput, PathResolver}

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(_args, _opts \\ [])

  def run(args, opts) when is_map(args) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())
    session_id = Keyword.get(opts, :session_id)
    thread_id = resolve_thread_id(Keyword.get(opts, :thread_id), session_id)
    path = Map.get(args, "path") || Map.get(args, :path)

    with :ok <- validate_session(session_id),
         :ok <- validate_path(path),
         {:ok, abs} <- resolve_image(path, base) do
      :ok = Images.append(session_id, thread_id, %{path: abs, ts: System.system_time(:second)})
      _ = Events.broadcast_image_attached(session_id, thread_id, abs)
      {:ok, ExecOutput.format("image attached: " <> abs, 0, 0.0)}
    else
      {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
      {:error, _} -> {:error, "invalid path"}
    end
  end

  def run(_args, _opts), do: {:error, "invalid arguments"}

  defp resolve_thread_id(nil, session_id) do
    case Conversations.latest_snapshot(session_id) do
      %Conversations.ChatEntry{thread_id: tid} -> tid
      _ -> nil
    end
  end

  defp resolve_thread_id(tid, _), do: tid

  defp validate_session(session_id) when is_binary(session_id) and session_id != "", do: :ok
  defp validate_session(_), do: {:error, "missing session_id"}

  defp validate_path(path) do
    if is_binary(path) and String.trim(path) != "" do
      :ok
    else
      {:error, "missing path"}
    end
  end

  defp resolve_image(path, base) do
    case PathResolver.resolve(path, base) do
      {:ok, abs} -> if image_ext?(abs), do: {:ok, abs}, else: {:ok, abs}
      {:error, :outside_workspace} -> {:error, :outside_workspace}
      {:error, _} -> {:error, :invalid}
    end
  end

  defp image_ext?(p) do
    p_str = if is_binary(p), do: p, else: ""
    ext = String.downcase(Path.extname(p_str))
    ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg"]
  end
end
