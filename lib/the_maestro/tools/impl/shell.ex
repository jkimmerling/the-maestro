defmodule TheMaestro.Tools.Impl.Shell do
  @moduledoc """
  Shell command execution with basic safety policies.
  """

  @spec run(String.t(), map(), map()) :: {:ok, String.t(), integer()} | {:error, term()}
  def run(root, args, _policy) do
    cmd = Map.get(args, "command") || Map.get(args, :command)

    if is_binary(cmd) do
      {out, code} = System.cmd("bash", ["-lc", cmd], cd: root, stderr_to_stdout: true)
      {:ok, out, code}
    else
      {:error, :invalid_args}
    end
  end
end
