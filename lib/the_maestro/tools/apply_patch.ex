defmodule TheMaestro.Tools.ApplyPatch do
  @moduledoc """
  Full `apply_patch` tool using a dedicated parser and runner.
  """

  alias TheMaestro.Tools.ApplyPatch.Runner
  alias TheMaestro.Tools.ExecOutput

  @type result :: {:ok, String.t()} | {:error, String.t()}

  @spec run(String.t(), keyword()) :: result
  def run(patch, opts \\ [])

  def run(patch, opts) when is_binary(patch) do
    base = Keyword.get(opts, :base_cwd, File.cwd!()) |> Path.expand()

    case Runner.apply(patch, base_cwd: base) do
      {:ok, %{added: _a, modified: _m, deleted: _d} = res} ->
        summary = Runner.format_summary(Map.take(res, [:added, :modified, :deleted]), base)
        {:ok, ExecOutput.format(summary, 0, 0.0)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def run(_other, _opts), do: {:error, "invalid patch input"}
end
