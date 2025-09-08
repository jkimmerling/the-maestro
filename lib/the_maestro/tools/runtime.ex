defmodule TheMaestro.Tools.Runtime do
  @moduledoc """
  Unified tool runtime used by AgentLoop and LiveView.

  Provides a single dispatch point for executing provider tool calls by name,
  returning a consistent result tuple.
  """

  alias TheMaestro.Tools.{ApplyPatch, Shell}

  @type exec_result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Execute a tool by `name` with `args_json` (string) in `base_cwd`.

  Returns `{:ok, payload}` or `{:error, reason}`. The `payload` is a string:
  - for shell-like tools, JSON produced by ExecOutput.format/3
  - for read, the raw file contents (optionally sliced)
  """
  @spec exec(String.t() | atom(), String.t() | nil, String.t()) :: exec_result
  def exec(name, args_json, base_cwd) do
    dispatch(to_string(name) |> String.downcase(), args_json || "{}", base_cwd)
  end

  # Split per-tool to keep complexity low
  defp dispatch("read", args_json, base_cwd) do
    case safe_decode(args_json) do
      {:ok, args} -> exec_read(args, base_cwd)
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch("bash", args_json, base_cwd) do
    case safe_decode(args_json) do
      {:ok, args} ->
        case bash_to_shell_args(args) do
          {:ok, shell_args} -> Shell.run(shell_args, base_cwd: base_cwd)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp dispatch("shell", args_json, base_cwd) do
    case safe_decode(args_json) do
      {:ok, args} -> Shell.run(args, base_cwd: base_cwd)
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch("run_shell_command", args_json, base_cwd) do
    case safe_decode(args_json) do
      {:ok, args} -> run_shell_command(args, base_cwd)
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch("list_directory", args_json, base_cwd) do
    case safe_decode(args_json) do
      {:ok, args} -> list_directory(args, base_cwd)
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch("apply_patch", args_json, base_cwd) do
    case safe_decode(args_json) do
      {:ok, args} ->
        case Map.get(args, "input") do
          input when is_binary(input) -> ApplyPatch.run(input, base_cwd: base_cwd)
          _ -> {:error, "invalid apply_patch arguments"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp dispatch(other, _args_json, _cwd), do: {:error, "unsupported tool: #{other}"}

  # ===== helpers =====

  defp safe_decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, "invalid tool arguments"}
    end
  end

  # read tool
  defp exec_read(args, base_cwd) do
    with {:ok, abs} <- ensure_file_path(args, base_cwd),
         {:ok, content} <- read_file(abs) do
      off = normalize_int(Map.get(args, "offset") || Map.get(args, :offset))
      lim = normalize_int(Map.get(args, "limit") || Map.get(args, :limit))
      {:ok, slice_string(content, off, lim)}
    end
  end

  defp ensure_file_path(args, base_cwd) do
    case Map.get(args, "file_path") || Map.get(args, :file_path) do
      path when is_binary(path) ->
        trimmed = String.trim(path)

        if trimmed == "" do
          {:error, "missing file_path"}
        else
          abs = Path.expand(trimmed, base_cwd)
          under_workspace(abs, base_cwd)
        end

      _ ->
        {:error, "missing file_path"}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  defp under_workspace(abs, base) do
    if String.starts_with?(abs, base),
      do: {:ok, abs},
      else: {:error, "requested path outside workspace"}
  end

  defp normalize_int(nil), do: nil
  defp normalize_int(v) when is_integer(v), do: v
  defp normalize_int(v) when is_float(v), do: trunc(v)

  defp normalize_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      _ -> nil
    end
  end

  defp slice_string(content, nil, nil), do: content

  defp slice_string(content, off, nil) when is_integer(off) and off >= 0 do
    binary_part_safe(content, off, byte_size(content) - off)
  end

  defp slice_string(content, off, lim)
       when is_integer(off) and is_integer(lim) and off >= 0 and lim >= 0 do
    binary_part_safe(content, off, lim)
  end

  defp slice_string(content, _off, _lim), do: content

  defp binary_part_safe(bin, start, len) do
    size = byte_size(bin)
    s = min(max(start, 0), size)
    l = min(max(len, 0), size - s)
    binary_part(bin, s, l)
  end

  # bash tool → shell args
  defp bash_to_shell_args(args) when is_map(args) do
    case Map.get(args, "command") do
      cmd when is_binary(cmd) ->
        timeout = Map.get(args, "timeout")
        shell_args = %{"command" => ["bash", "-lc", cmd]}
        {:ok, maybe_put_timeout(shell_args, timeout)}

      _ ->
        {:error, "invalid bash arguments"}
    end
  end

  defp maybe_put_timeout(map, t) when is_integer(t) and t > 0, do: Map.put(map, "timeout_ms", t)

  defp maybe_put_timeout(map, t) when is_float(t) and t > 0.0,
    do: Map.put(map, "timeout_ms", trunc(t))

  defp maybe_put_timeout(map, _), do: map

  # gemini-compatible helpers
  defp run_shell_command(args, base_cwd) do
    cmd = Map.get(args, "command")
    dir = Map.get(args, "directory")

    if is_binary(cmd) and byte_size(String.trim(cmd)) > 0 do
      shell_args = %{"command" => ["bash", "-lc", cmd]}

      shell_args =
        if is_binary(dir) and dir != "", do: Map.put(shell_args, "workdir", dir), else: shell_args

      Shell.run(shell_args, base_cwd: base_cwd)
    else
      {:error, "missing command"}
    end
  end

  defp list_directory(args, base_cwd) do
    path = Map.get(args, "path") || base_cwd
    path = Path.expand(path, base_cwd)
    shell_args = %{"command" => ["bash", "-lc", "ls -la"], "workdir" => path}
    Shell.run(shell_args, base_cwd: base_cwd)
  end
end
