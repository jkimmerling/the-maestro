defmodule TheMaestro.Tools.Shell do
  @moduledoc false
  alias TheMaestro.Tools.ExecOutput

  @default_timeout 120_000

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(%{"command" => argv} = args, opts) when is_list(argv) and argv != [] do
    base = Keyword.get(opts, :base_cwd, File.cwd!()) |> Path.expand()
    requested = Map.get(args, "workdir") || Map.get(args, :workdir)
    timeout_ms = Map.get(args, "timeout_ms") || Map.get(args, :timeout_ms) || @default_timeout

    with {:ok, cwd} <- resolve_cwd(base, requested),
         :ok <- guard(argv),
         {:ok, out, code, dur} <- exec(argv, cwd, timeout_ms) do
      {:ok, ExecOutput.format(out, code, dur)}
    else
      {:error, r} -> {:error, r}
    end
  end

  def run(_, _), do: {:error, "invalid shell arguments"}

  defp resolve_cwd(base, nil), do: {:ok, base}
  defp resolve_cwd(base, dir) when is_binary(dir) do
    abs = Path.expand(dir, base)
    if String.starts_with?(abs, base), do: {:ok, abs}, else: {:error, "requested workdir outside workspace"}
  end

  defp guard([prog | args]) when is_binary(prog) and is_list(args) do
    lc = Enum.map([prog | args], &String.downcase/1)
    case lc do
      ["git", "push", "--force" | _] -> {:error, "forbidden command"}
      ["git", "push", "-f" | _] -> {:error, "forbidden command"}
      ["git", "commit", "--no-verify" | _] -> {:error, "forbidden command"}
      ["git", "commit", "-n" | _] -> {:error, "forbidden command"}
      _ -> :ok
    end
  end
  defp guard(_), do: {:error, "invalid command"}

  defp exec([prog | args], cwd, timeout_ms) do
    t0 = System.monotonic_time(:millisecond)
    parent = self()
    {:ok, _pid} = Task.start(fn ->
      {out, code} = System.cmd(prog, args, cd: cwd, stderr_to_stdout: true, env: [{"PATH", System.get_env("PATH") || "/usr/local/bin:/usr/bin:/bin"}])
      send(parent, {:done, out, code})
    end)

    receive do
      {:done, out, code} -> {:ok, out, code, (System.monotonic_time(:millisecond) - t0) / 1000}
    after
      max(0, timeout_ms) -> {:ok, "timeout", 124, (System.monotonic_time(:millisecond) - t0) / 1000}
    end
  end
end

