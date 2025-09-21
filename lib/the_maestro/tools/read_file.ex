defmodule TheMaestro.Tools.ReadFile do
  @moduledoc """
  Read a file with optional byte slicing.
  """

  alias TheMaestro.Tools.PathResolver

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ []) when is_map(args) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())

    with {:ok, path} <- ensure_file_path(args, base),
         {:ok, content} <- read_file(path) do
      off = normalize_int(Map.get(args, "offset") || Map.get(args, :offset))
      lim = normalize_int(Map.get(args, "limit") || Map.get(args, :limit))
      {:ok, slice_string(content, off, lim)}
    else
      {:error, r} -> {:error, to_string(r)}
    end
  end

  def run(_, _), do: {:error, "invalid arguments"}

  defp ensure_file_path(args, base_cwd) do
    case Map.get(args, "file_path") || Map.get(args, :file_path) do
      path when is_binary(path) ->
        cond do
          Path.type(path) == :absolute and File.exists?(path) ->
            {:ok, path}

          true ->
            case PathResolver.resolve_existing(path, base_cwd) do
              {:ok, abs} -> {:ok, abs}
              {:error, :not_found} -> {:error, "enoent"}
              {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
              {:error, :missing} -> {:error, "missing file_path"}
            end
        end

      _ ->
        {:error, "missing file_path"}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, to_string(reason)}
    end
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
