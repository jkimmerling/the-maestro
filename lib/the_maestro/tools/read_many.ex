defmodule TheMaestro.Tools.ReadMany do
  @moduledoc """
  Read multiple files and concatenate their contents with separators.
  """

  alias TheMaestro.Tools.ReadFile

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ [])

  def run(args, opts) when is_map(args) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())
    files = normalize_files(Map.get(args, "files") || Map.get(args, :files))
    sep = Map.get(args, "separator") || Map.get(args, :separator) || "\n\n"

    if files == [] do
      {:error, "missing files"}
    else
      {:ok, Enum.map(files, &read_or_error(&1, base)) |> Enum.join(sep)}
    end
  end

  def run(_, _), do: {:error, "invalid arguments"}

  defp normalize_files(list) do
    list
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
  end

  defp read_or_error(path, base) do
    case ReadFile.run(%{"file_path" => path}, base_cwd: base) do
      {:ok, bin} -> bin
      {:error, r} -> "[error reading #{path}: #{r}]"
    end
  end
end
