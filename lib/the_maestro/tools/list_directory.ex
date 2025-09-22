defmodule TheMaestro.Tools.ListDirectory do
  @moduledoc """
  List a directory with `ls -la` semantics using the shell tool.
  """

  alias TheMaestro.Tools.{PathResolver, Shell}

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ []) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())

    case PathResolver.resolve_dir(Map.get(args, "path"), base) do
      {:ok, path} ->
        Shell.run(%{"command" => ["bash", "-lc", "ls -la"], "workdir" => path}, base_cwd: base)

      {:error, :outside_workspace} ->
        {:error, "requested path outside workspace"}

      {:error, :not_found} ->
        {:error, "directory not found"}

      {:error, :invalid} ->
        {:error, "invalid directory"}

      {:error, _} ->
        {:error, "invalid arguments"}
    end
  end
end
