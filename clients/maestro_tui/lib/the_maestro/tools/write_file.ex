defmodule TheMaestro.Tools.WriteFile do
  @moduledoc false
  alias TheMaestro.Tools.{ExecOutput, PathResolver}

  @type result :: {:ok, String.t()} | {:error, String.t()}

  @spec run(map(), keyword()) :: result
  def run(params, opts) when is_map(params) do
    base = Keyword.get(opts, :base_cwd, File.cwd!()) |> Path.expand()
    t0 = System.monotonic_time(:millisecond)

    with {:ok, path} <- fetch_path(params),
         {:ok, abs} <- resolve(path, base),
         :ok <- File.mkdir_p(Path.dirname(abs)),
         {:ok, content} <- fetch_content(params),
         :ok <- File.write(abs, content) do
      dur = (System.monotonic_time(:millisecond) - t0) / 1000
      rel = case Path.relative_to(abs, base) do ^abs -> abs; r -> r end
      {:ok, ExecOutput.format("wrote #{byte_size(content)} bytes to #{rel}", 0, dur)}
    else
      {:error, r} -> {:error, to_string(r)}
    end
  end
  def run(_, _), do: {:error, "invalid write arguments"}

  defp fetch_path(m) do
    p = m["file_path"] || m["path"] || m[:file_path] || m[:path]
    if is_binary(p) and String.trim(p) != "", do: {:ok, p}, else: {:error, "missing file path"}
  end
  defp fetch_content(m) do
    case m["content"] || m[:content] do
      c when is_binary(c) -> {:ok, c}
      nil -> {:error, "missing content"}
      other -> {:ok, to_string(other)}
    end
  end
  defp resolve(p, base) do
    case PathResolver.resolve(p, base) do
      {:ok, abs} -> {:ok, abs}
      {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
      _ -> {:error, "invalid path"}
    end
  end
end

