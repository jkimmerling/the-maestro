defmodule TheMaestro.Tools.ToolRegistry do
  @moduledoc """
  Registry of builtin tools exposed to providers.

  Providers query this module to discover the supported tools for a session.
  """

  alias TheMaestro.Tools

  @type spec :: %{name: String.t(), module: module(), description: String.t() | nil}

  @builtin %{
    "read" => %{mod: Tools.ReadFile, desc: "Read a file slice"},
    "read_many" => %{mod: Tools.ReadMany, desc: "Read multiple files"},
    "write_file" => %{mod: Tools.WriteFile, desc: "Write a file"},
    "apply_patch" => %{mod: Tools.ApplyPatch, desc: "Apply a patch envelope"},
    "edit" => %{mod: Tools.Edit, desc: "Find/replace edit"},
    "multi_edit" => %{mod: Tools.MultiEdit, desc: "Multiple edits"},
    "glob" => %{mod: Tools.Glob, desc: "File glob"},
    "grep" => %{mod: Tools.Grep, desc: "Search files"},
    "list_directory" => %{mod: Tools.ListDirectory, desc: "ls -la for a path"},
    "shell" => %{mod: Tools.Shell, desc: "Run a shell command"},
    "run_shell_command" => %{mod: Tools.ShellCommand, desc: "Gemini shell"},
    "web_fetch" => %{mod: Tools.WebFetch, desc: "Fetch a URL"},
    "web_search" => %{mod: Tools.WebSearch, desc: "Search the web"}
  }

  # Optional tools surfaced by Anthropic/Gemini providers
  @optional %{
    "todo_write" => %{mod: Tools.TodoWrite, desc: "Append a todo item"},
    "notebook_edit" => %{mod: Tools.NotebookEdit, desc: "Replace notebook contents"}
  }

  @doc "Return all builtin tool specs as a list."
  @spec list_builtin() :: [spec()]
  def list_builtin do
    all = Map.merge(@builtin, @optional)

    Enum.map(all, fn {name, %{mod: mod, desc: desc}} ->
      %{name: name, module: mod, description: desc}
    end)
  end

  @doc "Lookup a builtin tool module by name."
  @spec lookup(String.t()) :: {:ok, module()} | :error
  def lookup(name) when is_binary(name) do
    case Map.get(Map.merge(@builtin, @optional), name) do
      %{mod: mod} -> {:ok, mod}
      _ -> :error
    end
  end
end
