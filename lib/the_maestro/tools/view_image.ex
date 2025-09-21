defmodule TheMaestro.Tools.ViewImage do
  @moduledoc """
  Acknowledge a local image path for this turn.

  Args:
    - path: string (absolute or workspace-relative)
  """

  alias TheMaestro.Tools.{ExecOutput, PathResolver}
  alias TheMaestro.Images
  alias TheMaestro.Conversations
  alias TheMaestro.Events

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ []) when is_map(args) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())
    session_id = Keyword.get(opts, :session_id)
    thread_id =
      Keyword.get(opts, :thread_id) ||
        case Conversations.latest_snapshot(session_id) do
          %Conversations.ChatEntry{thread_id: tid} -> tid
          _ -> nil
        end
    path = Map.get(args, "path") || Map.get(args, :path)

    cond do
      !is_binary(session_id) or session_id == "" -> {:error, "missing session_id"}
      !is_binary(path) or String.trim(path) == "" -> {:error, "missing path"}
      true ->
        case resolve_image(path, base) do
          {:ok, abs} ->
            :ok = Images.append(session_id, thread_id, %{path: abs, ts: System.system_time(:second)})
            _ = Events.broadcast_image_attached(session_id, thread_id, abs)
            {:ok, ExecOutput.format("image attached: " <> abs, 0, 0.0)}
          {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
          {:error, :not_found} -> {:error, "enoent"}
          {:error, _} -> {:error, "invalid path"}
        end
    end
  end

  def run(_args, _opts), do: {:error, "invalid arguments"}

  defp resolve_image(path, base) do
    case PathResolver.resolve_existing(path, base) do
      {:ok, abs} -> if image_ext?(abs), do: {:ok, abs}, else: {:ok, abs}
      {:error, :outside_workspace} -> {:error, :outside_workspace}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp image_ext?(p) do
    ext = String.downcase(Path.extname(to_string(p || "")))
    ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg"]
  end
end
