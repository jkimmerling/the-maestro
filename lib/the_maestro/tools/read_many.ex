defmodule TheMaestro.Tools.ReadMany do
  @moduledoc """
  Read multiple files and concatenate their contents with separators.
  """

  alias TheMaestro.Tools.ReadFile

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ []) when is_map(args) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())

    files =
      (Map.get(args, "files") || Map.get(args, :files) || [])
      |> List.wrap()
      |> Enum.filter(&is_binary/1)

    sep = Map.get(args, "separator") || Map.get(args, :separator) || "\n\n"

    case files do
      [] ->
        {:error, "missing files"}

      _ ->
        contents =
          Enum.map(files, fn p ->
            case ReadFile.run(%{"file_path" => p}, base_cwd: base) do
              {:ok, bin} -> bin
              {:error, r} -> "[error reading #{p}: #{r}]"
            end
          end)

        {:ok, Enum.join(contents, sep)}
    end
  end

  def run(_, _), do: {:error, "invalid arguments"}
end
