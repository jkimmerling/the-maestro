defmodule TheMaestro.Tools.MultiEdit do
  @moduledoc """
  Multiple replacements in a single file.

  Args:
    - file_path: path
    - edits/replacements: list of %{old_string, new_string, expected_replacements?}
  """

  alias TheMaestro.Tools.{PathResolver, ExecOutput}

  @spec run(map(), keyword()) ::
          {:ok, String.t(), %{prev: String.t(), new: String.t(), path: String.t()}}
          | {:error, String.t()}
  def run(args, opts \\ []) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())

    with {:ok, path} <- resolve_path(args, base),
         {:ok, prev, exists?} <- read_if_exists(path),
         {:ok, newc} <- apply_multi(prev, exists?, args) do
      :ok = File.mkdir_p!(Path.dirname(path))
      :ok = File.write!(path, newc)

      summary =
        if exists?,
          do: "multi_edit applied to #{rel(path, base)}",
          else: "created #{rel(path, base)}"

      payload = ExecOutput.format(summary, 0, 0.0)
      {:ok, payload, %{prev: prev || "", new: newc, path: path}}
    end
  end

  defp resolve_path(args, base) do
    case Map.get(args, "file_path") || Map.get(args, :file_path) do
      p when is_binary(p) ->
        case PathResolver.resolve(p, base) do
          {:ok, abs} -> {:ok, abs}
          {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
          _ -> {:error, "invalid file_path"}
        end

      _ ->
        {:error, "missing file_path"}
    end
  end

  defp read_if_exists(path) do
    case File.read(path) do
      {:ok, bin} -> {:ok, bin, true}
      {:error, :enoent} -> {:ok, nil, false}
      {:error, r} -> {:error, to_string(r)}
    end
  end

  defp apply_multi(prev, exists?, args) do
    edits = Map.get(args, "edits") || Map.get(args, :edits) || []
    edits = Enum.map(edits, &normalize_edit/1)

    cond do
      not is_list(edits) or edits == [] ->
        {:error, "missing edits"}

      prev == nil and exists? == false and Enum.any?(edits, &(&1.old != "")) ->
        {:error, "file not found"}

      true ->
        content = prev || ""

        {content2, ok} =
          Enum.reduce(edits, {content, :ok}, fn e, {acc, status} ->
            if status != :ok, do: {acc, status}, else: do_apply(acc, exists?, e)
          end)

        case ok do
          :ok -> {:ok, content2}
          {:error, r} -> {:error, r}
        end
    end
  end

  defp normalize_edit(%{"old_string" => o, "new_string" => n} = m),
    do: %{old: o || "", new: n || "", all: m["replace_all"] || false}

  defp normalize_edit(%{old_string: o, new_string: n} = m),
    do: %{old: o || "", new: n || "", all: m[:replace_all] || false}

  defp normalize_edit(other), do: other

  defp do_apply(acc, exists?, %{old: old, new: new, all: replace_all}) do
    cond do
      not is_binary(old) or not is_binary(new) ->
        {acc, {:error, "invalid edit arguments"}}

      old == "" and exists? and acc != "" ->
        {acc, {:error, "attempt to create existing file"}}

      old == "" and acc == "" and not exists? ->
        case maybe_filter_new_string(new) do
          {:ok, newf, _} -> {newf, :ok}
          {:error, r} -> {acc, {:error, r}}
        end

      true ->
        occ = occurrences(acc, old)

        cond do
          occ == 0 -> {acc, {:error, "no occurrences found"}}
          old == new -> {acc, {:error, "no change"}}
          replace_all == true ->
            case maybe_filter_new_string(new) do
              {:ok, newf, _} -> {String.replace(acc, old, newf), :ok}
              {:error, r} -> {acc, {:error, r}}
            end
          occ == 1 ->
            case maybe_filter_new_string(new) do
              {:ok, newf, _} -> {String.replace(acc, old, newf), :ok}
              {:error, r} -> {acc, {:error, r}}
            end
          true -> {acc, {:error, "non-unique match without replace_all"}}
        end
    end
  end

  defp occurrences(content, sub) do
    do_count(content, sub, 0, 0)
  end

  defp do_count(_c, _s, _i, n) when _s == "", do: n

  defp do_count(c, s, i, n) do
    case :binary.match(c, s, scope: {i, byte_size(c) - i}) do
      :nomatch -> n
      {pos, _len} -> do_count(c, s, pos + byte_size(s), n + 1)
    end
  end

  # no longer used

  defp rel(path, base) do
    case Path.relative_to(path, base) do
      ^path -> path
      r -> r
    end
  end

  defp maybe_filter_new_string(text) do
    mode = TheMaestro.Tools.Filters.EmojiFilter.mode_from_env()
    TheMaestro.Tools.Filters.EmojiFilter.filter(text, mode)
  end
end
