defmodule TheMaestro.Tools.ShellCommand do
  @moduledoc """
  Gemini-compatible wrapper for `run_shell_command`.
  """

  alias TheMaestro.Tools.Shell

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ []) do
    base = Keyword.get(opts, :base_cwd, File.cwd!())
    cmd = Map.get(args, "command")
    dir = Map.get(args, "directory")

    if is_binary(cmd) and String.trim(cmd) != "" do
      shell_args = %{"command" => ["bash", "-lc", cmd]}

      shell_args =
        if is_binary(dir) and dir != "", do: Map.put(shell_args, "workdir", dir), else: shell_args

      Shell.run(shell_args, base_cwd: base)
    else
      {:error, "missing command"}
    end
  end
end
