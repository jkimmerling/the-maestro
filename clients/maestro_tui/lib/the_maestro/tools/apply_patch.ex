defmodule TheMaestro.Tools.ApplyPatch do
  @moduledoc false
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
      {:error, r} -> {:error, r}
    end
  end
  def run(_, _), do: {:error, "invalid patch input"}
end

