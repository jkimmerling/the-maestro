defmodule TheMaestro.Tools.Edit do
  @moduledoc """
  Claude Code compatible Edit tool (replace) for a single file.

  JSON args (Anthropic):
    - file_path: absolute or relative path
    - old_string: exact text to find
    - new_string: replacement text
    - expected_replacements?: integer (default 1)
  """

  alias TheMaestro.Tools.{ExecOutput, PathResolver}
  alias TheMaestro.Tools.Filters.EmojiFilter

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
    with {:ok, old, new, replace_all?} <- fetch_edit_strings(args),
         :ok <- validate_creation(old, exists?) do
      src_result = if old == "", do: {:ok, ""}, else: ensure_source(prev)

      with {:ok, source} <- src_result,
           :ok <- validate_change(old, new),
           :ok <- validate_occurrences(source, old, replace_all?) do
        {:ok, apply_replacement(source, old, new, replace_all?)}
      end
    end
  end

  defp fetch_edit_strings(args) do
    old = Map.get(args, "old_string") || Map.get(args, :old_string) || ""
    new = Map.get(args, "new_string") || Map.get(args, :new_string) || ""
    replace_all? = Map.get(args, "replace_all") || Map.get(args, :replace_all) || false

    if is_binary(old) and is_binary(new) do
      {:ok, old, new, replace_all?}
    else
      {:error, "invalid edit arguments"}
    end
  end

  defp validate_creation("", true), do: {:error, "attempt to create existing file"}
  defp validate_creation("", false), do: :ok
  defp validate_creation(_old, _exists?), do: :ok

  defp ensure_source(nil), do: {:error, "file not found"}
  defp ensure_source(content), do: {:ok, content}

  defp validate_change(old, new) when old == new, do: {:error, "no change"}
  defp validate_change(_old, _new), do: :ok

  defp validate_occurrences(_content, "", _replace_all), do: :ok

  defp validate_occurrences(content, old, replace_all?) do
    case occurrences(content, old) do
      0 -> {:error, "no occurrences found"}
      1 -> :ok
      _count when replace_all? -> :ok
      _ -> {:error, "non-unique match without replace_all"}
    end
  end

  defp apply_replacement(_content, "", new, _replace_all?), do: new
  defp apply_replacement(content, old, new, true), do: String.replace(content, old, new)
  defp apply_replacement(content, old, new, false), do: String.replace(content, old, new)

  defp occurrences(content, sub) do
    do_count(content, sub, 0, 0)
  end

  defp do_count(_c, s, _i, n) when s == "", do: n

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
    mode = EmojiFilter.mode_from_env()
    EmojiFilter.filter(text, mode)
  end
end
