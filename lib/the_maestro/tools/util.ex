defmodule TheMaestro.Tools.Util do
  @moduledoc "Utilities for path safety, file reading, and environment checks."

  @spec working_root(map()) :: binary()
  def working_root(agent) do
    wd = Map.get(agent, :working_directory) || Map.get(agent, "working_directory")
    wd || File.cwd!()
  end

  @spec within_root?(binary(), binary()) :: boolean()
  def within_root?(root, path) do
    abs_root = Path.expand(root)
    abs_path = Path.expand(path)
    String.starts_with?(abs_path, abs_root)
  end

  @spec safe_expand(binary(), binary()) :: {:ok, binary()} | {:error, :outside_root}
  def safe_expand(root, path) do
    abs_root = Path.expand(root)
    abs_path = Path.expand(Path.join(abs_root, path))
    if String.starts_with?(abs_path, abs_root), do: {:ok, abs_path}, else: {:error, :outside_root}
  end

  @spec text_file?(binary()) :: boolean()
  def text_file?(path) do
    ext = String.downcase(Path.extname(path))
    text_exts = [
      ".ex", ".exs", ".md", ".txt", ".json", ".yml", ".yaml",
      ".js", ".ts", ".tsx", ".css", ".html", ".heex", ".leex",
      ".rs", ".py", ".rb", ".go", ".java", ".c", ".h", ".cpp",
      ".sh", ".sql"
    ]
    ext in text_exts
  end

  @spec small_binary?(binary()) :: boolean()
  def small_binary?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size <= 256 * 1024
      _ -> false
    end
  end

  @spec image_or_pdf?(binary()) :: boolean()
  def image_or_pdf?(path) do
    ext = String.downcase(Path.extname(path))
    ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".pdf"]
  end
end
