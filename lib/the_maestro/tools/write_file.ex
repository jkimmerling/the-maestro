defmodule TheMaestro.Tools.WriteFile do
  @moduledoc """
  Simple file writer used by tool calls. Ensures writes stay under the
  provided workspace root, creates intermediate directories, and mirrors the
  JSON payload structure expected by Codex/Gemini style agents.
  """

  alias TheMaestro.Tools.{ExecOutput, PathResolver}

  @type result :: {:ok, String.t()} | {:error, String.t()}

  @spec run(map(), keyword()) :: result
  def run(params, opts \\ [])

  def run(params, opts) when is_map(params) do
    base = Keyword.get(opts, :base_cwd, File.cwd!()) |> Path.expand()
    started = System.monotonic_time(:millisecond)

    with {:ok, path} <- fetch_path(params),
         {:ok, abs_path} <- resolve_path(path, base),
         :ok <- ensure_directory(abs_path),
         {:ok, content} <- fetch_content(params),
         :ok <- write_file(abs_path, content) do
      duration = (System.monotonic_time(:millisecond) - started) / 1000
      summary = success_message(abs_path, base, content)
      {:ok, ExecOutput.format(summary, 0, duration)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def run(_other, _opts), do: {:error, "invalid write arguments"}

  defp fetch_path(params) do
    path_like =
      Map.get(params, "file_path") ||
        Map.get(params, "path") ||
        Map.get(params, "absolute_path") ||
        Map.get(params, :file_path) ||
        Map.get(params, :path) ||
        Map.get(params, :absolute_path)

    case path_like do
      path when is_binary(path) ->
        if String.trim(path) == "" do
          {:error, "missing file path"}
        else
          {:ok, path}
        end

      _ ->
        {:error, "missing file path"}
    end
  end

  defp resolve_path(path, base) do
    case PathResolver.resolve(path, base) do
      {:ok, resolved} -> {:ok, resolved}
      {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
      {:error, :missing} -> {:error, "missing file path"}
      {:error, other} -> {:error, format_error(other)}
    end
  end

  defp fetch_content(params) do
    case Map.get(params, "content") || Map.get(params, :content) do
      content when is_binary(content) -> {:ok, content}
      other when is_nil(other) -> {:error, "missing content"}
      other -> {:ok, to_string(other)}
    end
  end

  defp ensure_directory(path) do
    case File.mkdir_p(Path.dirname(path)) do
      :ok -> :ok
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  defp write_file(path, content) do
    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  defp success_message(abs_path, base, content) do
    rel =
      case Path.relative_to(abs_path, base) do
        ^abs_path -> abs_path
        relative -> relative
      end

    bytes = byte_size(content)
    lines = content |> String.split("\n", trim: false) |> length()
    "wrote #{bytes} bytes (#{lines} lines) to #{rel}"
  end

  defp format_error(reason) when is_atom(reason) do
    :file.format_error(reason) |> List.to_string()
  end

  defp format_error(reason), do: to_string(reason)
end
