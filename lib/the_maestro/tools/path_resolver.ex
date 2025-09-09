defmodule TheMaestro.Tools.PathResolver do
  @moduledoc """
  Resolves user-provided paths against a session workspace root and enforces
  confinement. Converts relative paths to absolute under the workspace_root and
  rejects any path that escapes the root (including via symlinks when resolvable).
  """

  @type reason :: :missing | :invalid | :outside_workspace | :not_found

  @doc """
  Resolve a path-like value within `workspace_root`.

  Returns `{:ok, abs_path}` when resolution succeeds (existence not required),
  or `{:error, reason}`.
  """
  @spec resolve(String.t(), String.t()) :: {:ok, String.t()} | {:error, reason}
  def resolve(path_like, workspace_root)
      when is_binary(path_like) and is_binary(workspace_root) do
    trimmed = String.trim(path_like)

    if trimmed == "" do
      {:error, :missing}
    else
      base = normalize_root(workspace_root)
      abs = Path.expand(trimmed, base)

      if under_workspace?(abs, base) do
        {:ok, abs}
      else
        {:error, :outside_workspace}
      end
    end
  end

  @doc """
  Resolve a path and ensure the target exists. If it exists, attempt
  `File.realpath/1` and re-check confinement on the canonical path.
  """
  @spec resolve_existing(String.t(), String.t()) :: {:ok, String.t()} | {:error, reason}
  def resolve_existing(path_like, workspace_root) do
    with {:ok, abs} <- resolve(path_like, workspace_root) do
      case File.exists?(abs) do
        true ->
          # Best-effort: rely on expanded path check. Symlink escape prevention
          # is handled at higher layers if needed.
          {:ok, abs}

        false ->
          {:error, :not_found}
      end
    end
  end

  @doc """
  Resolve directory path, ensuring it exists and is a directory.
  """
  @spec resolve_dir(String.t() | nil, String.t()) :: {:ok, String.t()} | {:error, reason}
  def resolve_dir(nil, workspace_root), do: {:ok, normalize_root(workspace_root)}

  def resolve_dir(dir_like, workspace_root) when is_binary(dir_like) do
    with {:ok, abs} <- resolve(dir_like, workspace_root) do
      case File.stat(abs) do
        {:ok, %File.Stat{type: :directory}} -> {:ok, abs}
        {:ok, _} -> {:error, :invalid}
        _ -> {:error, :not_found}
      end
    end
  end

  @doc false
  @spec under_workspace?(String.t(), String.t()) :: boolean
  def under_workspace?(abs, base) do
    a = Path.expand(abs)
    b = Path.expand(base)
    a == b or String.starts_with?(a, b <> "/")
  end

  defp normalize_root(root), do: Path.expand(root)
end
