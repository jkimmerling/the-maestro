defmodule TheMaestro.Tools.Edit do
  @moduledoc false
  alias TheMaestro.Tools.{ExecOutput, PathResolver}

  @spec run(map(), keyword()) :: {:ok, String.t(), %{prev: String.t(), new: String.t(), path: String.t()}} | {:error, String.t()}
  def run(args, opts) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())
    with {:ok, path} <- resolve_path(args, base),
         {:ok, prev, exists?} <- read_if_exists(path),
         {:ok, newc} <- apply_edit(prev, exists?, args) do
      :ok = File.mkdir_p(Path.dirname(path))
      :ok = File.write(path, newc)
      summary = if exists?, do: "edit applied", else: "created"
      payload = ExecOutput.format(summary, 0, 0.0)
      {:ok, payload, %{prev: prev || "", new: newc, path: path}}
    end
  end

  defp resolve_path(args, base) do
    case args["file_path"] || args[:file_path] do
      p when is_binary(p) ->
        case PathResolver.resolve(p, base) do
          {:ok, abs} -> {:ok, abs}
          {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
          _ -> {:error, "invalid file_path"}
        end
      _ -> {:error, "missing file_path"}
    end
  end

  defp read_if_exists(path) do
    case File.read(path) do
      {:ok, bin} -> {:ok, bin, true}
      {:error, :enoent} -> {:ok, nil, false}
      {:error, r} -> {:error, to_string(r)}
    end
  end

  defp apply_edit(prev, exists?, args) do
    old = args["old_string"] || args[:old_string] || ""
    new = args["new_string"] || args[:new_string] || ""
    replace_all? = args["replace_all"] || args[:replace_all] || false
    if not (is_binary(old) and is_binary(new)), do: {:error, "invalid edit arguments"}, else: :ok
    src = if old == "", do: "", else: ensure_source(prev)
    with :ok <- validate_creation(old, exists?),
         {:ok, source} <- src,
         :ok <- validate_change(old, new),
         :ok <- validate_occurrences(source, old, replace_all?) do
      {:ok, do_replace(source, old, new, replace_all?)}
    end
  end

  defp validate_creation("", true), do: {:error, "attempt to create existing file"}
  defp validate_creation(_, _), do: :ok
  defp ensure_source(nil), do: {:error, "file not found"}
  defp ensure_source(c), do: {:ok, c}
  defp validate_change(o, n) when o == n, do: {:error, "no change"}
  defp validate_change(_, _), do: :ok

  defp validate_occurrences(_c, "", _), do: :ok
  defp validate_occurrences(c, o, replace_all?) do
    cnt = occurrences(c, o)
    cond do
      cnt == 0 -> {:error, "no occurrences found"}
      cnt == 1 -> :ok
      replace_all? -> :ok
      true -> {:error, "non-unique match without replace_all"}
    end
  end

  defp do_replace(_c, "", n, _), do: n
  defp do_replace(c, o, n, true), do: String.replace(c, o, n)
  defp do_replace(c, o, n, false), do: String.replace(c, o, n)

  defp occurrences(content, sub), do: count_occ(content, sub, 0, 0)
  defp count_occ(_c, s, _i, n) when s == "", do: n
  defp count_occ(c, s, i, n) do
    case :binary.match(c, s, scope: {i, byte_size(c) - i}) do
      :nomatch -> n
      {pos, _} -> count_occ(c, s, pos + byte_size(s), n + 1)
    end
  end
end
