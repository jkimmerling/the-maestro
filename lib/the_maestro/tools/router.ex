defmodule TheMaestro.Tools.Router do
  @moduledoc """
  Tool Router: validates permissions and safety, then dispatches to concrete
  tool implementations. This version wires non-destructive tools; remaining tools
  will be implemented next.
  """
  alias TheMaestro.Tools.Impl.FileSystem
  alias TheMaestro.Tools.Util

  @type function_call :: %{
          required(:id) => String.t(),
          required(:function) => %{
            required(:name) => String.t(),
            required(:arguments) => String.t()
          }
        }

  @type tool_result :: %{
          name: String.t(),
          call_id: String.t(),
          text: String.t(),
          inline_data: map() | nil,
          sources: list(map()) | nil,
          meta: map()
        }

  @doc """
  Execute a provider-agnostic function call with the given agent context.

  Returns {:ok, tool_result} or {:error, reason}.
  """
  @spec execute(map(), function_call(), keyword()) :: {:ok, tool_result()} | {:error, term()}
  def execute(agent, %{"function" => %{"name" => name, "arguments" => args}} = call, _opts)
      when is_binary(name) do
    root = Util.working_root(agent)
    call_id = Map.get(call, "id") || "call_0"
    case decode_args(args) do
      {:ok, params} -> do_execute(name, call_id, root, params)
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(agent, %{function: %{name: name, arguments: args}} = call, _opts)
      when is_binary(name) do
    root = Util.working_root(agent)
    call_id = Map.get(call, :id) || "call_0"
    case decode_args(args) do
      {:ok, params} -> do_execute(name, call_id, root, params)
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(_agent, _call, _opts), do: {:error, :invalid_call}

  # ===== Helpers =====
  defp decode_args(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, %{} = m} -> {:ok, m}
      {:ok, _} -> {:error, :arguments_not_object}
      {:error, e} -> {:error, {:invalid_json, e}}
    end
  end
  defp decode_args(%{} = m), do: {:ok, m}
  defp decode_args(_), do: {:ok, %{}}

  defp do_execute("list_directory", call_id, root, params) do
    case FileSystem.list_directory(root, path: Map.get(params, "path", ".")) do
      {:ok, text} -> ok(call_id, "list_directory", text)
      {:error, r} -> {:error, r}
    end
  end

  defp do_execute("read_file", call_id, root, params) do
    opts = [
      absolute_path: Map.get(params, "absolute_path"),
      offset: Map.get(params, "offset"),
      limit: Map.get(params, "limit")
    ]
    case FileSystem.read_file(root, opts) do
      {:ok, %{text: text}} -> ok(call_id, "read_file", text)
      {:ok, %{inline_data: inline}} -> ok_inline(call_id, "read_file", inline)
      {:error, r} -> {:error, r}
    end
  end

  defp do_execute("glob", call_id, root, params) do
    base = Map.get(params, "path")
    case FileSystem.glob(root, pattern: Map.get(params, "pattern"), path: base) do
      {:ok, files} -> ok(call_id, "glob", Enum.join(files, "\n"))
      {:error, r} -> {:error, r}
    end
  end

  defp do_execute("search_file_content", call_id, root, params) do
    case FileSystem.search_file_content(root,
           pattern: Map.fetch!(params, "pattern"),
           path: Map.get(params, "path"),
           include: Map.get(params, "include")
         ) do
      {:ok, text} -> ok(call_id, "search_file_content", text)
      {:error, r} -> {:error, r}
    end
  end

  defp do_execute(name, call_id, _root, _params) do
    ok(call_id, name, "Tool execution pending implementation for '#{name}'.")
  end

  defp ok(call_id, name, text) do
    {:ok, %{name: name, call_id: call_id, text: text, inline_data: nil, sources: [], meta: %{}}}
  end

  defp ok_inline(call_id, name, inline) do
    {:ok, %{name: name, call_id: call_id, text: "", inline_data: inline, sources: [], meta: %{}}}
  end
end
