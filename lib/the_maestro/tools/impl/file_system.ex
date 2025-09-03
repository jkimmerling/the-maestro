defmodule TheMaestro.Tools.Impl.FileSystem do
  @moduledoc "File-system tools: list_directory, read_file, glob, search_file_content."
  alias TheMaestro.Tools.{TokenEstimator, Util}

  @default_token_cap 100_000

  @spec list_directory(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def list_directory(root, opts) do
    path = Keyword.fetch!(opts, :path)
    case Util.safe_expand(root, path) do
      {:ok, abs} -> list_dir_abs(abs)
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_dir_abs(abs) do
    if File.dir?(abs), do: {:ok, format_dir(abs)}, else: {:error, :not_a_directory}
  end

  defp format_dir(abs) do
    entries = File.ls!(abs)
    data =
      entries
      |> Enum.map(fn e -> {e, File.dir?(Path.join(abs, e))} end)
      |> Enum.sort_by(fn {name, is_dir} -> {is_dir && 0 || 1, String.downcase(name)} end)
      |> Enum.map(fn {name, is_dir} -> (if is_dir, do: "[DIR] ", else: "") <> name end)
      |> Enum.join("\n")
    "Directory listing for #{abs}\n" <> data
  end

  @spec read_file(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def read_file(root, opts) do
    path = Keyword.fetch!(opts, :absolute_path)
    offset = Keyword.get(opts, :offset)
    limit = Keyword.get(opts, :limit)
    token_cap = Keyword.get(opts, :token_cap, @default_token_cap)

    cond do
      not Util.within_root?(root, path) -> {:error, :outside_root_or_not_regular}
      not File.regular?(path) -> {:error, :outside_root_or_not_regular}
      true ->
        case classify_file(path) do
          :text -> {:ok, %{text: read_text_slice(path, offset, limit, token_cap)}}
          :inline -> {:ok, %{inline_data: inline_data(path)}}
          :binary -> {:ok, %{text: "Cannot display content of binary file: #{path}"}}
        end
    end
  end

  defp read_text_slice(path, nil, nil, token_cap) do
    {:ok, content} = File.read(path)
    TokenEstimator.clamp_to_tokens(content, token_cap)
  end

  defp read_text_slice(path, offset, limit, token_cap) when is_integer(offset) and is_integer(limit) do
    lines = path |> File.stream!() |> Enum.to_list()
    slice = lines |> Enum.slice(offset, limit) |> Enum.join("")
    msg = "[File content truncated: showing lines #{offset + 1}-#{offset + limit} of #{length(lines)} total lines...]\n"
    msg <> TokenEstimator.clamp_to_tokens(slice, token_cap)
  end

  defp inline_data(path) do
    ext = String.downcase(Path.extname(path))
    mime = mime_for_ext(ext)
    {:ok, bin} = File.read(path)
    %{inlineData: %{mimeType: mime, data: Base.encode64(bin)}}
  end

  defp mime_for_ext(ext) do
    %{
      ".png" => "image/png",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".gif" => "image/gif",
      ".webp" => "image/webp",
      ".svg" => "image/svg+xml",
      ".bmp" => "image/bmp",
      ".pdf" => "application/pdf"
    }
    |> Map.get(ext, "application/octet-stream")
  end

  @spec glob(binary(), keyword()) :: {:ok, [binary()]} | {:error, term()}
  def glob(root, opts) do
    pattern = Keyword.fetch!(opts, :pattern)
    base = Path.expand(Keyword.get(opts, :path, root))

    if String.starts_with?(base, Path.expand(root)) do
      files = Path.wildcard(Path.join(base, pattern))
      sorted = (files
        |> Enum.map(&Path.expand/1)
        |> Enum.sort_by(fn p -> (File.stat(p) |> elem(1)).mtime end, :desc))
      {:ok, sorted}
    else
      {:error, :outside_root}
    end
  end

  @spec search_file_content(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def search_file_content(root, opts) do
    pattern = Keyword.fetch!(opts, :pattern)
    base = Path.expand(Keyword.get(opts, :path, root))
    include = Keyword.get(opts, :include)

    if String.starts_with?(base, Path.expand(root)) do
      do_search(base, pattern, include)
    else
      {:error, :outside_root}
    end
  end

  defp do_search(base, pattern, include) do
    cond do
      git_repo?(base) and cmd?("git") -> git_grep(base, pattern, include)
      cmd?("rg") -> ripgrep(base, pattern, include)
      true -> scan_with_elixir(base, pattern, include)
    end
  end

  defp git_repo?(base), do: File.exists?(Path.join(base, ".git"))
  defp cmd?(exe), do: System.find_executable(exe) != nil

  defp git_grep(base, pattern, include) do
    args = ["-n", "-E", pattern]
    args = if include, do: args ++ [include], else: args
    {out, _} = System.cmd("git", ["-C", base, "grep" | args], stderr_to_stdout: true)
    {:ok, format_search_output(base, out)}
  end

  defp ripgrep(base, pattern, include) do
    args = ["-n", pattern]
    args = if include, do: args ++ [include], else: args ++ [base]
    {out, _} = System.cmd("rg", args, cd: base, stderr_to_stdout: true)
    {:ok, format_search_output(base, out)}
  end

  defp scan_with_elixir(base, pattern, include) do
    regex = Regex.compile!(pattern)
    files = collect_files(base, include)

    lines =
      for f <- files,
          {:ok, content} <- [File.read(f)],
          {line, idx} <- Enum.with_index(String.split(content, "\n"), 1),
          Regex.match?(regex, line) do
        "#{Path.relative_to(f, base)}:#{idx}: #{line}"
      end

    {:ok, (["Found matches for pattern \"#{pattern}\" in path \"#{Path.relative_to_cwd(base)}\":\n\n"] ++ lines) |> Enum.join("\n")}
  end

  defp collect_files(base, nil) do
    Path.wildcard(Path.join(base, "**/*")) |> Enum.filter(&File.regular?/1)
  end

  defp collect_files(base, include) do
    Path.wildcard(Path.join(base, include)) |> Enum.filter(&File.regular?/1)
  end

  defp format_search_output(base, out) do
    header = "Found matches in #{Path.relative_to_cwd(base)}:\n\n"
    header <> out
  end

  defp classify_file(path) do
    cond do
      Util.text_file?(path) -> :text
      Util.image_or_pdf?(path) and Util.small_binary?(path) -> :inline
      true -> :binary
    end
  end
end
