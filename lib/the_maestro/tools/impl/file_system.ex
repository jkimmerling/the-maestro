defmodule TheMaestro.Tools.Impl.FileSystem do
  @moduledoc """
  File system tool implementations.
  """

  @spec list_directory(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def list_directory(root, opts) do
    path = Path.expand(Path.join(root, Keyword.get(opts, :path, ".")))

    with :ok <- ensure_within(root, path),
         {:ok, entries} <- do_ls(path) do
      {:ok, Enum.join(entries, "\n")}
    end
  end

  defp do_ls(path) do
    with {:ok, list} <- File.ls(path) do
      details =
        Enum.map(list, fn name ->
          full = Path.join(path, name)
          if File.dir?(full), do: name <> "/", else: name
        end)

      {:ok, details}
    end
  end

  @spec read_file(String.t(), keyword()) ::
          {:ok, %{text: String.t()} | %{inline_data: map()}} | {:error, term()}
  def read_file(root, opts) do
    abs = Path.expand(Keyword.get(opts, :absolute_path) || Path.join(root, ""))

    with :ok <- ensure_within(root, abs),
         {:ok, bin} <- File.read(abs) do
      if binary_text?(bin) do
        offset = Keyword.get(opts, :offset, 0) || 0
        limit = Keyword.get(opts, :limit)
        text = slice_text(bin, offset, limit)
        {:ok, %{text: text}}
      else
        {:ok, %{inline_data: %{media_type: "application/octet-stream", bytes: byte_size(bin)}}}
      end
    end
  end

  @spec write_file(String.t(), keyword()) ::
          {:ok, String.t(), non_neg_integer()} | {:error, term()}
  def write_file(root, opts) do
    path = Path.expand(Path.join(root, Keyword.get(opts, :file_path, "")))
    content = Keyword.get(opts, :content, "")

    with :ok <- ensure_within(root, path),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, content) do
      {:ok, path, byte_size(content)}
    end
  end

  @spec replace(String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def replace(root, opts) do
    path = Path.expand(Path.join(root, Keyword.get(opts, :file_path, "")))
    old = Keyword.get(opts, :old_string, "")
    new = Keyword.get(opts, :new_string, "")
    expected = Keyword.get(opts, :expected_replacements)

    with :ok <- ensure_within(root, path),
         {:ok, text} <- File.read(path) do
      {new_text, count} =
        :binary.replace(text, old, new, [:global, :scope])
        |> count_replacements(text, old, new)

      if expected && count != expected do
        {:error, {:unexpected_replacements, count}}
      else
        :ok = File.write(path, new_text)
        {:ok, count}
      end
    end
  end

  defp count_replacements(result, old_text, old, new) do
    # Compute count by difference; conservative when equal strings
    if old == new, do: {result, 0}, else: {result, occurrences(old_text, old)}
  end

  defp occurrences(text, pattern) do
    Regex.scan(~r/#{Regex.escape(pattern)}/, text) |> length()
  end

  @spec glob(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def glob(root, opts) do
    pattern = Keyword.get(opts, :pattern, "*")
    base = Path.expand(Path.join(root, Keyword.get(opts, :path, ".")))

    with :ok <- ensure_within(root, base) do
      files = Path.wildcard(Path.join(base, pattern))
      {:ok, Enum.map(files, &Path.relative_to(&1, root))}
    end
  end

  @spec search_file_content(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def search_file_content(root, opts) do
    pattern = Keyword.get(opts, :pattern, "")
    path = Path.expand(Path.join(root, Keyword.get(opts, :path, ".")))

    with :ok <- ensure_within(root, path) do
      files = if File.dir?(path), do: Path.wildcard(Path.join(path, "**/*")), else: [path]
      re = Regex.compile!(pattern)

      results =
        files
        |> Enum.filter(&File.regular?/1)
        |> Enum.flat_map(&match_lines(&1, re, root))

      {:ok, Enum.join(results, "\n")}
    end
  end

  defp match_lines(file, re, root) do
    case File.read(file) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _i} -> Regex.match?(re, line) end)
        |> Enum.map(fn {line, i} -> "#{Path.relative_to(file, root)}:#{i}:#{line}" end)

      _ ->
        []
    end
  end

  defp ensure_within(root, path) do
    root = Path.expand(root)
    path = Path.expand(path)
    if String.starts_with?(path, root), do: :ok, else: {:error, :outside_root}
  end

  defp binary_text?(bin) do
    String.valid?(bin)
  end

  defp slice_text(text, offset, nil) do
    off = max(offset, 0)

    if off >= String.length(text),
      do: "",
      else: String.slice(text, off, String.length(text) - off)
  end

  defp slice_text(text, offset, limit) when is_integer(limit) and limit >= 0 do
    off = max(offset, 0)
    if off >= String.length(text), do: "", else: String.slice(text, off, limit)
  end
end
