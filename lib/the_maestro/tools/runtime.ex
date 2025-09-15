defmodule TheMaestro.Tools.Runtime do
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  # credo:disable-for-this-file Credo.Check.Refactor.CondStatements
  @moduledoc """
  Unified tool runtime used by AgentLoop and LiveView.

  Provides a single dispatch point for executing provider tool calls by name,
  returning a consistent result tuple.
  """

  alias TheMaestro.Tools.{ApplyPatch, PathResolver, Shell}
  require Logger

  @type exec_result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Execute a tool by `name` with `args_json` (string) in `base_cwd`.

  Overloads:
  - exec(name, args_json, base_cwd) – legacy path (no MCP routing)
  - exec(session_id, name, args_json, base_cwd) – preferred (enables MCP routing)

  Returns `{:ok, payload}` or `{:error, reason}`. The `payload` is a string.
  """
  @spec exec(String.t() | atom(), String.t() | nil, String.t()) :: exec_result
  def exec(name, args_json, base_cwd) do
    if System.get_env("HTTP_DEBUG") in ["1", "true", "TRUE"] do
      Logger.debug("[tools] exec name=#{inspect(name)} cwd=#{base_cwd}")
    end

    dispatch(to_string(name) |> String.downcase(), args_json || "{}", base_cwd)
  end

  @spec exec(String.t(), String.t() | atom(), String.t() | nil, String.t()) :: exec_result
  def exec(session_id, name, args_json, base_cwd) when is_binary(session_id) do
    if System.get_env("HTTP_DEBUG") in ["1", "true", "TRUE"] do
      Logger.debug("[tools] exec session_id=#{session_id} name=#{inspect(name)} cwd=#{base_cwd}")
    end

    dispatch_with_session(session_id, to_string(name) |> String.downcase(), args_json || "{}", base_cwd)
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

  defp dispatch("glob", args_json, base_cwd) do
    case safe_decode(args_json) do
      {:ok, args} -> exec_glob(args, base_cwd)
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch("grep", args_json, base_cwd) do
    case safe_decode(args_json) do
      {:ok, args} -> exec_grep(args, base_cwd)
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch(other, _args_json, _cwd), do: {:error, "unsupported tool: #{other}"}

  # Same as dispatch/3 but with MCP fallback using the session registry
  defp dispatch_with_session(session_id, name, args_json, base_cwd) do
    case do_dispatch_known(name, args_json, base_cwd) do
      {:unknown, ^name} ->
        # Try MCP registry resolution
        case TheMaestro.MCP.Registry.resolve(session_id, name) do
          {:ok, %{server: server_key, mcp_tool_name: tool}} ->
            with {:ok, args} <- safe_decode(args_json) do
              TheMaestro.MCP.Client.call_tool(session_id, server_key, tool, args)
            else
              {:error, reason} -> {:error, reason}
            end

          :error -> {:error, "unsupported tool: #{name}"}
        end

      other -> other
    end
  end

  defp do_dispatch_known(name, args_json, base_cwd) do
    case name do
      "read" -> dispatch("read", args_json, base_cwd)
      "bash" -> dispatch("bash", args_json, base_cwd)
      "shell" -> dispatch("shell", args_json, base_cwd)
      "run_shell_command" -> dispatch("run_shell_command", args_json, base_cwd)
      "list_directory" -> dispatch("list_directory", args_json, base_cwd)
      "apply_patch" -> dispatch("apply_patch", args_json, base_cwd)
      "glob" -> dispatch("glob", args_json, base_cwd)
      "grep" -> dispatch("grep", args_json, base_cwd)
      _ -> {:unknown, name}
    end
  end

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
        # Fast path: if absolute and exists, accept immediately to avoid false negatives
        # if the caller's base_cwd has drifted. Confinement is still enforced for relative paths.
        cond do
          Path.type(path) == :absolute and File.exists?(path) ->
            {:ok, path}

          true ->
            case PathResolver.resolve_existing(path, base_cwd) do
              {:ok, abs} -> {:ok, abs}
              {:error, :not_found} -> {:error, "enoent"}
              {:error, :outside_workspace} -> {:error, "requested path outside workspace"}
              {:error, :missing} -> {:error, "missing file_path"}
            end
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
    path_like = Map.get(args, "path")

    case PathResolver.resolve_dir(path_like, base_cwd) do
      {:ok, path} ->
        shell_args = %{"command" => ["bash", "-lc", "ls -la"], "workdir" => path}
        Shell.run(shell_args, base_cwd: base_cwd)

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

  # ===== Glob implementation =====
  defp exec_glob(args, base_cwd) do
    pattern = Map.get(args, "pattern") || Map.get(args, :pattern)
    path_like = Map.get(args, "path") || Map.get(args, :path)

    cond do
      !is_binary(pattern) or String.trim(pattern) == "" ->
        {:error, "missing pattern"}

      true ->
        case PathResolver.resolve_dir(path_like, base_cwd) do
          {:ok, base_path} ->
            combined =
              if Path.type(pattern) == :absolute do
                # Allow absolute only if inside workspace; resolve and re-root to base
                case PathResolver.resolve(pattern, base_cwd) do
                  {:ok, abs} -> abs
                  {:error, :outside_workspace} -> return_outside_workspace()
                  _ -> Path.join(base_path, pattern)
                end
              else
                Path.join(base_path, pattern)
              end

            # If pattern lacks a directory, search recursively
            recursive_pattern =
              if String.contains?(pattern, "/") do
                combined
              else
                Path.join(base_path, "**/" <> pattern)
              end

            matches = Path.wildcard(recursive_pattern, match_dot: true)

            # Filter to keep inside workspace only, and convert to relative
            rel =
              matches
              |> Enum.filter(&PathResolver.under_workspace?(&1, base_cwd))
              |> Enum.map(&Path.relative_to(&1, base_cwd))

            payload = Jason.encode!(%{"matches" => rel, "count" => length(rel)})
            {:ok, payload}

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

  defp return_outside_workspace, do: {:error, "requested path outside workspace"}

  # ===== Grep implementation =====
  defp exec_grep(args, base_cwd) do
    pattern = Map.get(args, "pattern") || Map.get(args, :pattern)
    path_like = Map.get(args, "path") || Map.get(args, :path)

    cond do
      !is_binary(pattern) or String.trim(pattern) == "" ->
        {:error, "missing pattern"}

      true ->
        case PathResolver.resolve_dir(path_like, base_cwd) do
          {:ok, base_path} ->
            max_hits = 500

            {matcher, is_regex} =
              case Regex.compile(pattern) do
                {:ok, re} -> {re, true}
                _ -> {pattern, false}
              end

            files = collect_files(base_path, base_cwd, 10_000)

            {hits, _count} =
              Enum.reduce_while(files, {[], 0}, fn file, {acc, c} ->
                if c >= max_hits do
                  {:halt, {acc, c}}
                else
                  case File.exists?(file) and File.regular?(file) do
                    true ->
                      results = grep_file(file, matcher, is_regex, base_cwd, max_hits - c)
                      nc = c + length(results)
                      {:cont, {acc ++ results, nc}}

                    _ ->
                      {:cont, {acc, c}}
                  end
                end
              end)

            payload =
              hits
              |> Enum.map(fn %{path: p, line: ln, text: t} -> "#{p}:#{ln}: #{t}" end)
              |> Enum.join("\n")

            {:ok, payload}

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

  defp collect_files(dir, base_root, max_count) do
    do_collect_files([dir], base_root, [], 0, max_count)
  end

  defp do_collect_files([], _base, acc, _n, _max), do: Enum.reverse(acc)

  defp do_collect_files([d | rest], base, acc, n, max) when n < max do
    if PathResolver.under_workspace?(d, base) do
      case File.ls(d) do
        {:ok, entries} ->
          {files, dirs} =
            entries
            |> Enum.map(&Path.join(d, &1))
            |> Enum.split_with(&File.regular?/1)

          do_collect_files(rest ++ dirs, base, files ++ acc, n + length(files), max)

        _ ->
          do_collect_files(rest, base, acc, n, max)
      end
    else
      do_collect_files(rest, base, acc, n, max)
    end
  end

  defp grep_file(file, matcher, true = _is_regex, base_root, limit) do
    stream = File.stream!(file, :line, [])
    rel = Path.relative_to(file, base_root)

    stream
    |> Stream.with_index(1)
    |> Stream.filter(fn {line, _i} -> Regex.match?(matcher, line) end)
    |> Enum.take(limit)
    |> Enum.map(fn {line, i} -> %{path: rel, line: i, text: String.trim_trailing(line)} end)
  end

  defp grep_file(file, matcher, false, base_root, limit) when is_binary(matcher) do
    stream = File.stream!(file, :line, [])
    rel = Path.relative_to(file, base_root)

    stream
    |> Stream.with_index(1)
    |> Stream.filter(fn {line, _i} -> String.contains?(line, matcher) end)
    |> Enum.take(limit)
    |> Enum.map(fn {line, i} -> %{path: rel, line: i, text: String.trim_trailing(line)} end)
  end
end
