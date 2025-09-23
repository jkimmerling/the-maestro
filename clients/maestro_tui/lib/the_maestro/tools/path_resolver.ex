defmodule TheMaestro.Tools.PathResolver do
  @moduledoc false

  @type reason :: :missing | :invalid | :outside_workspace | :not_found

  @spec resolve(String.t(), String.t()) :: {:ok, String.t()} | {:error, reason}
  def resolve(path_like, root) when is_binary(path_like) and is_binary(root) do
    p = String.trim(path_like)
    if p == "" do
      {:error, :missing}
    else
      base = Path.expand(root)
      abs = Path.expand(p, base)
      if under_workspace?(abs, base), do: {:ok, abs}, else: {:error, :outside_workspace}
    end
  end

  @spec resolve_existing(String.t(), String.t()) :: {:ok, String.t()} | {:error, reason}
  def resolve_existing(path_like, root) do
    with {:ok, abs} <- resolve(path_like, root) do
      if File.exists?(abs), do: {:ok, abs}, else: {:error, :not_found}
    end
  end

  @spec resolve_dir(String.t() | nil, String.t()) :: {:ok, String.t()} | {:error, reason}
  def resolve_dir(nil, root), do: {:ok, Path.expand(root)}
  def resolve_dir(dir_like, root) when is_binary(dir_like) do
    with {:ok, abs} <- resolve(dir_like, root) do
      case File.stat(abs) do
        {:ok, %File.Stat{type: :directory}} -> {:ok, abs}
        {:ok, _} -> {:error, :invalid}
        _ -> {:error, :not_found}
      end
    end
  end

  @spec under_workspace?(String.t(), String.t()) :: boolean
  def under_workspace?(abs, base) do
    a = Path.expand(abs)
    b = Path.expand(base)
    a == b or String.starts_with?(a, b <> "/")
  end
end

