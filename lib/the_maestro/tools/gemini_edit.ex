defmodule TheMaestro.Tools.GeminiEdit do
  @moduledoc """
  Gemini CLI compatible replace/edit tool using expected_replacements semantics.

  Args:
    - file_path: absolute or relative path within workspace
    - old_string: text to replace; empty string creates new file if file does not exist
    - new_string: replacement text
    - expected_replacements?: integer (default 1)
  """

  alias TheMaestro.Tools.{PathResolver, ExecOutput}

  @spec run(map(), keyword()) ::
          {:ok, String.t(), %{prev: String.t(), new: String.t(), path: String.t(), replacements: non_neg_integer()}}
          | {:error, String.t()}
  def run(args, opts \\ []) when is_map(args) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())

    with {:ok, path} <- resolve_path(args, base),
         {:ok, prev, exists?} <- read_if_exists(path),
         {:ok, newc, nrepl} <- apply_edit(prev, exists?, args) do
      :ok = File.mkdir_p!(Path.dirname(path))
      :ok = File.write!(path, newc)

      summary =
        if exists?, do: "Successfully modified file: #{rel(path, base)} (#{nrepl} replacements).", else: "Created new file: #{rel(path, base)} with provided content."

      payload = ExecOutput.format(summary, 0, 0.0)
      {:ok, payload, %{prev: prev || "", new: newc, path: path, replacements: nrepl}}
    end
  end

  def run(_, _), do: {:error, "invalid arguments"}

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
    expected =
      case Map.get(args, "expected_replacements") || Map.get(args, :expected_replacements) do
        i when is_integer(i) and i >= 1 -> i
        i when is_binary(i) ->
          case Integer.parse(i) do
            {n, _} when n >= 1 -> n
            _ -> 1
          end
        _ -> 1
      end

    cond do
      not is_binary(old) or not is_binary(new) ->
        {:error, "invalid edit arguments"}

      old == "" and exists? ->
        {:error, "Failed to edit. Attempted to create a file that already exists."}

      old == "" and expected > 1 ->
        {:error, "Failed to edit. Cannot perform multiple replacements with empty old_string."}

      old == "" and not exists? ->
        {:ok, new, 0}

      prev == nil ->
        {:error, "File not found. Cannot apply edit. Use an empty old_string to create a new file."}

      true ->
        occ = occurrences(prev, old)

        cond do
          occ == 0 ->
            {:error,
             "Failed to edit, could not find the string to replace."}

          expected != occ ->
            term = if expected == 1, do: "occurrence", else: "occurrences"
            {:error,
             "Failed to edit, expected #{expected} #{term} but found #{occ}."}

          old == new ->
            {:error,
             "No changes to apply. The old_string and new_string are identical."}

          true ->
            {:ok, replace_n(prev, old, new, expected), expected}
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

  defp replace_n(content, old, new, n) when n <= 0, do: content
  defp replace_n(content, old, new, n) do
    do_replace(content, old, new, n, 0)
  end

  defp do_replace(content, _old, _new, n, _i) when n <= 0, do: content
  defp do_replace(content, old, new, n, i) do
    case :binary.match(content, old, scope: {i, byte_size(content) - i}) do
      :nomatch -> content
      {pos, _len} ->
        head = binary_part(content, 0, pos)
        tail = binary_part(content, pos + byte_size(old), byte_size(content) - (pos + byte_size(old)))
        updated = head <> new <> tail
        # continue after the replacement to avoid infinite loops on overlapping patterns
        do_replace(updated, old, new, n - 1, pos + byte_size(new))
    end
  end

  defp rel(path, base) do
    case Path.relative_to(path, base) do
      ^path -> path
      r -> r
    end
  end
end

