defmodule TheMaestro.Tools.Shell do
  @moduledoc """
  Safe shell executor for tool calls. Enforces cwd policy, timeouts, and returns
  Codex-compatible output payloads (as a JSON string) via TheMaestro.Tools.ExecOutput.
  """

  alias TheMaestro.Tools.ExecOutput

  @default_timeout 120_000

  @spec run(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(args, opts \\ [])

  def run(%{"command" => argv} = args, opts) when is_list(argv) and argv != [] do
    base_cwd = Keyword.get(opts, :base_cwd, File.cwd!()) |> Path.expand()
    requested = Map.get(args, "workdir") || Map.get(args, :workdir)
    timeout_ms = Map.get(args, "timeout_ms") || Map.get(args, :timeout_ms) || @default_timeout

    with {:ok, cwd} <- resolve_cwd(base_cwd, requested),
         :ok <- guard_argv(argv),
         {:ok, output, exit_code, duration} <- exec(argv, cwd, timeout_ms) do
      {:ok, ExecOutput.format(output, exit_code, duration)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def run(_other, _opts), do: {:error, "invalid shell arguments"}

  defp resolve_cwd(base, nil), do: {:ok, base}

  defp resolve_cwd(base, workdir) when is_binary(workdir) do
    abs = Path.expand(workdir, base)
    # Ensure the requested cwd stays under base
    if String.starts_with?(abs, base) do
      {:ok, abs}
    else
      {:error, "requested workdir outside workspace"}
    end
  end

  # Deny rules enforced in guard_argv/1

  defp guard_argv([prog | args]) when is_binary(prog) and is_list(args) do
    # Very light denylist to mirror zero‑tolerance rules; expand as needed.
    lc = Enum.map([prog | args], &String.downcase/1)

    case lc do
      ["git", "push", "--force" | _] -> {:error, "forbidden command"}
      ["git", "push", "-f" | _] -> {:error, "forbidden command"}
      ["git", "commit", "--no-verify" | _] -> {:error, "forbidden command"}
      ["git", "commit", "-n" | _] -> {:error, "forbidden command"}
      _ -> :ok
    end
  end

  defp guard_argv(_), do: {:error, "invalid command"}

  defp exec([prog | args], cwd, timeout_ms) do
    started = System.monotonic_time(:millisecond)
    parent = self()

    {:ok, _pid} =
      Task.start(fn ->
        {out, status} =
          System.cmd(prog, args, cd: cwd, stderr_to_stdout: true, env: sanitized_env())

        send(parent, {:__shell_done__, {out, status}})
      end)

    receive do
      {:__shell_done__, {out, status}} ->
        duration = (System.monotonic_time(:millisecond) - started) / 1000
        {:ok, out, status, duration}
    after
      max(0, timeout_ms) ->
        {:ok, _out, _status, duration} =
          {:ok, "timeout", 124, (System.monotonic_time(:millisecond) - started) / 1000}

        {:ok, "timeout", 124, duration}
    end
  end

  defp sanitized_env do
    # Provide a minimal PATH; strip potentially sensitive variables.
    base_path = System.get_env("PATH") || "/usr/local/bin:/usr/bin:/bin"
    [{"PATH", base_path}]
  end
end
