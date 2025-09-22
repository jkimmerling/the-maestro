defmodule TheMaestro.Tools.Glob do
  @moduledoc """
  Glob files relative to a path.
  """

  alias TheMaestro.Tools.PathResolver

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ [])

  def run(args, opts) when is_map(args) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())

    with {:ok, pattern} <- fetch_pattern(args),
         {:ok, base_dir} <- resolve_base_dir(args, base),
         search_path <- build_search_path(pattern, base, base_dir),
         matches <- find_matches(search_path, base) do
      {:ok, Jason.encode!(%{"matches" => matches, "count" => length(matches)})}
    end
  end

  def run(_, _), do: {:error, "invalid arguments"}

  defp fetch_pattern(args) do
    pattern = Map.get(args, "pattern") || Map.get(args, :pattern)

    case pattern do
      value when is_binary(value) ->
        if String.trim(value) != "" do
          {:ok, value}
        else
          {:error, "missing pattern"}
        end

      _ ->
        {:error, "missing pattern"}
    end
  end

  defp resolve_base_dir(args, base) do
    path_like = Map.get(args, "path") || Map.get(args, :path)

    case PathResolver.resolve_dir(path_like, base) do
      {:ok, base_path} -> {:ok, base_path}
      {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
      {:error, :not_found} -> {:error, "directory not found"}
      {:error, :invalid} -> {:error, "invalid directory"}
      _ -> {:error, "invalid arguments"}
    end
  end

  defp build_search_path(pattern, base, base_dir) do
    pattern_path(pattern, base, base_dir)
    |> maybe_expand_glob(base_dir, pattern)
  end

  defp pattern_path(pattern, base, base_dir) do
    if Path.type(pattern) == :absolute do
      case PathResolver.resolve(pattern, base) do
        {:ok, abs} -> abs
        _ -> Path.join(base_dir, pattern)
      end
    else
      Path.join(base_dir, pattern)
    end
  end

  defp maybe_expand_glob(resolved, base_dir, pattern) do
    if String.contains?(pattern, "/") do
      resolved
    else
      Path.join(base_dir, "**/" <> pattern)
    end
  end

  defp find_matches(search_path, base) do
    search_path
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&PathResolver.under_workspace?(&1, base))
    |> Enum.map(&Path.relative_to(&1, base))
  end
end
