defmodule TheMaestro.Tools.Glob do
  @moduledoc false
  alias TheMaestro.Tools.PathResolver

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())
    with {:ok, pattern} <- fetch_pattern(args),
         {:ok, base_dir} <- resolve_base_dir(args, base) do
      search = build_search(pattern, base, base_dir)
      matches =
        search
        |> Path.wildcard(match_dot: true)
        |> Enum.filter(&PathResolver.under_workspace?(&1, base))
        |> Enum.map(&Path.relative_to(&1, base))
      {:ok, Jason.encode!(%{"matches" => matches, "count" => length(matches)})}
    end
  end

  defp fetch_pattern(args) do
    case args["pattern"] || args[:pattern] do
      p when is_binary(p) ->
        if String.trim(p) != "", do: {:ok, p}, else: {:error, "missing pattern"}
      _ -> {:error, "missing pattern"}
    end
  end
  defp resolve_base_dir(args, base) do
    case PathResolver.resolve_dir(args["path"] || args[:path], base) do
      {:ok, dir} -> {:ok, dir}
      {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
      {:error, :not_found} -> {:error, "directory not found"}
      {:error, :invalid} -> {:error, "invalid directory"}
      _ -> {:error, "invalid arguments"}
    end
  end
  defp build_search(pattern, base, dir) do
    if Path.type(pattern) == :absolute do
      case PathResolver.resolve(pattern, base) do
        {:ok, abs} -> abs
        _ -> Path.join(dir, pattern)
      end
    else
      Path.join(dir, if(String.contains?(pattern, "/"), do: pattern, else: "**/" <> pattern))
    end
  end
end
