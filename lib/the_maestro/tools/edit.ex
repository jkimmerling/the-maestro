defmodule TheMaestro.Tools.Edit do
  @moduledoc """
  Claude Code compatible Edit tool (replace) for a single file.

  JSON args (Anthropic):
    - file_path: absolute or relative path
    - old_string: exact text to find
    - new_string: replacement text
    - expected_replacements?: integer (default 1)
  """

  alias TheMaestro.Tools.{PathResolver, ExecOutput}

  @spec run(map(), keyword()) ::
          {:ok, String.t(), %{prev: String.t(), new: String.t(), path: String.t()}}
          | {:error, String.t()}
  def run(args, opts \\ []) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())

    with {:ok, path} <- resolve_path(args, base),
         {:ok, prev, exists?} <- read_if_exists(path),
         {:ok, newc} <- apply_edit(prev, exists?, args),
         {:ok, newc, _warns} <- maybe_filter_new_string(newc) do
      :ok = File.mkdir_p!(Path.dirname(path))
      :ok = File.write!(path, newc)

      summary =
        if exists?, do: "edit applied to #{rel(path, base)}", else: "created #{rel(path, base)}"

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

  defp apply_edit(prev, exists?, args) do
    old = Map.get(args, "old_string") || Map.get(args, :old_string) || ""
    new = Map.get(args, "new_string") || Map.get(args, :new_string) || ""
    replace_all = Map.get(args, "replace_all") || Map.get(args, :replace_all) || false

    cond do
      not is_binary(old) or not is_binary(new) ->
        {:error, "invalid edit arguments"}

      old == "" and exists? ->
        {:error, "attempt to create existing file"}

      old == "" and not exists? ->
        {:ok, new}

      prev == nil ->
        {:error, "file not found"}

      old == new ->
        {:error, "no change"}

      true ->
        occ = occurrences(prev, old)

        cond do
          occ == 0 -> {:error, "no occurrences found"}
          replace_all == true -> {:ok, String.replace(prev, old, new)}
          occ == 1 -> {:ok, String.replace(prev, old, new)}
          true -> {:error, "non-unique match without replace_all"}
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

  # no longer used (expected_replacements removed)

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
