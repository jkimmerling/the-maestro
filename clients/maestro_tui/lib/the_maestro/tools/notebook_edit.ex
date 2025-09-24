defmodule TheMaestro.Tools.NotebookEdit do
  @moduledoc false

  alias TheMaestro.Tools.{ExecOutput, PathResolver}

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ []) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())

    with {:ok, path} <- resolve_path(args, base),
         :ok <- ensure_ipynb(path),
         {:ok, mode} <- normalize_mode(args),
         {:ok, nb} <- read_notebook(path),
         {:ok, index} <- pick_index(nb, args, mode),
         {:ok, nb2} <- apply_edit(nb, index, args, mode),
         :ok <- write_notebook(path, nb2) do
      rel = rel(path, base)
      {:ok, ExecOutput.format("notebook edited: #{rel}@#{index}", 0, 0.0)}
    end
  end

  defp resolve_path(args, base) do
    case Map.get(args, "notebook_path") || Map.get(args, :notebook_path) do
      p when is_binary(p) ->
        case PathResolver.resolve(p, base) do
          {:ok, abs} -> {:ok, abs}
          {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
          _ -> {:error, "invalid notebook_path"}
        end

      _ ->
        {:error, "missing notebook_path"}
    end
  end

  defp ensure_ipynb(path) do
    cond do
      not File.exists?(path) -> {:error, "notebook not found"}
      Path.extname(path) != ".ipynb" -> {:error, "file must be .ipynb"}
      true -> :ok
    end
  end

  defp normalize_mode(args) do
    case Map.get(args, "edit_mode") || Map.get(args, :edit_mode) || "replace" do
      m when m in ["replace", "insert", "delete"] -> {:ok, m}
      _ -> {:error, "invalid edit_mode"}
    end
  end

  defp read_notebook(path) do
    case File.read(path) do
      {:ok, bin} ->
        case Jason.decode(bin) do
          {:ok, %{"cells" => _} = nb} -> {:ok, nb}
          _ -> {:error, "invalid notebook json"}
        end

      {:error, r} ->
        {:error, to_string(r)}
    end
  end

  defp pick_index(%{"cells" => cells}, args, mode) do
    cid = Map.get(args, "cell_id") || Map.get(args, :cell_id)

    cond do
      cid in [nil, ""] -> if mode == "insert", do: {:ok, 0}, else: {:error, "cell_id required unless inserting"}
      is_integer(cid) -> {:ok, clamp_index(cid, length(cells))}
      is_binary(cid) -> pick_index_from_string(cid, cells)
      true -> {:error, "cell_id required unless inserting"}
    end
  end

  defp pick_index_from_string(cid, cells) do
    case Integer.parse(cid) do
      {i, _} -> {:ok, clamp_index(i, length(cells))}
      :error -> pick_index_by_cell_id(cid, cells)
    end
  end

  defp pick_index_by_cell_id(cid, cells) do
    idx = Enum.find_index(cells, fn c -> Map.get(c, "id") == cid end)
    if is_nil(idx), do: {:error, "cell id not found"}, else: {:ok, idx}
  end

  defp clamp_index(i, _len) when i < 0, do: 0
  defp clamp_index(i, len) when i > len, do: len
  defp clamp_index(i, _len), do: i

  defp apply_edit(nb, idx, args, mode) when mode in ["replace", "insert", "delete"] do
    case mode do
      "delete" -> do_delete(nb, idx)
      "insert" -> do_insert(nb, idx, args)
      "replace" -> do_replace(nb, idx, args)
    end
  end

  defp do_delete(nb, idx), do: {:ok, update_in(nb, ["cells"], &List.delete_at(&1, idx))}

  defp do_insert(nb, idx, args) do
    cell_type = (Map.get(args, "cell_type") || Map.get(args, :cell_type) || "code") |> to_string()

    case get_source(args) do
      {:ok, new_source} ->
        cell = new_cell(new_source, cell_type, nil)
        {:ok, update_in(nb, ["cells"], &List.insert_at(&1, idx, cell))}

      {:error, r} ->
        {:error, r}
    end
  end

  defp do_replace(nb, idx, args) do
    with {:ok, new_source} <- get_source(args) do
      cells = nb["cells"] || []
      cell = Enum.at(cells, idx)

      if is_nil(cell) do
        cell = new_cell(new_source, Map.get(args, "cell_type") || "code", nil)
        {:ok, update_in(nb, ["cells"], &List.insert_at(&1, idx, cell))}
      else
        cell2 =
          cell
          |> Map.put("source", new_source)
          |> maybe_reset_code_outputs()

        {:ok, put_in(nb["cells"][idx], cell2)}
      end
    end
  end

  defp get_source(args) do
    case Map.get(args, "new_source") || Map.get(args, :new_source) do
      s when is_binary(s) -> {:ok, s}
      _ -> {:error, "missing new_source"}
    end
  end

  defp new_cell(src, "markdown", id) do
    %{"cell_type" => "markdown", "id" => id, "source" => src, "metadata" => %{}}
  end

  defp new_cell(src, _other, id) do
    %{
      "cell_type" => "code",
      "id" => id,
      "source" => src,
      "metadata" => %{},
      "execution_count" => nil,
      "outputs" => []
    }
  end

  defp maybe_reset_code_outputs(%{"cell_type" => "code"} = cell) do
    cell
    |> Map.put("execution_count", nil)
    |> Map.put("outputs", [])
  end

  defp maybe_reset_code_outputs(cell), do: cell

  defp write_notebook(path, nb) do
    json = Jason.encode!(nb, pretty: true)
    File.write(path, json)
  end

  defp rel(path, base) do
    case Path.relative_to(path, base) do
      ^path -> path
      r -> r
    end
  end
end

