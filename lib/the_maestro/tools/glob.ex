defmodule TheMaestro.Tools.Glob do
  @moduledoc """
  Glob files relative to a path.
  """

  alias TheMaestro.Tools.PathResolver

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ []) when is_map(args) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())
    pattern = Map.get(args, "pattern") || Map.get(args, :pattern)
    path_like = Map.get(args, "path") || Map.get(args, :path)

    cond do
      !is_binary(pattern) or String.trim(pattern) == "" ->
        {:error, "missing pattern"}

      true ->
        case PathResolver.resolve_dir(path_like, base) do
          {:ok, base_path} ->
            combined =
              if Path.type(pattern) == :absolute do
                case PathResolver.resolve(pattern, base) do
                  {:ok, abs} -> abs
                  _ -> Path.join(base_path, pattern)
                end
              else
                Path.join(base_path, pattern)
              end

            recursive =
              if String.contains?(pattern, "/"),
                do: combined,
                else: Path.join(base_path, "**/" <> pattern)

            matches = Path.wildcard(recursive, match_dot: true)

            rel =
              matches
              |> Enum.filter(&PathResolver.under_workspace?(&1, base))
              |> Enum.map(&Path.relative_to(&1, base))

            {:ok, Jason.encode!(%{"matches" => rel, "count" => length(rel)})}

          {:error, :outside_workspace} ->
            {:error, "requested path outside workspace"}

          {:error, :not_found} ->
            {:error, "directory not found"}

          {:error, :invalid} ->
            {:error, "invalid directory"}

          _ ->
            {:error, "invalid arguments"}
        end
    end
  end

  def run(_, _), do: {:error, "invalid arguments"}
end
