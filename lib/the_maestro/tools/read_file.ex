defmodule TheMaestro.Tools.ReadFile do
  @moduledoc """
  Read a file with optional byte slicing.
  """

  alias TheMaestro.Tools.PathResolver

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ [])

  def run(args, opts) when is_map(args) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())

    case fetch_file_path(args, base) do
      {:ok, path} -> read_and_slice(path, args)
      {:error, reason} -> {:error, reason}
    end
  end

  def run(_, _), do: {:error, "invalid arguments"}

  defp fetch_file_path(args, base) do
    case Map.get(args, "file_path") || Map.get(args, :file_path) do
      path when is_binary(path) and path != "" -> resolve_existing_path(path, base)
      _ -> {:error, "missing file_path"}
    end
  end

  defp resolve_existing_path(path, base) do
    if absolute_path?(path) do
      if File.exists?(path), do: {:ok, path}, else: {:error, "enoent"}
    else
      resolve_relative_path(path, base)
    end
  end

  defp absolute_path?(path), do: Path.type(path) == :absolute

  defp resolve_relative_path(path, base) do
    case PathResolver.resolve_existing(path, base) do
      {:ok, abs} -> {:ok, abs}
      {:error, :not_found} -> {:error, "enoent"}
      {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
      {:error, :missing} -> {:error, "missing file_path"}
    end
  end

  defp read_and_slice(path, args) do
    case File.read(path) do
      {:ok, content} -> {:ok, slice(content, args)}
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  defp slice(content, args) do
    offset = normalize_int(Map.get(args, "offset") || Map.get(args, :offset))
    limit = normalize_int(Map.get(args, "limit") || Map.get(args, :limit))
    slice_string(content, offset, limit)
  end

  defp normalize_int(nil), do: nil
  defp normalize_int(v) when is_integer(v), do: v
  defp normalize_int(v) when is_float(v), do: trunc(v)

  defp normalize_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      _ -> nil
    end
  end

  defp slice_string(content, nil, nil), do: content

  defp slice_string(content, off, nil) when is_integer(off) and off >= 0,
    do: binary_part_safe(content, off, byte_size(content) - off)

  defp slice_string(content, off, lim)
       when is_integer(off) and is_integer(lim) and off >= 0 and lim >= 0,
       do: binary_part_safe(content, off, lim)

  defp slice_string(content, _o, _l), do: content

  defp binary_part_safe(bin, start, len) do
    size = byte_size(bin)
    s = min(max(start, 0), size)
    l = min(max(len, 0), size - s)
    binary_part(bin, s, l)
  end
end
