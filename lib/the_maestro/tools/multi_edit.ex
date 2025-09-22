defmodule TheMaestro.Tools.MultiEdit do
  @moduledoc """
  Multiple replacements in a single file.

  Args:
    - file_path: path
    - edits/replacements: list of %{old_string, new_string, expected_replacements?}
  """

  alias TheMaestro.Tools.{ExecOutput, PathResolver}
  alias TheMaestro.Tools.Filters.EmojiFilter

  @type edit_map :: %{old: String.t(), new: String.t(), replace_all?: boolean()}

  @spec run(map(), keyword()) ::
          {:ok, String.t(), %{prev: String.t(), new: String.t(), path: String.t()}}
          | {:error, String.t()}
  def run(args, opts \\ []) do
    base_cwd = Keyword.get(opts, :base_cwd, File.cwd!())

    with {:ok, path} <- resolve_path(args, base_cwd),
         {:ok, prev, exists?} <- read_if_exists(path),
         {:ok, content} <- apply_multi(prev || "", exists?, args) do
      persist_changes(path, content)
      {:ok, build_payload(path, base_cwd, exists?), %{prev: prev || "", new: content, path: path}}
    end
  end

  # ===== Path + IO helpers =====

  defp resolve_path(args, base) do
    args
    |> fetch_path()
    |> case do
      {:ok, relative} -> do_resolve_path(relative, base)
      error -> error
    end
  end

  defp fetch_path(args) do
    args
    |> Map.get("file_path")
    |> Kernel.||(Map.get(args, :file_path))
    |> case do
      path when is_binary(path) and path != "" -> {:ok, path}
      _ -> {:error, "missing file_path"}
    end
  end

  defp do_resolve_path(path, base) do
    case PathResolver.resolve(path, base) do
      {:ok, abs} -> {:ok, abs}
      {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
      _ -> {:error, "invalid file_path"}
    end
  end

  defp read_if_exists(path) do
    case File.read(path) do
      {:ok, bin} -> {:ok, bin, true}
      {:error, :enoent} -> {:ok, nil, false}
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  defp persist_changes(path, content) do
    :ok = File.mkdir_p!(Path.dirname(path))
    :ok = File.write!(path, content)
  end

  defp build_payload(path, base, exists?) do
    summary =
      if exists?,
        do: "multi_edit applied to #{rel(path, base)}",
        else: "created #{rel(path, base)}"

    ExecOutput.format(summary, 0, 0.0)
  end

  defp rel(path, base) do
    case Path.relative_to(path, base) do
      ^path -> path
      relative -> relative
    end
  end

  # ===== Edit application =====

  defp apply_multi(content, exists?, args) do
    with {:ok, edits} <- fetch_edits(args),
         :ok <- ensure_editable_file(content, exists?, edits),
         {:ok, updated} <- apply_edits(content, exists?, edits) do
      {:ok, updated}
    end
  end

  defp fetch_edits(args) do
    edits = Map.get(args, "edits") || Map.get(args, :edits) || []

    if not is_list(edits) or edits == [] do
      {:error, "missing edits"}
    else
      normalize_edits(edits)
    end
  end

  defp normalize_edits(raw_edits) do
    raw_edits
    |> Enum.map(&normalize_edit/1)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, edit}, {:ok, acc} -> {:cont, {:ok, [edit | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, edits} -> {:ok, Enum.reverse(edits)}
      other -> other
    end
  end

  defp normalize_edit(%{"old_string" => old, "new_string" => new} = edit) do
    {:ok, build_edit(old, new, Map.get(edit, "replace_all"))}
  end

  defp normalize_edit(%{old_string: old, new_string: new} = edit) do
    {:ok, build_edit(old, new, Map.get(edit, :replace_all))}
  end

  defp normalize_edit(_), do: {:error, "invalid edits"}

  defp build_edit(old, new, replace_all) do
    %{
      old: to_string(old || ""),
      new: to_string(new || ""),
      replace_all?: truthy?(replace_all)
    }
  end

  defp ensure_editable_file(_content, true, _edits), do: :ok

  defp ensure_editable_file("", false, edits) do
    if Enum.any?(edits, &(&1.old != "")) do
      {:error, "file not found"}
    else
      :ok
    end
  end

  defp ensure_editable_file(_content, false, _edits), do: :ok

  defp apply_edits(content, exists?, edits) do
    edits
    |> Enum.reduce_while({:ok, content}, fn edit, {:ok, acc} ->
      case apply_edit(acc, exists?, edit) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_edit(content, exists?, %{old: ""} = edit) do
    maybe_write_new_file(content, exists?, edit.new)
  end

  defp apply_edit(content, _exists?, %{old: old, new: new} = edit) do
    cond do
      not is_binary(old) or not is_binary(new) -> {:error, "invalid edit arguments"}
      old == new -> {:error, "no change"}
      edit.replace_all? -> replace_all(content, old, new)
      true -> replace_single(content, old, new)
    end
  end

  defp maybe_write_new_file(_content, true, _new), do: {:error, "attempt to create existing file"}

  defp maybe_write_new_file("", false, new) do
    filter_new_string(new)
  end

  defp maybe_write_new_file(_content, false, _new),
    do: {:error, "attempt to create existing file"}

  defp replace_all(content, old, new) do
    with :ok <- ensure_occurrences(content, old, :at_least_one),
         {:ok, filtered} <- filter_new_string(new) do
      {:ok, String.replace(content, old, filtered)}
    end
  end

  defp replace_single(content, old, new) do
    with :ok <- ensure_occurrences(content, old, :exactly_one),
         {:ok, filtered} <- filter_new_string(new) do
      {:ok, String.replace(content, old, filtered)}
    end
  end

  defp ensure_occurrences(content, old, expectation) do
    case occurrences(content, old) do
      0 -> {:error, "no occurrences found"}
      1 -> validate_occurrence_count(expectation, 1)
      count -> validate_occurrence_count(expectation, count)
    end
  end

  defp validate_occurrence_count(:exactly_one, 1), do: :ok

  defp validate_occurrence_count(:exactly_one, _count),
    do: {:error, "non-unique match without replace_all"}

  defp validate_occurrence_count(:at_least_one, _count), do: :ok

  defp occurrences(content, sub) do
    count_occurrences(content, sub, 0, 0)
  end

  defp count_occurrences(_content, sub, _index, tally) when sub == "", do: tally

  defp count_occurrences(content, sub, index, tally) do
    case :binary.match(content, sub, scope: {index, byte_size(content) - index}) do
      :nomatch -> tally
      {pos, _len} -> count_occurrences(content, sub, pos + byte_size(sub), tally + 1)
    end
  end

  defp filter_new_string(text) do
    mode = EmojiFilter.mode_from_env()

    case EmojiFilter.filter(text, mode) do
      {:ok, filtered, _metadata} -> {:ok, filtered}
      {:error, reason} -> {:error, reason}
    end
  end

  defp truthy?(value), do: value in [true, "true", 1, "1"]
end
