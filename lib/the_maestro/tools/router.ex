defmodule TheMaestro.Tools.Router do
  @moduledoc """
  Tool Router: validates policy and dispatches tool calls.
  """

  alias TheMaestro.Tools.TokenEstimator
  alias TheMaestro.Tools.Util
  alias TheMaestro.Tools.Impl.{FileSystem, Shell}

  @type function_call :: %{
          required(:id) => String.t(),
          required(:function) => %{
            required(:name) => String.t(),
            required(:arguments) => String.t() | map()
          }
        }

  @type tool_result :: %{
          text: String.t(),
          inline_data: map() | nil,
          sources: list(map()) | nil,
          meta: map()
        }

  @spec execute(map(), map(), keyword()) :: {:ok, tool_result()} | {:error, term()}
  def execute(agent, call, opts \\ [])

  def execute(agent, call, opts) when is_map(call) do
    with {:ok, name, args, call_id} <- normalize_call(call),
         {:ok, result} <- do_execute(agent, name, args, opts) do
      {:ok,
       Map.merge(
         %{inline_data: nil, sources: [], meta: %{}, name: name, call_id: call_id},
         result
       )}
    end
  end

  def execute(_agent, _call, _opts), do: {:error, :invalid_call}

  defp normalize_call(%{"function" => %{"name" => name, "arguments" => args}} = call) do
    {args_map, _} = safe_decode_args(args)
    {:ok, name, args_map, Map.get(call, "id") || "call_0"}
  end

  defp normalize_call(%{function: %{name: name, arguments: args}} = call) do
    {args_map, _} = safe_decode_args(args)
    {:ok, name, args_map, Map.get(call, :id) || "call_0"}
  end

  defp normalize_call(_), do: {:error, :invalid_call}

  defp safe_decode_args(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, map} when is_map(map) -> {map, :json}
      _ -> {%{}, :invalid}
    end
  end

  defp safe_decode_args(%{} = map), do: {map, :map}
  defp safe_decode_args(_), do: {%{}, :invalid}

  defp do_execute(agent, name, args, opts) do
    root = Util.working_root(agent)
    policy = build_policy(agent)

    dispatch(name, root, policy, args, opts)
  end

  defp dispatch("run_shell_command", root, policy, args, _opts), do: run_shell(root, args, policy)

  defp dispatch("list_directory", root, policy, args, _opts),
    do: list_directory(root, args, policy)

  defp dispatch("read_file", root, policy, args, _opts), do: read_file(root, args, policy)
  defp dispatch("glob", root, _policy, args, _opts), do: glob(root, args)

  defp dispatch("search_file_content", root, _policy, args, _opts),
    do: search_file_content(root, args)

  defp dispatch("write_file", root, policy, args, opts), do: write_file(root, args, policy, opts)
  defp dispatch("replace", root, policy, args, opts), do: replace(root, args, policy, opts)

  defp dispatch("read_many_files", root, policy, args, _opts),
    do: read_many_files(root, args, policy)

  defp dispatch(other, _root, _policy, _args, _opts), do: {:error, {:unknown_tool, other}}

  defp run_shell(root, args, policy) do
    with :ok <- ensure_shell_safe(args, policy),
         {:ok, out, code} <- Shell.run(root, args, policy) do
      {:ok, %{text: shell_text(out, code)}}
    end
  end

  defp list_directory(root, args, _policy) do
    case FileSystem.list_directory(root, path: Map.get(args, "path")) do
      {:ok, text} -> {:ok, %{text: text}}
      {:error, e} -> {:error, e}
    end
  end

  defp read_file(root, args, policy) do
    opts = [
      absolute_path: Map.get(args, "absolute_path") || Map.get(args, "path"),
      offset: Map.get(args, "offset"),
      limit: Map.get(args, "limit"),
      token_cap: policy.token_cap
    ]

    case FileSystem.read_file(root, opts) do
      {:ok, %{text: t}} ->
        {:ok, %{text: TokenEstimator.clamp_to_tokens(t, policy.token_cap)}}

      {:ok, %{inline_data: inline}} ->
        {:ok, %{text: "[binary content omitted]", inline_data: inline}}

      {:error, e} ->
        {:error, e}
    end
  end

  defp write_file(root, args, policy, opts) do
    case ensure_trusted(policy, opts) do
      :ok ->
        case FileSystem.write_file(root,
               file_path: Map.get(args, "file_path"),
               content: Map.get(args, "content")
             ) do
          {:ok, path, bytes} -> {:ok, %{text: "Wrote #{bytes} bytes to #{path}."}}
          {:error, e} -> {:error, e}
        end

      {:error, e} ->
        {:error, e}
    end
  end

  defp replace(_root, _args, _policy, _opts), do: {:error, :unsupported_tool}

  defp glob(root, args) do
    case FileSystem.glob(root, pattern: Map.get(args, "pattern"), path: Map.get(args, "path")) do
      {:ok, files} -> {:ok, %{text: Enum.join(files, "\n")}}
      {:error, e} -> {:error, e}
    end
  end

  defp search_file_content(root, args) do
    case FileSystem.search_file_content(root,
           pattern: Map.get(args, "pattern"),
           path: Map.get(args, "path")
         ) do
      {:ok, text} -> {:ok, %{text: text}}
      {:error, e} -> {:error, e}
    end
  end

  defp read_many_files(root, args, policy) do
    paths =
      case Map.get(args, "paths") do
        list when is_list(list) -> list
        _ -> []
      end

    texts =
      Enum.map(paths, fn p ->
        case FileSystem.read_file(root, absolute_path: p, token_cap: policy.token_cap) do
          {:ok, %{text: t}} -> "# #{p}\n\n" <> t
          {:ok, %{inline_data: _}} -> "# #{p}\n\n[binary file omitted]"
          {:error, _} -> "# #{p}\n\n[error reading file]"
        end
      end)

    {:ok, %{text: Enum.join(texts, "\n\n")}}
  end

  # --- Policy ---
  defp build_policy(agent) do
    tools = Map.get(agent, :tools) || Map.get(agent, "tools") || %{}

    %{
      allow_chaining: Map.get(tools, "allow_chaining", false),
      token_cap: Map.get(tools, "token_cap", 100_000),
      denylist: List.wrap(Map.get(tools, "denylist", [])),
      sudo_allowed: Map.get(tools, "sudo_allowed", false),
      trust: Map.get(tools, "trust", false)
    }
  end

  defp ensure_trusted(policy, opts) do
    if Keyword.get(opts, :trust, false) or policy.trust,
      do: :ok,
      else: {:error, :write_requires_trust}
  end

  defp ensure_shell_safe(%{"command" => cmd}, policy) when is_binary(cmd) do
    cond do
      String.contains?(cmd, ~w(&& || ;)) and not policy.allow_chaining ->
        {:error, :command_chaining_blocked}

      (String.starts_with?(cmd, "sudo") or String.contains?(cmd, " sudo ")) and
          not policy.sudo_allowed ->
        {:error, :sudo_not_allowed}

      denies?(cmd, policy.denylist) ->
        {:error, :denied_by_policy}

      true ->
        :ok
    end
  end

  defp ensure_shell_safe(_, _), do: {:error, :invalid_args}

  defp denies?(cmd, denylist) do
    Enum.any?(denylist, fn
      %Regex{} = rx -> Regex.match?(rx, cmd)
      s when is_binary(s) -> String.contains?(cmd, s)
      _ -> false
    end)
  end

  defp shell_text(out, code) do
    head = if code == 0, do: "[exit 0]\n", else: "[exit #{code}]\n"
    head <> out
  end
end
