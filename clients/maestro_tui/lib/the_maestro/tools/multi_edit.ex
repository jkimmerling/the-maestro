defmodule TheMaestro.Tools.MultiEdit do
  @moduledoc false
  alias TheMaestro.Tools.{ExecOutput, PathResolver}

  @spec run(map(), keyword()) :: {:ok, String.t(), %{prev: String.t(), new: String.t(), path: String.t()}} | {:error, String.t()}
  def run(args, opts) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())
    with {:ok, path} <- resolve_path(args, base),
         {:ok, prev, exists?} <- read_if_exists(path),
         {:ok, content} <- apply_multi(prev || "", exists?, args) do
      :ok = File.mkdir_p(Path.dirname(path))
      :ok = File.write(path, content)
      payload = ExecOutput.format(if(exists?, do: "multi_edit applied", else: "created"), 0, 0.0)
      {:ok, payload, %{prev: prev || "", new: content, path: path}}
    end
  end

  defp resolve_path(args, base) do
    case args["file_path"] || args[:file_path] do
      p when is_binary(p) -> case PathResolver.resolve(p, base) do {:ok, abs} -> {:ok, abs}; {:error, :outside_workspace} -> {:error, "requested path outside workspace"}; _ -> {:error, "invalid file_path"} end
      _ -> {:error, "missing file_path"}
    end
  end
  defp read_if_exists(path) do
    case File.read(path) do {:ok, bin} -> {:ok, bin, true}; {:error, :enoent} -> {:ok, nil, false}; {:error, r} -> {:error, to_string(r)} end
  end

  defp apply_multi(content, exists?, args) do
    with {:ok, edits} <- fetch_edits(args),
         :ok <- ensure_editable(content, exists?, edits),
         {:ok, updated} <- do_apply(content, exists?, edits) do
      {:ok, updated}
    end
  end
  defp fetch_edits(args) do
    e = args["edits"] || args[:edits] || []
    if is_list(e) and e != [], do: normalize_edits(e), else: {:error, "missing edits"}
  end
  defp normalize_edits(list) do
    list
    |> Enum.map(fn
      %{"old_string" => o, "new_string" => n} = m -> {:ok, %{old: to_string(o || ""), new: to_string(n || ""), replace_all?: m["replace_all"] || false}}
      %{old_string: o, new_string: n} = m -> {:ok, %{old: to_string(o || ""), new: to_string(n || ""), replace_all?: m[:replace_all] || false}}
      _ -> {:error, "invalid edits"}
    end)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, e}, {:ok, acc} -> {:cont, {:ok, [e | acc]}}
      {:error, r}, _ -> {:halt, {:error, r}}
    end)
    |> case do {:ok, l} -> {:ok, Enum.reverse(l)}; other -> other end
  end
  defp ensure_editable(_c, true, _), do: :ok
  defp ensure_editable("", false, edits) do
    if Enum.any?(edits, &(&1.old != "")), do: {:error, "file not found"}, else: :ok
  end
  defp ensure_editable(_c, false, _), do: :ok
  defp do_apply(content, exists?, edits) do
    Enum.reduce_while(edits, {:ok, content}, fn e, {:ok, acc} ->
      case apply_one(acc, exists?, e) do {:ok, upd} -> {:cont, {:ok, upd}}; {:error, r} -> {:halt, {:error, r}} end
    end)
  end
  defp apply_one(content, exists?, %{old: ""} = e), do: maybe_write_new(content, exists?, e.new)
  defp apply_one(content, _exists?, %{old: o, new: n, replace_all?: all?}) do
    cond do
      not is_binary(o) or not is_binary(n) -> {:error, "invalid edit arguments"}
      o == n -> {:error, "no change"}
      all? -> replace_all(content, o, n)
      true -> replace_single(content, o, n)
    end
  end
  defp maybe_write_new(_c, true, _n), do: {:error, "attempt to create existing file"}
  defp maybe_write_new("", false, n), do: {:ok, n}
  defp maybe_write_new(_c, false, _n), do: {:error, "attempt to create existing file"}
  defp replace_all(c, o, n) do
    with :ok <- ensure_occ(c, o, :at_least_one) do
      {:ok, String.replace(c, o, n)}
    end
  end
  defp replace_single(c, o, n) do
    with :ok <- ensure_occ(c, o, :exactly_one) do
      {:ok, String.replace(c, o, n)}
    end
  end
  defp ensure_occ(c, o, exp) do
    cnt = occ(c, o)
    cond do
      cnt == 0 -> {:error, "no occurrences found"}
      exp == :exactly_one and cnt != 1 -> {:error, "non-unique match without replace_all"}
      true -> :ok
    end
  end
  defp occ(c, s), do: count(c, s, 0, 0)
  defp count(_c, s, _i, n) when s == "", do: n
  defp count(c, s, i, n) do
    case :binary.match(c, s, scope: {i, byte_size(c) - i}) do
      :nomatch -> n
      {pos, _} -> count(c, s, pos + byte_size(s), n + 1)
    end
  end
end
